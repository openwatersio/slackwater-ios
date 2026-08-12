// Slackwater — GPL v3. Current detail on the iOS scrub model (prototype
// TidesApp.dc.html): one continuous multi-day strip pans under a fixed
// centerline, current only — a paired reference port's tide no longer rides
// the same track (split-scrubbers spec §1). The port stays reachable one tap
// away via TideAtPortLink, under the scrub card's own readout. No day pager;
// the schedule is a rolling multi-day list, rows scrub cross-day.
import SwiftUI
import TideEngine

struct CurrentDetailView: View {
    let record: CurrentStationRecord
    @AppStorage(unitsKey) private var units = "imperial"
    @AppStorage(speedUnitKey) private var speedUnit = "kn"
    @ObservedObject private var service = ChsFitService.shared

    @State private var live = appNow()
    @State private var scrubTime = appNow()
    @State private var timeline: TimelineData?
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
    private var imperial: Bool { units == "imperial" }
    private var tz: TimeZone { record.tz }
    private var scrubSigned: Double { exactSigned(at: scrubTime) }
    private var phase: CurrentPhase { currentPhase(signed: scrubSigned) }
    private var nextSlack: CurrentEvent? {
        timeline?.currentEvents.first { $0.kind == .slack && $0.time > scrubTime }
    }
    /// The window around the next slack — looked up, not recomputed. The strip
    /// draws these same numbers as a band (gutter spec §3).
    private var slackWin: (start: Date, end: Date)? {
        guard let slack = nextSlack else { return nil }
        return timeline?.slackWindows.first { $0.slack == slack.time }
            .map { (start: $0.start, end: $0.end) }
    }

    /// The fast answer's marking, on every number this page prints: the tilde
    /// appears when the reading IS provisional. Every call site below reaches
    /// it rather than inlining the ternary.
    private var tilde: String { provisionalGate == nil ? "" : "~" }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                MapHeader(name: record.name, region: record.region,
                          latitude: record.latitude, longitude: record.longitude,
                          favoriteId: record.itemId)
                if let gate = provisionalGate {
                    ChsAmberCard(title: "Fast answer", headline: gate.provisionalHeadline,
                                 expectation: gate.provisionalExpectation,
                                 action: "See all downloads",
                                 identifier: "chs-provisional-warning") { showDownloads = true }
                        .padding(.top, 14)
                }
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
        .sheet(isPresented: $showDownloads) { OfflineManagerView().environment(\.openChsRoute, openChsRoute) }
        .onAppear {
            if timeline == nil {
                timeline = TimelineData.build(tide: nil, current: record, now: live, anchor: todayLocal(tz))
            }
            RecentsStore.shared.record(record.itemId)
        }
        // The refinement lands under an open page: same station, new model. The
        // curve, the schedule and the amber marking all have to follow it.
        .onChange(of: record) { _, refined in
            timeline = TimelineData.build(tide: nil, current: refined, now: live, anchor: todayLocal(tz))
        }
    }

    // MARK: - Scrub card: strip, current readout, tide-at-port link

    static func phaseColor(_ phase: CurrentPhase) -> Color {
        switch phase {
        case .flood: SN.rising
        case .ebb: SN.falling
        // Slack is the app's "go" colour, not a neutral. It is the moment the
        // app is named for, and it must read the same on every surface.
        case .slack: SN.go
        }
    }

    private func scrubCard(_ tl: TimelineData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Current readout above the strip.
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    if phase == .slack {
                        Text("Slack").font(.largeTitle)
                            .foregroundStyle(provisionalGate == nil ? Self.phaseColor(phase) : SN.amber)
                        Text("under \(formatSpeed(slackKn, unit: speedUnit)) \(speedUnitLabel(speedUnit))")
                            .font(.footnote.monospacedDigit()).foregroundStyle(SN.foam.opacity(0.7))
                    } else {
                        // The tilde is the whole point of the provisional
                        // treatment: the number itself stops claiming to be
                        // exact, before any badge or card is read.
                        (Text(tilde).font(.largeTitle)
                         + Text(formatSpeed(abs(scrubSigned), unit: speedUnit)).font(.largeTitle.monospacedDigit())
                         + Text(" \(speedUnitLabel(speedUnit))").font(.footnote))
                            .foregroundStyle(readingColor)
                        HStack(spacing: 4) {
                            Text(phaseWord(phase)).font(.footnote)
                            CompassArrow(deg: record.setDegrees(signed: scrubSigned)).font(.footnote)
                            Text(compass16(record.setDegrees(signed: scrubSigned))).font(.footnote)
                        }
                        .foregroundStyle(provisionalGate == nil ? Self.phaseColor(phase) : SN.amber.opacity(0.85))
                    }
                    if let gate = provisionalGate {
                        MonoLabel(text: "Fast answer · slack \(gate.provisionalTolerance)",
                                  color: SN.amber, tracking: 1.2)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(SN.amber.opacity(0.16), in: Capsule())
                            .padding(.top, 2)
                            .accessibilityIdentifier("provisional-reading-badge")
                    }
                }
                Spacer()
                if let slack = nextSlack {
                    VStack(alignment: .trailing, spacing: 1) {
                        MonoLabel(text: "Next slack", color: SN.foam.opacity(0.5), tracking: 1.4)
                        if let win = slackWin {
                            // Counts to the window OPENING, not the slack instant:
                            // this readout answers "when can I be there", and the
                            // window is when the pass is transitable. The window
                            // brackets the slack, so it is often already open —
                            // then it says `now` (gutter spec §5).
                            Text(win.start > scrubTime
                                 ? "\(tilde)in \(countdown(from: scrubTime, to: win.start))"
                                 : "\(tilde)now")
                                .font(.caption.monospacedDigit())
                                // SN.go, not SN.leaf: this line says when slack is.
                                // Same value today, but the token has to name the
                                // meaning or retargeting one of them breaks it.
                                .foregroundStyle(provisionalGate == nil ? SN.go : SN.amber)
                            // Time REMAINING, not the window's original length —
                            // an already-open window must not claim its full run.
                            // The threshold lives HERE, once, and not on the
                            // strip. It briefly moved onto the slack bands to
                            // fill their value row; six identical "0.5"s across
                            // a day made it the most repeated and least useful
                            // number on screen. One statement of a constant is
                            // information, six is texture — and the strip's
                            // value row went to the slack times instead.
                            Text("\(tilde)for \(countdown(from: max(scrubTime, win.start), to: win.end)) @ \(formatSpeed(Timeline.slackThresholdKn, unit: speedUnit)) \(speedUnitLabel(speedUnit))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(provisionalGate == nil ? SN.foam.opacity(0.7) : SN.amber.opacity(0.7))
                                .accessibilityIdentifier("slack-window")
                        } else {
                            Text("\(tilde)in \(countdown(from: scrubTime, to: slack.time))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(provisionalGate == nil ? SN.go : SN.amber)
                        }
                    }
                }
            }

            TimelineScrubStrip(data: tl, geo: TimelineGeo(data: tl),
                               imperial: imperial, speedUnit: speedUnit,
                               now: live,
                               floodDeg: record.floodDirection, ebbDeg: record.ebbDirection,
                               scrubTime: $scrubTime)
                .padding(.horizontal, -16)  // full-bleed strip
                .padding(.top, 12)

            MonoLabel(text: "‹ swipe to scrub ›",
                      color: SN.foam.opacity(0.4), tracking: 1.4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            ScrubWhen(scrubTime: scrubTime, live: live, tz: tz, onReturn: returnToNow)
                .padding(.top, 14)

            if let port = pairedTide {
                TideAtPortLink(port: port)
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(SN.cardFill)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SN.leaf.opacity(0.22)).frame(height: 0.5)
        }
    }

    // MARK: - Rolling multi-day schedule (slack/max rows, sun in the day header)

    private func scheduleCard(_ tl: TimelineData) -> some View {
        MultiDaySchedule(entries: scheduleEntries(tl), tz: tz, anchor: tl.anchor,
                         today: tl.today, days: tl.days,
                         scrubTime: scrubTime, onTap: { scrubTime = $0 })
            .background(SN.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(SN.cardStroke, lineWidth: 0.5))
            .padding(.horizontal, 16)
    }

    private func scheduleEntries(_ tl: TimelineData) -> [ScheduleEntry] {
        let out: [ScheduleEntry] = tl.currentEvents
            .filter { tl.scheduleRange.contains($0.time) }
            .map { e in
                switch e.kind {
                case .slack:
                    ScheduleEntry(time: e.time, pill: .slack)
                case .maxFlood:
                    ScheduleEntry(time: e.time, pill: .flood,
                                  value: "\(formatSpeed(abs(e.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit))",
                                  arrowDeg: record.floodDirection)
                case .maxEbb:
                    ScheduleEntry(time: e.time, pill: .ebb,
                                  value: "\(formatSpeed(abs(e.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit))",
                                  arrowDeg: record.ebbDirection)
                }
            }
        return out.sorted { $0.time < $1.time }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            MonoLabel(text: "Predictions — not for navigation",
                      color: SN.foam.opacity(0.4), tracking: 1.4)
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
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    // MARK: - Data

    /// Engine-exact signed velocity — same call as the old committed readout.
    private func exactSigned(at t: Date) -> Double {
        record.engineStation.speeds(from: t, to: t.addingTimeInterval(1), step: 1).first?.speed ?? 0
    }

    private func returnToNow() {
        live = appNow()
        scrubTime = live
    }
}
