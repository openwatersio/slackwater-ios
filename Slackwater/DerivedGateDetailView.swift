// Slackwater — GPL v3. Derived-gate detail (Malibu Rapids): the gate's
// schematic current strip with phase readout and slack times, one-tap link to
// the reference port's tide. A derived gate has honest slack times and phase,
// but no speed prediction.
import SwiftUI
import TideEngine

struct DerivedGateDetailView: View {
    let record: DerivedGateRecord

    @State private var live = appNow()
    @State private var scrubTime = Timeline.introStart(for: appNow())
    /// Chunk cache + merged window (TimelineChunks.swift). The schematic ±1
    /// shape needs no governed scale — its fit never moves.
    @State private var store: TimelineWindowStore?
    /// The local midnight the schedule week hangs from. `returnToNow`, the
    /// picker, and the settle-follow below move it.
    @State private var anchor = Date.distantPast
    @State private var viewportPts: CGFloat = 0
    /// The strip window's slacks with their HW/LW origin (the phase call needs
    /// the flags; timeline.currentEvents carries only times).
    @State private var slacks: [DerivedSlackEvent] = []

    private var timeline: TimelineData? { store?.timeline }

    private var gate: ChsGateInfo { record.gate }
    private var port: TideStationRecord { record.port }
    private var tz: TimeZone { gate.tz }
    private var phase: DerivedPhase { record.engineGate.phase(at: scrubTime, slacks: slacks) }
    private var nextSlack: DerivedSlackEvent? { slacks.first { $0.time > scrubTime } }
    /// The stop the pill names and its tap walks to: the next slack, or the
    /// sun's next rise or set when that comes first.
    private var nextStop: (time: Date, text: String)? {
        nextCommentaryStop(nextSlack.map { (time: $0.time, text: "Slack") },
                           sun: timeline?.days ?? [], after: scrubTime)
    }

    var body: some View {
        let sky = SkyState(time: scrubTime, latitude: gate.latitude, longitude: gate.longitude,
                           days: timeline?.days ?? [],
                           eclipses: timeline?.eclipses ?? [])
        ScrubDetailScaffold(name: gate.name, region: gate.region,
                            favoriteId: gate.id, tz: tz,
                            timeline: timeline, entries: scheduleEntries,
                            scrubTime: $scrubTime,
                            anchor: $anchor,
                            onPicked: { picked in
                                store?.jump(to: scrubTime, anchor: picked)
                                refreshSlacks()
                            },
                            topBackdrop: AnyView(SkyBackdrop(sky: sky)),
                            above: { EmptyView() },
                            card: { tl in
                                let next = nextStop
                                TimelineScrubStrip(data: tl, geo: TimelineGeo(data: tl),
                                                   now: live, chromeInk: sky.ink,
                                                   scrubTime: $scrubTime,
                                                   onReturn: returnToNow,
                                                   commentary: next.map {
                                                       commentaryText($0.text, at: $0.time, from: scrubTime, now: live)
                                                   },
                                                   onCommentary: { if let next { scrubTime = next.time } },
                                                   scrollGate: store?.gate,
                                                   onViewportWidth: { viewportPts = $0 })
                                    .overlay(alignment: .top) { lead(ink: sky.ink) }
                            },
                            links: { tl, jump in
                                VStack(alignment: .leading, spacing: 12) {
                                    SummaryTiles(primary: ("Shape only", "No speed",
                                                           "\(port.name) tides"),
                                                 moon: sky.illumination, at: scrubTime,
                                                 eclipse: tl.eclipses.first { $0.underway(at: scrubTime) },
                                                 onJump: jump,
                                                 latitude: gate.latitude, longitude: gate.longitude)
                                    if let note = gate.magnitudeNote {
                                        Text(note).font(.caption).foregroundStyle(SN.foam.opacity(0.7))
                                    }
                                    TideAtPortLink(port: port)
                                }
                            },
                            bottom: {
                                VStack(spacing: 14) {
                                    footer
                                    stationDetails
                                }
                            })
            .onAppear {
                if store == nil {
                    anchor = todayLocal(tz)
                    let s = TimelineWindowStore(source: .gate(record))
                    s.start(anchor: anchor, now: live)
                    store = s
                    refreshSlacks()
                }
                RecentsStore.shared.record(gate.id)
            }
            .onChange(of: scrubTime) { _, t in store?.focus(t, viewportPts: viewportPts) }
            // Chunks landing widen the strip; the phase readout's slacks must
            // cover whatever it now spans.
            .onChange(of: timeline.map { $0.start...$0.end }) { _, _ in refreshSlacks() }
            // The schedule follows a scrub that has settled outside its week.
            .task(id: scrubTime) {
                guard (try? await Task.sleep(for: .milliseconds(600))) != nil else { return }
                if let tl = timeline, !tl.scheduleRange.contains(scrubTime) {
                    anchor = dayLocal(scrubTime, tz)
                    store?.setAnchor(anchor)
                }
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
        return LeadCard(time: leadWhen(scrubTime, tz), timeColor: ink) {
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

    /// The nod to the nerds (#170). The lags are the whole model here — the
    /// two numbers every slack on this page is made of — and they exist
    /// nowhere else in the app.
    private var stationDetails: some View {
        StationDetails {
            StationDetailRow("Gate", gate.id)
            StationDetailRow("Position", formatCoord(lat: gate.latitude, lon: gate.longitude))
            StationDetailRow("Time zone", gate.timezone)
            StationDetailRow("Reference", "\(port.name), \(Int(distanceKm(gate.latitude, gate.longitude, port.latitude, port.longitude).rounded())) km away")
            StationDetailRow("Slack lags", "\(Int(gate.hwLagMinutes.rounded())) min after \(port.name) high · \(Int(gate.lwLagMinutes.rounded())) min after low")
            StationDetailRow("Prediction", "Slack times only, derived on this device — no speed prediction exists for this pass")
            StationDetailNote("The curve between slacks is a schematic shape, not a measured speed. Only the times it crosses zero are a claim.")
        }
    }

    // MARK: - Data

    private func returnToNow() {
        live = appNow()
        // The anchor too: return-to-now from a September window has to bring
        // the whole schedule week back. The scrubber rides home animated
        // within `Timeline.snapJumpHours` and lands unanimated past it.
        anchor = todayLocal(tz)
        store?.jump(to: live, anchor: anchor)
        scrubTime = live
        refreshSlacks()
    }

    /// Slacks over the merged strip plus the event pad, so the phase/readout
    /// and the drawn dots can never disagree about a slack near an edge.
    private func refreshSlacks() {
        guard let tl = timeline else { slacks = []; return }
        let pad = TimelineData.eventPad
        slacks = record.engineGate.slacks(from: tl.start.addingTimeInterval(-pad),
                                          to: tl.end.addingTimeInterval(pad))
    }
}
