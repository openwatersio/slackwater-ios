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
    @State private var scrubTime = Timeline.introStart(for: appNow())
    @State private var timeline: TimelineData?
    /// The local midnight the window hangs from. Only `returnToNow` and (in
    /// Plan B) the range bar move it; everything else reads it.
    @State private var anchor = Date.distantPast
    /// The strip window's slacks with their HW/LW origin (the phase call needs
    /// the flags; timeline.currentEvents carries only times).
    @State private var slacks: [DerivedSlackEvent] = []

    private var gate: ChsGateInfo { record.gate }
    private var port: TideStationRecord { record.port }
    private var tz: TimeZone { gate.tz }
    private var phase: DerivedPhase { record.engineGate.phase(at: scrubTime, slacks: slacks) }
    private var nextSlack: DerivedSlackEvent? { slacks.first { $0.time > scrubTime } }

    var body: some View {
        let sky = SkyState(time: scrubTime, latitude: gate.latitude, longitude: gate.longitude)
        ScrubDetailScaffold(name: gate.name, region: gate.region,
                            favoriteId: gate.id, tz: tz,
                            timeline: timeline, entries: scheduleEntries,
                            scrubTime: $scrubTime,
                            anchor: $anchor,
                            onPicked: { _ in rebuild() },
                            topBackdrop: AnyView(SkyBackdrop(sky: sky)),
                            above: { EmptyView() },
                            card: { tl in
                                let slack = nextSlack
                                TimelineScrubStrip(data: tl, geo: TimelineGeo(data: tl),
                                                   now: live, showsDayBands: false,
                                                   skyFill: sky.horizon, chromeInk: sky.ink,
                                                   scrubTime: $scrubTime,
                                                   onReturn: returnToNow,
                                                   commentary: slack.map {
                                                       commentaryText("Slack", at: $0.time, from: scrubTime, now: live)
                                                   },
                                                   onCommentary: { if let slack { scrubTime = slack.time } })
                                    .overlay(alignment: .top) { lead(ink: sky.ink) }
                                // The web's chart note, verbatim in spirit: the curve is a shape.
                                Text("Shape only — slack times are derived from high and low water at \(port.name) (+\(Int(gate.hwLagMinutes)) min at high, +\(Int(gate.lwLagMinutes)) at low). Floods on the rising tide, ebbs on the falling one; speeds are not predicted.")
                                    .font(.caption2)
                                    .foregroundStyle(SN.foam.opacity(0.5))
                                    .padding(.top, 10)
                            },
                            links: { _ in
                                VStack(alignment: .leading, spacing: 12) {
                                    // Moon only: a derived gate has slack times and phase, no knots.
                                    SummaryTiles(at: scrubTime)
                                    if let note = gate.magnitudeNote {
                                        Text(note).font(.caption).foregroundStyle(SN.foam.opacity(0.7))
                                    }
                                    TideAtPortLink(port: port)
                                }
                            },
                            bottom: { footer })
            .onAppear {
                if timeline == nil {
                    anchor = todayLocal(tz)
                    rebuild()
                }
                RecentsStore.shared.record(gate.id)
            }
    }

    // MARK: - The lead reading, fixed over the centerline

    /// Kept as the tests' named binding (ColourAndFormTests); the palette
    /// itself lives in `StationGlyph.colour(for:)`.
    static func phaseColor(_ phase: DerivedPhase) -> Color {
        StationGlyph.colour(for: ChsGateCardView.glyphTone(phase))
    }

    /// The same lead anatomy the other three details wear, minus its big
    /// line: no speed exists for this pass (spec §3), so the eyebrow's phase
    /// word sits straight above the time rather than over an invented number.
    ///
    /// A plain forward/back arrow, not a `CompassArrow`: a derived gate has no
    /// set bearing to point at — only which way through the pass the water is
    /// going. The word is the same one the measured leads use, so the four
    /// details read alike.
    private func lead(ink: Color) -> some View {
        let word = phase.word
        return LeadCard(time: chartTime(scrubTime, tz), timeColor: ink) {
            leadState(word, ink: ink)
            Image(systemName: glyph)
                .foregroundStyle(Self.phaseColor(phase))
        }
    }

    private var glyph: String {
        switch phase {
        case .flood: "arrow.forward"
        case .ebb: "arrow.backward"
        case .slack: "arrow.right.and.line.vertical.and.arrow.left"
        }
    }

    // MARK: - Rolling multi-day schedule (slack rows, sun in the day header)

    private func scheduleEntries(_ tl: TimelineData) -> [ScheduleEntry] {
        // Slack rows carry no value — "—", like the web's derived rows.
        tl.currentEvents
            .filter { tl.scheduleRange.contains($0.time) }
            .map { ScheduleEntry(time: $0.time, pill: .slack) }
            .sorted { $0.time < $1.time }
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

    // MARK: - Data

    private func returnToNow() {
        live = appNow()
        scrubTime = live
        // The anchor too: return-to-now from a September window has to bring
        // the whole window back, not just park the centerline at a `now` that
        // isn't on this strip.
        anchor = todayLocal(tz)
        rebuild()
    }

    /// One place the timeline is rebuilt from, so the anchor and the slacks
    /// (derived off the same padded window) can never fall out of sync.
    private func rebuild() {
        let tl = TimelineData.build(gate: record, now: live, anchor: anchor)
        timeline = tl
        // Same padded window the strip's events were derived over, so
        // the phase/readout and the drawn dots can never disagree.
        let pad = TimelineData.eventPad
        slacks = record.engineGate.slacks(from: tl.start.addingTimeInterval(-pad),
                                          to: tl.end.addingTimeInterval(pad))
    }
}
