// Slackwater — GPL v3. Derived-gate detail (Malibu Rapids): the gate's
// schematic current strip with phase readout and slack times, one-tap link to
// the reference port's tide. No speed prediction exists (spec §3), so the curve
// is a shape, not a velocity. The derivation (reference HW/LW + fixed lag,
// cruising-community consensus) lives in text, not on the schematic (web
// App.tsx: "Shape only" note + slack-only rows). A derived gate has honest
// slack TIMES and flood/ebb PHASE but NO knots.
import SwiftUI
import TideEngine

struct DerivedGateDetailView: View {
    let record: DerivedGateRecord

    @State private var live = appNow()
    @State private var scrubTime = appNow()
    @State private var timeline: TimelineData?
    /// The strip window's slacks with their HW/LW origin (the phase call needs
    /// the flags; timeline.currentEvents carries only times).
    @State private var slacks: [DerivedSlackEvent] = []

    private var gate: ChsGateInfo { record.gate }
    private var port: TideStationRecord { record.port }
    private var tz: TimeZone { gate.tz }
    private var phase: DerivedPhase { record.engineGate.phase(at: scrubTime, slacks: slacks) }
    private var nextSlack: DerivedSlackEvent? { slacks.first { $0.time > scrubTime } }

    var body: some View {
        ScrubDetailScaffold(name: gate.name, region: gate.region,
                            latitude: gate.latitude, longitude: gate.longitude,
                            favoriteId: gate.id, tz: tz,
                            timeline: timeline, entries: scheduleEntries,
                            live: $live, scrubTime: $scrubTime,
                            above: { EmptyView() },
                            card: { tl in
                                readout
                                TimelineScrubStrip(data: tl, geo: TimelineGeo(data: tl),
                                                   now: live, scrubTime: $scrubTime)
                                    .padding(.horizontal, -16)  // full-bleed strip
                                    .padding(.top, 12)
                                // The web's chart note, verbatim in spirit: the curve is a shape.
                                Text("Shape only — slack times are derived from high and low water at \(port.name) (+\(Int(gate.hwLagMinutes)) min at high, +\(Int(gate.lwLagMinutes)) at low). Floods on the rising tide, ebbs on the falling one; speeds are not predicted.")
                                    .font(.caption2)
                                    .foregroundStyle(SN.foam.opacity(0.5))
                                    .padding(.top, 10)
                            },
                            links: { TideAtPortLink(port: port) },
                            bottom: { footer })
            .onAppear {
                if timeline == nil {
                    let tl = TimelineData.build(gate: record, now: live)
                    timeline = tl
                    // Same padded window the strip's events were derived over, so
                    // the phase/readout and the drawn dots can never disagree.
                    let pad = 6.0 * 3600
                    slacks = record.engineGate.slacks(from: tl.start.addingTimeInterval(-pad),
                                                      to: tl.end.addingTimeInterval(pad))
                }
                RecentsStore.shared.record(gate.id)
            }
    }

    // MARK: - Readout above the strip: the phase word, never a number

    /// Kept as the tests' named binding (ColourAndFormTests); the palette
    /// itself lives in `StationGlyph.colour(for:)`.
    static func phaseColor(_ phase: DerivedPhase) -> Color {
        StationGlyph.colour(for: ChsGateCardView.glyphTone(phase))
    }

    private var readout: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(phase.word)
                    .font(.largeTitle)
                    .foregroundStyle(Self.phaseColor(phase))
                Text("speeds not predicted for this pass")
                    .font(.footnote).foregroundStyle(SN.foam.opacity(0.7))
            }
            Spacer()
            if let slack = nextSlack {
                VStack(alignment: .trailing, spacing: 1) {
                    MonoLabel(text: "Next slack", color: SN.foam.opacity(0.5), tracking: 1.4)
                    Text("in \(countdown(from: scrubTime, to: slack.time))")
                        // SN.go, not SN.leaf: this line says when slack is.
                        .font(.caption.monospacedDigit()).foregroundStyle(SN.go)
                    Text("at \(slack.highWater ? "high" : "low") water")
                        .font(.caption).foregroundStyle(SN.foam.opacity(0.7))
                }
            }
        }
    }

    // MARK: - Rolling multi-day schedule (slack rows, sun in the day header)

    private func scheduleEntries(_ tl: TimelineData) -> [ScheduleEntry] {
        let t0 = tl.today
        let t1 = t0.addingTimeInterval(Timeline.scheduleHours * 3600)
        // Slack rows carry no value — "—", like the web's derived rows.
        let out: [ScheduleEntry] = tl.currentEvents
            .filter { $0.time >= t0 && $0.time <= t1 }
            .map { ScheduleEntry(time: $0.time, pill: .slack) }
        return out.sorted { $0.time < $1.time }
    }

    // The provenance footer (web App.tsx derived footer, in the app's CHS
    // register): derived on this device, no CHS current prediction exists.
    private var footer: some View {
        DetailFooter {
            Text("Slack times for \(gate.name) are derived on this device from \(port.name) high and low water — a cruising-community rule of thumb, not a CHS prediction. CHS publishes no current prediction for this pass.")
                .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
                .multilineTextAlignment(.center)
        }
    }
}
