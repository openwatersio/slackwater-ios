// Slackwater — GPL v3. Current detail on the iOS scrub model (prototype
// TidesApp.dc.html): one continuous multi-day strip pans under a fixed
// centerline, current only — a paired reference port's tide no longer rides
// the same track (split-scrubbers spec §1). The port stays reachable one tap
// away via TideAtPortLink, in the scrub card. No day pager; the schedule is a
// rolling multi-day list, rows scrub cross-day.
import SwiftUI
import TideEngine

/// One schedule for every real-velocity current strip (harmonic or fetched
/// official samples): slack rows bare, max rows with speed + set bearing.
func scheduleEntries(_ tl: TimelineData, floodDeg: Double, ebbDeg: Double, speedUnit: String) -> [ScheduleEntry] {
    // `scheduleRange` hangs off the ANCHOR, not `today` — the list a September
    // window shows is September's. Never re-derive it from `tl.today` here.
    let out: [ScheduleEntry] = tl.currentEvents
        .filter { tl.scheduleRange.contains($0.time) }
        .map { e in
            switch e.kind {
            case .slack:
                ScheduleEntry(time: e.time, pill: .slack)
            case .maxFlood:
                ScheduleEntry(time: e.time, pill: .flood,
                              value: "\(formatSpeed(abs(e.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit))",
                              arrowDeg: floodDeg)
            case .maxEbb:
                ScheduleEntry(time: e.time, pill: .ebb,
                              value: "\(formatSpeed(abs(e.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit))",
                              arrowDeg: ebbDeg)
            }
        }
    return out.sorted { $0.time < $1.time }
}

struct CurrentDetailView: View {
    let record: CurrentStationRecord
    @AppStorage(speedUnitKey, store: AppGroup.defaults) private var speedUnit = "kn"
    @AppStorage(AppGroup.slackWindowSpeedKey, store: AppGroup.defaults)
    private var slackWindowSpeed = defaultSlackThresholdKn
    @ObservedObject private var service = ChsFitService.shared
    @ObservedObject private var net = Connectivity.shared

    @State private var live = appNow()
    @State private var scrubTime = appNow()
    @State private var timeline: TimelineData?
    /// The local midnight the window hangs from. Only `returnToNow` and (in
    /// Plan B) the range bar move it; everything else reads it.
    @State private var anchor = Date.distantPast
    @State private var showDownloads = false
    // Re-forwarded onto the sheet below — `.sheet` content doesn't inherit a
    // custom `@Environment` key set above the presenting view on its own
    // (SlackwaterApp.swift's `.sheet(showDownloads)` comment has the story).
    @Environment(\.openChsRoute) private var openChsRoute

    /// The gate identity behind a provisional fast answer — nil for a final
    /// model, which is what every readout below keys on.
    private var provisionalGate: ChsCurrentGateInfo? {
        service.isProvisional(record.id) ? record.chsGate : nil
    }
    /// Every number on this page is the fast answer's: amber, not white.
    private var readingColor: Color { provisionalGate == nil ? .white : SN.amber }

    private var pairedTide: TideStationRecord? { record.pairedTide }
    private var tz: TimeZone { record.tz }
    private var scrubSigned: Double { exactSigned(at: scrubTime) }
    private var phase: CurrentPhase { currentPhase(signed: scrubSigned) }
    private var activeSlackWin: (slack: Date, start: Date, end: Date)? {
        timeline?.containingSlackWindow(at: scrubTime)
    }
    private var isSlack: Bool { activeSlackWin != nil || phase == .slack }
    /// What the right tile shows. Running water: the next slack, since the max
    /// belongs to this run and the left tile's caption carries it. Slack: the
    /// next max. Inside a window, everything before its end IS this slack — a
    /// weak station's window can swallow a sub-threshold max and the slack
    /// after it — so next is whatever follows the window.
    private var nextEvent: CurrentEvent? {
        guard let events = timeline?.currentEvents else { return nil }
        if let win = activeSlackWin { return events.first { $0.time >= win.end } }
        return isSlack ? events.first { $0.time > scrubTime }
                       : events.first { $0.kind == .slack && $0.time > scrubTime }
    }
    /// This run's max — behind the scrub once past it, ahead before it.
    private var runMax: CurrentEvent? {
        guard let events = timeline?.currentEvents else { return nil }
        if let prev = events.last(where: { $0.time <= scrubTime }), prev.kind != .slack { return prev }
        return events.first { $0.time > scrubTime && $0.kind != .slack }
    }
    /// The window around a slack — looked up, not recomputed. The strip draws
    /// these same numbers as a band (gutter spec §3).
    private func slackWindow(at slack: Date) -> (start: Date, end: Date)? {
        timeline?.slackWindows.first { $0.slack == slack }.map { (start: $0.start, end: $0.end) }
    }

    /// The fast answer's marking, on every number this page prints: the tilde
    /// appears when the reading IS provisional. Every call site below reaches
    /// it rather than inlining the ternary.
    private var tilde: String { provisionalGate == nil ? "" : "~" }

    var body: some View {
        ScrubDetailScaffold(name: record.name, region: record.region,
                            favoriteId: record.itemId, tz: tz,
                            timeline: timeline,
                            entries: { scheduleEntries($0, floodDeg: record.floodDirection,
                                                       ebbDeg: record.ebbDirection, speedUnit: speedUnit) },
                            live: $live, scrubTime: $scrubTime,
                            onReturn: returnToNow,
                            anchor: $anchor,
                            onPicked: { _ in rebuild() },
                            scrubSummary: { tl in
                                guard let range = currentPeakToPeakRange(tl.currentEvents, around: scrubTime) else { return nil }
                                return ("Range", "\(formatSpeed(range, unit: speedUnit)) \(speedUnitLabel(speedUnit))")
                            },
                            above: {
                                if let gate = provisionalGate {
                                    ChsAmberCard(title: "Fast answer", headline: gate.provisionalHeadline,
                                                 expectation: gate.provisionalExpectation(online: net.online),
                                                 action: "See all downloads",
                                                 identifier: "chs-provisional-warning") { showDownloads = true }
                                        .padding(.bottom, 14)
                                }
                                readout
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 14)
                            },
                            card: { tl in
                                TimelineScrubStrip(data: tl, geo: TimelineGeo(data: tl),
                                                   speedUnit: speedUnit, now: live,
                                                   floodDeg: record.floodDirection, ebbDeg: record.ebbDirection,
                                                   scrubTime: $scrubTime, onReturn: returnToNow)
                            },
                            links: {
                                if let port = pairedTide { TideAtPortLink(port: port) }
                            },
                            bottom: { footer })
            .sheet(isPresented: $showDownloads) { OfflineManagerView().environment(\.openChsRoute, openChsRoute) }
            .onAppear {
                if timeline == nil {
                    anchor = todayLocal(tz)
                    rebuild()
                }
                RecentsStore.shared.record(record.itemId)
            }
            // The refinement lands under an open page: same station, new model. The
            // curve, the schedule and the amber marking all have to follow it.
            .onChange(of: record) { _, _ in rebuild() }
            .onChange(of: slackWindowSpeed) { _, _ in rebuild() }
    }

    // MARK: - Readout between header and card: two tiles, now and next

    /// Kept as the tests' named binding (ColourAndFormTests); the palette
    /// itself lives in `StationGlyph.colour(for:)`. Slack is the app's "go"
    /// colour — the moment the app is named for, the same on every surface.
    static func phaseColor(_ phase: CurrentPhase) -> Color {
        StationGlyph.colour(for: phase == .flood ? .flood : phase == .ebb ? .ebb : .slack)
    }

    private func speedText(_ kn: Double) -> Text {
        Text("\(tilde)\(formatSpeed(abs(kn), unit: speedUnit))").font(ReadoutType.hero.monospacedDigit())
            + Text(" \(speedUnitLabel(speedUnit))").font(ReadoutType.unit)
    }
    private var thresholdText: String {
        "<\(formatSpeed(timeline?.slackThreshold ?? slackThresholdKn, unit: speedUnit)) \(speedUnitLabel(speedUnit))"
    }

    /// Running water's caption: this run's max and when. Relative from now;
    /// once scrubbed away, "in 4h" from an arbitrary point means nothing, so
    /// the clock time.
    private var maxLine: String? {
        runMax.map { m in
            let when = scrubbedAway(scrubTime, from: live) ? chartTime(m.time, tz)
                : m.time > scrubTime ? "in \(countdown(from: scrubTime, to: m.time))"
                : "\(countdown(from: m.time, to: scrubTime)) ago"
            return "\(tilde)Max \(formatSpeed(abs(m.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit)) · \(when)"
        }
    }

    private var readout: some View {
        let phaseColor = provisionalGate == nil ? Self.phaseColor(isSlack ? .slack : phase) : SN.amber
        let caption = provisionalGate == nil ? SN.foam.opacity(0.55) : SN.amber.opacity(0.7)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Now. The set is the hero (#59): a novice reads the arrow
                // first. In slack the water goes both ways, so the glyph does
                // too, and the number is how long the slack holds — time
                // REMAINING, not the window's original length.
                ReadoutTile(label: isSlack ? "Slack" : phase.word,
                            caption: isSlack ? (activeSlackWin.map { "\(tilde)\(thresholdText) until \(chartTime($0.end, tz))" } ?? chartTime(scrubTime, tz))
                                : (maxLine ?? chartTime(scrubTime, tz)),
                            valueColor: readingColor, captionColor: caption,
                            accessibility: isSlack ? "Slack" : "\(phase.word), setting \(compass16(record.setDegrees(signed: scrubSigned)))") {
                    if isSlack {
                        Image(systemName: "arrow.right.and.line.vertical.and.arrow.left")
                            .foregroundStyle(phaseColor)
                    } else {
                        let deg = record.setDegrees(signed: scrubSigned)
                        Text(compass16(deg)).foregroundStyle(SN.foam.opacity(0.5))
                        CompassArrow(deg: deg).foregroundStyle(phaseColor)
                    }
                } value: {
                    if isSlack {
                        Text(activeSlackWin.map { "\(tilde)for \(countdown(from: scrubTime, to: $0.end))" } ?? "\(tilde)now")
                            .font(ReadoutType.hero.monospacedDigit())
                            .accessibilityIdentifier("slack-window")
                    } else {
                        speedText(scrubSigned)
                    }
                }
                .accessibilityIdentifier("detail-reading")

                if let next = nextEvent {
                    // Next. A slack counts to its window OPENING, not the
                    // instant: the window is when the pass is transitable
                    // (gutter spec §5), and for a slack the when IS the hero
                    // and the caption is how long it holds. A max counts to
                    // the max. Relative from now, the clock time once scrubbed
                    // away.
                    let window = next.kind == .slack ? slackWindow(at: next.time) : nil
                    let target = window?.start ?? next.time
                    let away = scrubbedAway(scrubTime, from: live)
                    let when = away ? chartTime(target, tz) : countdown(from: scrubTime, to: target)
                    let nextColor = provisionalGate == nil
                        ? Self.phaseColor(next.kind == .slack ? .slack : next.kind == .maxFlood ? .flood : .ebb)
                        : SN.amber
                    ReadoutTile(label: next.kind == .slack ? "Next slack" : next.turnLabel,
                                caption: next.kind == .slack
                                    // The threshold prints HERE, once, not on the strip.
                                    ? (window.map { "\(tilde)\(thresholdText) for \(countdown(from: $0.start, to: $0.end))" }
                                       ?? "\(tilde)never \(thresholdText)")
                                    : (away ? "\(tilde)\(when)" : "\(tilde)in \(when)"),
                                valueColor: readingColor, captionColor: caption,
                                accessibility: "Next \(next.turnLabel.lowercased())") {
                        if next.kind == .slack {
                            Image(systemName: "arrow.right.and.line.vertical.and.arrow.left")
                                .foregroundStyle(nextColor)
                        } else {
                            let deg = next.kind == .maxFlood ? record.floodDirection : record.ebbDirection
                            Text(compass16(deg)).foregroundStyle(SN.foam.opacity(0.5))
                            CompassArrow(deg: deg).foregroundStyle(nextColor)
                        }
                    } value: {
                        if next.kind == .slack {
                            Text(away ? "\(tilde)\(when)" : "\(tilde)In \(when)")
                                .font(ReadoutType.hero.monospacedDigit())
                        } else {
                            speedText(next.speed)
                        }
                    }
                }
            }
            if let gate = provisionalGate {
                MonoLabel(text: "Fast answer · slack \(gate.provisionalTolerance)",
                          color: SN.amber, tracking: 1.2)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(SN.amber.opacity(0.16), in: Capsule())
                    .accessibilityIdentifier("provisional-reading-badge")
            }
        }
    }

    private var footer: some View {
        DetailFooter {
            if let gate = provisionalGate {
                Text("Flood sets \(Int(record.floodDirection.rounded()))°T · \(Int(ChsCurrentGateInfo.provisionalDays)) of \(Int(gate.fitDays)) days downloaded — still refining")
                    .font(.caption2).foregroundStyle(SN.amber.opacity(0.7))
                    .multilineTextAlignment(.center)
            } else if record.isChs {
                // Same register as the CHS tide footer (TideDetailView).
                Text("Flood sets \(Int(record.floodDirection.rounded()))°T · Downloaded from CHS (IWLS) — computed on this device, not CHS-published numbers")
                    .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
                    .multilineTextAlignment(.center)
            } else {
                Text("Flood sets \(Int(record.floodDirection.rounded()))°T · NOAA harmonic current prediction · \(speedUnit == "kn" ? "knots" : speedUnitLabel(speedUnit))")
                    .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
            }
        }
    }

    // MARK: - Data

    /// Engine-exact signed velocity — same call as the old committed readout.
    private func exactSigned(at t: Date) -> Double {
        record.engineStation.speeds(from: t, to: t.addingTimeInterval(1), step: 1).first?.speed ?? 0
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
        timeline = TimelineData.build(tide: nil, current: record, now: live, anchor: anchor,
                                      threshold: normalizedSlackThresholdKn(slackWindowSpeed))
    }
}

#Preview {
    NavigationStack {
        CurrentDetailView(record: CurrentStationRecord.all.first { $0.name == "Deception Pass (Narrows)" }!)
    }
}
