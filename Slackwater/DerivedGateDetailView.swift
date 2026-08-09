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
    @AppStorage(unitsKey) private var units = "imperial"

    @State private var live = appNow()
    @State private var scrubTime = appNow()
    @State private var timeline: TimelineData?
    /// The strip window's slacks with their HW/LW origin (the phase call needs
    /// the flags; timeline.currentEvents carries only times).
    @State private var slacks: [DerivedSlackEvent] = []

    private var gate: ChsGateInfo { record.gate }
    private var port: TideStationRecord { record.port }
    private var imperial: Bool { units == "imperial" }
    private var tz: TimeZone { gate.tz }
    private var phase: DerivedPhase { record.engineGate.phase(at: scrubTime, slacks: slacks) }
    private var nextSlack: DerivedSlackEvent? { slacks.first { $0.time > scrubTime } }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                MapHeader(name: gate.name, region: "\(gate.region) · current",
                          latitude: gate.latitude, longitude: gate.longitude,
                          favoriteId: gate.id)
                if let timeline {
                    scrubCard(timeline)
                    scheduleCard(timeline)
                        .padding(.top, 14)
                }
                footer
                    .padding(.top, 14)
            }
            .padding(.bottom, 42)
        }
        .ignoresSafeArea(edges: .top)
        .background(SN.page.ignoresSafeArea())
        .environment(\.timeZone, tz)
        .toolbar(.hidden, for: .navigationBar)
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

    // MARK: - Scrub card: strip, phase readout, tide link

    static func phaseColor(_ phase: DerivedPhase) -> Color {
        switch phase {
        case .flood: SN.rising
        case .ebb: SN.falling
        case .slack: SN.go
        }
    }

    private func scrubCard(_ tl: TimelineData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Phase readout above the strip: the word, never a number — no
            // speed exists for a derived gate (web hero phase-pill).
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(phaseWord(phase))
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

            TimelineScrubStrip(data: tl, geo: TimelineGeo(data: tl),
                               imperial: imperial,
                               now: live, scrubTime: $scrubTime)
                .padding(.horizontal, -16)  // full-bleed strip
                .padding(.top, 12)

            // The web's chart note, verbatim in spirit: the curve is a shape.
            Text("Shape only — slack times are derived from high and low water at \(port.name) (+\(Int(gate.hwLagMinutes)) min at high, +\(Int(gate.lwLagMinutes)) at low). Floods on the rising tide, ebbs on the falling one; speeds are not predicted.")
                .font(.caption2)
                .foregroundStyle(SN.foam.opacity(0.5))
                .padding(.top, 10)

            MonoLabel(text: "‹ swipe to scrub ›",
                      color: SN.foam.opacity(0.4), tracking: 1.4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            ScrubWhen(scrubTime: scrubTime, live: live, tz: tz, onReturn: returnToNow)
                .padding(.top, 14)

            TideAtPortLink(port: port)
                .padding(.top, 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(SN.cardFill)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SN.leaf.opacity(0.22)).frame(height: 0.5)
        }
    }

    // MARK: - Rolling multi-day schedule (slack rows, sun in the day header)

    private func scheduleCard(_ tl: TimelineData) -> some View {
        MultiDaySchedule(entries: scheduleEntries(tl), tz: tz, today: tl.today, days: tl.days,
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
        // Slack rows carry no value — "—", like the web's derived rows.
        let out: [ScheduleEntry] = tl.currentEvents
            .filter { $0.time >= t0 && $0.time <= t1 }
            .map { ScheduleEntry(time: $0.time, pill: .slack) }
        return out.sorted { $0.time < $1.time }
    }

    // The provenance footer (web App.tsx derived footer, in the app's CHS
    // register): derived on this device, no CHS current prediction exists.
    private var footer: some View {
        VStack(spacing: 6) {
            MonoLabel(text: "Predictions — not for navigation",
                      color: SN.foam.opacity(0.4), tracking: 1.4)
            Text("Slack times for \(gate.name) are derived on this device from \(port.name) high and low water — a cruising-community rule of thumb, not a CHS prediction. CHS publishes no current prediction for this pass.")
                .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    // MARK: - Data

    private func returnToNow() {
        live = appNow()
        scrubTime = live
    }
}
