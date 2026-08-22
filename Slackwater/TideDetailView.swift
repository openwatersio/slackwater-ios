// Slackwater — GPL v3. Tide detail on the iOS scrub model (prototype
// TidesApp.dc.html, not the web's): a FIXED reading line at the center of the
// strip, the continuous multi-day curve panning underneath it. No day pager —
// free panning plus the map header's return-to-now. The schedule below is a
// rolling list over `Timeline.scheduleRange` — the week hanging off the
// anchor, and the strip is `Timeline.window` over the same anchor — with day
// headers; rows scrub, cross-day.
import SwiftUI
import TideEngine

struct TideDetailView: View {
    let record: TideStationRecord
    @AppStorage(unitsKey, store: AppGroup.defaults) private var units = "imperial"

    @State private var live = appNow()
    /// The single scrub time — whatever sits under the centerline.
    @State private var scrubTime = appNow()
    @State private var timeline: TimelineData?
    /// The local midnight the window hangs from. Only `returnToNow` and (in
    /// Plan B) the range bar move it; everything else reads it.
    @State private var anchor = Date.distantPast

    private var imperial: Bool { units == "imperial" }
    private var tz: TimeZone { record.tz }
    private var unit: String { heightUnit(imperial: imperial) }
    private var scrubHeight: Double { exactHeight(at: scrubTime) }
    private var nextExtreme: TideExtreme? {
        timeline?.tideExtremes.first { $0.time > scrubTime }
    }
    private var rising: Bool { nextExtreme.map { $0.kind == .high } ?? true }
    private var prevExtreme: TideExtreme? {
        timeline?.tideExtremes.last { $0.time <= scrubTime }
    }
    /// m/hr at the scrub time; sign lives in the ▲/▼, display is unsigned.
    private var scrubRate: Double { record.engineStation.rateOfChange(at: scrubTime) }

    var body: some View {
        ScrubDetailScaffold(name: record.name, region: record.region,
                            latitude: record.latitude, longitude: record.longitude,
                            favoriteId: record.id, tz: tz,
                            timeline: timeline, entries: scheduleEntries,
                            live: $live, scrubTime: $scrubTime,
                            onReturn: returnToNow,
                            anchor: $anchor,
                            onPicked: { _ in rebuild() },
                            above: { EmptyView() },
                            card: { tl in
                                readout
                                TimelineScrubStrip(data: tl, geo: TimelineGeo(data: tl),
                                                   imperial: imperial, now: live, scrubTime: $scrubTime)
                                    .padding(.horizontal, -16)  // full-bleed strip (prototype margin 0 -16)
                                    .padding(.top, 12)
                            },
                            links: { EmptyView() },
                            bottom: { footer })
            .onAppear {
                if timeline == nil {
                    anchor = todayLocal(tz)
                    rebuild()
                }
                RecentsStore.shared.record(record.id)
            }
    }

    // MARK: - Readout above the strip

    private var readout: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                (Text(formatHeight(scrubHeight, imperial: imperial)).font(.largeTitle.monospacedDigit())
                 + Text(" \(unit)").font(.footnote))
                    .foregroundStyle(.white)
                HStack(spacing: 4) {
                    Text(rising ? "▲" : "▼").font(.caption2)
                    Text(rising ? "Rising" : "Falling").font(.footnote)
                    // Rate of rise, first-class (#95): at Friday Harbor this
                    // reads 0.8 ft/hr and nobody looks twice; at Ile Haute it
                    // reads 8 ft/hr and does the work of a warning.
                    Text("· \(formatHeight(abs(scrubRate), imperial: imperial)) \(unit)/hr")
                        .font(.footnote.monospacedDigit())
                }
                .foregroundStyle(rising ? SN.rising : SN.falling)
            }
            Spacer()
            if let prev = prevExtreme, let next = nextExtreme {
                VStack(alignment: .trailing, spacing: 1) {
                    MonoLabel(text: "Range", color: SN.foam.opacity(0.5), tracking: 1.4)
                    // This tide's swing, prev turn to next — the subtraction
                    // the reader was otherwise left to do across the readout.
                    Text("\(formatHeight(abs(next.height - prev.height), imperial: imperial)) \(unit)")
                        .font(.title3.monospacedDigit()).foregroundStyle(SN.foam)
                }
                .padding(.trailing, 20)
            }
            if let next = nextExtreme {
                VStack(alignment: .trailing, spacing: 1) {
                    MonoLabel(text: "Next \(next.kind == .high ? "High" : "Low")",
                              color: SN.foam.opacity(0.5), tracking: 1.4)
                    Text("\(formatHeight(next.height, imperial: imperial)) \(unit)")
                        .font(.title3.monospacedDigit()).foregroundStyle(SN.foam)
                    // Relative only — the absolute time lives on the strip.
                    Text("in \(countdown(from: scrubTime, to: next.time))")
                        .font(.caption.monospacedDigit()).foregroundStyle(SN.leaf)
                }
            }
        }
    }

    // MARK: - Rolling multi-day schedule (turns, day-grouped)

    private func scheduleEntries(_ tl: TimelineData) -> [ScheduleEntry] {
        tl.tideExtremes
            .filter { tl.scheduleRange.contains($0.time) }
            .map { ScheduleEntry(time: $0.time, pill: $0.kind == .high ? .high : .low,
                                 value: "\(formatHeight($0.height, imperial: imperial)) \(unit)") }
            .sorted { $0.time < $1.time }
    }

    // The provenance/confidence marking (chs-online spec §2d, §7d — simplified
    // to plain language, design pass M4.3): lead with where the data came
    // from, keep the honesty clause that the numbers are device-computed. The
    // full clause-10 licence statement carries its weight in Settings.
    private var footer: some View {
        DetailFooter {
            if record.isChs {
                Text("Chart datum · Downloaded from CHS (IWLS) — computed on this device, not CHS-published numbers")
                    .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
                    .multilineTextAlignment(.center)
            } else {
                Text("\(record.chartDatum) datum · NOAA harmonic prediction")
                    .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
            }
        }
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
        // The anchor too: return-to-now from a September window has to bring
        // the whole window back, not just park the centerline at a `now` that
        // isn't on this strip.
        anchor = todayLocal(tz)
        rebuild()
    }

    /// One place the timeline is rebuilt from, so the anchor and the record
    /// can never be applied by two different code paths.
    private func rebuild() {
        timeline = TimelineData.build(tide: record, current: nil, now: live, anchor: anchor)
    }
}
