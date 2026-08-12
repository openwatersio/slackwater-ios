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

    var body: some View {
        ScrubDetailScaffold(name: record.name, region: record.region,
                            latitude: record.latitude, longitude: record.longitude,
                            favoriteId: record.id, tz: tz,
                            timeline: timeline, entries: scheduleEntries,
                            live: $live, scrubTime: $scrubTime,
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
                    timeline = TimelineData.build(tide: record, current: nil, now: live)
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
                }
                .foregroundStyle(rising ? SN.rising : SN.falling)
            }
            Spacer()
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
        let t0 = tl.today
        let t1 = t0.addingTimeInterval(Timeline.scheduleHours * 3600)
        let out: [ScheduleEntry] = tl.tideExtremes
            .filter { $0.time >= t0 && $0.time <= t1 }
            .map { ScheduleEntry(time: $0.time, pill: $0.kind == .high ? .high : .low,
                                 value: "\(formatHeight($0.height, imperial: imperial)) \(unit)") }
        return out.sorted { $0.time < $1.time }
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
}
