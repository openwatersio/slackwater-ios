// Slackwater — GPL v3. Tide detail on the iOS scrub model (prototype
// TidesApp.dc.html, not the web's): a FIXED reading line at the center of the
// strip, the continuous multi-day curve panning underneath it. No day pager —
// free panning plus the map header's return-to-now. The schedule below is a
// rolling multi-day list (today → +54h) with day headers; rows scrub, cross-day.
import SwiftUI
import TideEngine

struct TideDetailView: View {
    let record: TideStationRecord
    @AppStorage(unitsKey) private var units = "imperial"

    @State private var live = appNow()
    /// The single scrub time — whatever sits under the centerline.
    @State private var scrubTime = appNow()
    @State private var timeline: TimelineData?

    private var imperial: Bool { units == "imperial" }
    private var tz: TimeZone { record.tz }
    private var unit: String { heightUnit(imperial: imperial) }
    private var scrubHeight: Double { exactHeight(at: scrubTime) }
    private var nextExtreme: TideExtreme? {
        timeline?.tideExtremes.first { $0.time > scrubTime }
    }
    private var rising: Bool { nextExtreme.map { $0.kind == .high } ?? true }
    private var dayOffset: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.dateComponents([.day], from: cal.startOfDay(for: live),
                                  to: cal.startOfDay(for: scrubTime)).day ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                MapHeader(name: record.name, region: record.region,
                          latitude: record.latitude, longitude: record.longitude,
                          favoriteId: record.id,
                          showReturn: abs(scrubTime.timeIntervalSince(live)) > 60,
                          onReturn: returnToNow)
                if let timeline {
                    scrubCard(timeline)
                    scheduleCard(timeline)
                }
                footer
            }
            .padding(.bottom, 42)
        }
        .ignoresSafeArea(edges: .top)
        .background(SN.page.ignoresSafeArea())
        .environment(\.timeZone, tz)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if timeline == nil {
                timeline = TimelineData.build(tide: record, current: nil, now: live)
            }
            RecentsStore.shared.record(record.id)
        }
    }

    // MARK: - Scrub card (readout + pan-under-centerline strip)

    private func scrubCard(_ tl: TimelineData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    MonoLabel(text: "\(relativeDayLabel(dayOffset, scrubTime, tz)) · \(dayLine(scrubTime, tz))", size: 11)
                    Text(cardTime(scrubTime, tz))
                        .font(.fraunces(30, .medium))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                Spacer()
                // Moon for the scrubbed day (prototype scrubMoon + scrubMoonName).
                let moon = SunMoon.moonIllumination(date: scrubTime)
                HStack(spacing: 8) {
                    MoonGlyph(fraction: moon.fraction, waxing: moon.waxing, size: 22)
                    Text(SunMoon.phaseName(phase: moon.phase))
                        .font(.geist(11))
                        .foregroundStyle(SN.foam.opacity(0.6))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 88, alignment: .trailing)
                }
                .padding(.top, 2)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    (Text(formatHeight(scrubHeight, imperial: imperial)).font(.fraunces(34))
                     + Text(" \(unit)").font(.geist(14)))
                        .foregroundStyle(.white)
                    HStack(spacing: 4) {
                        Text(rising ? "▲" : "▼").font(.geist(10))
                        Text(rising ? "Rising" : "Falling").font(.geist(13))
                    }
                    .foregroundStyle(rising ? SN.rising : SN.falling)
                }
                Spacer()
                if let next = nextExtreme {
                    VStack(alignment: .trailing, spacing: 1) {
                        MonoLabel(text: "Next \(next.kind == .high ? "High" : "Low")",
                                  size: 9, color: SN.foam.opacity(0.5), tracking: 1.4)
                        Text("\(formatHeight(next.height, imperial: imperial)) \(unit)")
                            .font(.fraunces(19)).foregroundStyle(SN.foam)
                        Text("in \(countdown(from: scrubTime, to: next.time)) · \(cardTime(next.time, tz))")
                            .font(.geist(12)).foregroundStyle(SN.leaf)
                    }
                }
            }
            .padding(.top, 14)

            TimelineScrubStrip(data: tl, geo: TimelineGeo(data: tl),
                               imperial: imperial, now: live, scrubTime: $scrubTime)
                .padding(.horizontal, -16)  // full-bleed strip (prototype margin 0 -16)
                .padding(.top, 12)

            MonoLabel(text: "‹ swipe to scrub · snaps to high & low ›",
                      size: 9, color: SN.foam.opacity(0.4), tracking: 1.4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(SN.cardFill)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SN.leaf.opacity(0.22)).frame(height: 0.5)
        }
    }

    // MARK: - Rolling multi-day schedule (turns + sun, day-grouped)

    private func scheduleCard(_ tl: TimelineData) -> some View {
        MultiDaySchedule(entries: scheduleEntries(tl), tz: tz, today: tl.today,
                         scrubTime: scrubTime, onTap: { scrubTime = $0 })
            .background(SN.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(SN.cardStroke, lineWidth: 0.5))
            .padding(.horizontal, 16)
    }

    private func scheduleEntries(_ tl: TimelineData) -> [ScheduleEntry] {
        let t0 = tl.today
        let t1 = t0.addingTimeInterval(Timeline.scheduleHours * 3600)
        var out: [ScheduleEntry] = tl.tideExtremes
            .filter { $0.time >= t0 && $0.time <= t1 }
            .map { ScheduleEntry(time: $0.time, pill: $0.kind == .high ? .high : .low,
                                 value: "\(formatHeight($0.height, imperial: imperial)) \(unit)") }
        for day in tl.days {
            for (t, pill) in [(day.sunrise, SchedulePill.sunrise), (day.sunset, .sunset)] {
                if let t, t >= t0, t <= t1 { out.append(ScheduleEntry(time: t, pill: pill)) }
            }
        }
        return out.sorted { $0.time < $1.time }
    }

    // The provenance/confidence marking (chs-online spec §2d, §7d — simplified
    // to plain language, design pass M4.3): lead with where the data came
    // from, keep the honesty clause that the numbers are device-computed. The
    // full clause-10 licence statement carries its weight in Settings.
    private var footer: some View {
        VStack(spacing: 6) {
            MonoLabel(text: "Predictions — not for navigation",
                      size: 10, color: SN.foam.opacity(0.4), tracking: 1.4)
            if record.isChs {
                Text("Chart datum · Downloaded from CHS (IWLS) — computed on this device, not CHS-published numbers")
                    .font(.geist(11)).foregroundStyle(SN.foam.opacity(0.3))
                    .multilineTextAlignment(.center)
            } else {
                Text("\(record.chartDatum) datum · NOAA harmonic prediction")
                    .font(.geist(11)).foregroundStyle(SN.foam.opacity(0.3))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    // MARK: - Data

    /// Engine-exact height — the same call the old model's committed readout
    /// made, so the now-readout is unchanged by the scrub rework.
    private func exactHeight(at t: Date) -> Double {
        record.engineStation.heights(from: t, to: t.addingTimeInterval(1), step: 1).first?.height ?? 0
    }

    private func returnToNow() {
        live = appNow()
        scrubTime = live
    }
}
