// Slackwater — GPL v3. The 7 online (fit-reject) gates' detail (online-gates
// spec §2/§3): no on-device model exists for these, ever — the fetched CHS
// window is the only source of truth. Modeled on CurrentDetailView's
// post-split single-track anatomy, minus everything fit/provisional (there is
// no fast answer here, only the real published numbers or an honest why-not).
import SwiftUI
import TideEngine

struct OnlineGateDetailView: View {
    let gate: ChsCurrentGateInfo
    @AppStorage(speedUnitKey) private var speedUnit = "kn"
    @ObservedObject private var net = Connectivity.shared
    @Environment(\.openChsRoute) private var openChsRoute

    @State private var live = appNow()
    @State private var scrubTime = appNow()
    @State private var window: ChsOnlineWindow?
    /// The local midnight the window hangs from. Only `returnToNow` and (in
    /// Plan B) the range bar move it; everything else reads it.
    @State private var anchor = Date.distantPast
    @State private var fetching = false
    @State private var fetchFailed = false

    private var tz: TimeZone { gate.tz }

    /// The paired reference port, same lookup `CurrentStationRecord.pairedTide`
    /// does — this gate has no `CurrentStationRecord` of its own to hang it off.
    private var pairedTide: TideStationRecord? {
        gate.tideReference.flatMap { rid in
            if let bundled = TideStationRecord.all.first(where: { $0.id == rid }) { return bundled }
            if case .fitted(let record) = ChsFitService.shared.state(rid) { return record }
            return nil
        }
    }

    /// Fetched view only when the stored window still covers the full strip
    /// (online-gates spec §3: an expired window is the honesty card's job,
    /// same as no window at all — never a chart with a dead zone in it). Not
    /// cached in `@State`: filtering and sorting the stored series is cheap next
    /// to the tide/current harmonic synthesis `CurrentDetailView` caches for.
    /// The magnitude has moved, though — the 30-day fetch
    /// (`Timeline.onlineFetchDays`) made that series ~2,900 samples, roughly 4×
    /// the strip it draws, and this rebuilds on every body evaluation including
    /// scrub frames. Nobody has measured a regression; measure before caching.
    ///
    /// Computed, not `@State` — unlike the other three details, which store
    /// their `TimelineData`. It re-reads `window`/`anchor`/`live` on every
    /// access, so nothing here needs an explicit rebuild when the anchor
    /// moves; SwiftUI re-evaluates it. Don't add a `rebuild()` seam for
    /// symmetry with the others — it would have an empty body.
    ///
    /// The uncovered path pays for a build it discards. That path renders the
    /// honesty card, which nobody scrubs.
    private var timeline: TimelineData? {
        guard let window else { return nil }
        let tl = TimelineData.build(onlinePoints: window.points, tz: tz,
                                    lat: gate.latitude, lon: gate.longitude, now: live, anchor: anchor)
        return window.covers(anchor: anchor) ? tl : nil
    }

    private var scrubSigned: Double { timeline?.velocityAt(scrubTime) ?? 0 }
    private var phase: CurrentPhase { currentPhase(signed: scrubSigned) }
    private var nextSlack: CurrentEvent? {
        timeline?.currentEvents.first { $0.kind == .slack && $0.time > scrubTime }
    }
    private var slackWin: (start: Date, end: Date)? {
        guard let slack = nextSlack, let tl = timeline else { return nil }
        return slackWindow(tl.currentPoints, around: slack.time,
                           threshold: Timeline.slackThresholdKn)
    }

    /// The unfetched card's one tap out: nearest of the 11 shipped (fittable)
    /// gates — never a derived gate, never another online gate.
    private var nearestShipped: ChsCurrentGateInfo? {
        ChsCurrentGateInfo.all.filter { !$0.isOnline }.min {
            distanceKm(lat1: gate.latitude, lon1: gate.longitude, lat2: $0.latitude, lon2: $0.longitude) <
            distanceKm(lat1: gate.latitude, lon1: gate.longitude, lat2: $1.latitude, lon2: $1.longitude)
        }
    }

    var body: some View {
        // Bare gate.id as favoriteId, per PR #31 — left as-is (task-5-brief).
        ScrubDetailScaffold(name: gate.name, region: gate.region,
                            latitude: gate.latitude, longitude: gate.longitude,
                            favoriteId: gate.id, tz: tz,
                            timeline: timeline,
                            entries: { tl in
                                guard let window else { return [] }
                                return scheduleEntries(tl, floodDeg: window.floodDirection,
                                                       ebbDeg: window.ebbDirection, speedUnit: speedUnit)
                            },
                            live: $live, scrubTime: $scrubTime,
                            onReturn: returnToNow,
                            anchor: $anchor,
                            onPickerOpen: prefetchNextBlock,
                            onPicked: { _ in applyAnchor() },
                            above: { EmptyView() },
                            card: { tl in
                                if let window {
                                    readout(window)
                                    TimelineScrubStrip(data: tl, geo: TimelineGeo(data: tl),
                                                       speedUnit: speedUnit, now: live,
                                                       floodDeg: window.floodDirection, ebbDeg: window.ebbDirection,
                                                       scrubTime: $scrubTime)
                                        .padding(.horizontal, -16)  // full-bleed strip
                                        .padding(.top, 12)
                                }
                            },
                            links: {
                                if let port = pairedTide { TideAtPortLink(port: port) }
                            },
                            bottom: {
                                if timeline != nil, let window {
                                    provenance(window)
                                } else {
                                    honestyCard
                                    nearestGateLink
                                }
                            })
            .onAppear {
                let today = todayLocal(tz)
                if anchor == .distantPast { anchor = today }
                if window == nil { window = ChsModelStore.loadOnline(gate.id) }
                RecentsStore.shared.record(gate.id)
                if window?.covers(anchor: anchor) != true, net.online { fetchNow(from: anchor) }
            }
            // A fetch this view did not start — the picker's prefetch — has to
            // reach it. `fetchOnlineWindow` saves and bumps the stamp; that is
            // exactly the "something changed, reload" signal the list's online
            // card already reloads on (SlackwaterApp's `onlineCard`). Without
            // it the speculatively fetched block sits on disk unseen and the
            // first pick into it refetches a month the app already has, which
            // is the entire prefetch, wasted. Subscribing to the one publisher
            // rather than @ObservedObject-ing the service keeps the fit
            // queue's churn from re-rendering a scrubbing strip.
            .onReceive(ChsFitService.shared.$onlineFetchStamp) { _ in
                window = ChsModelStore.loadOnline(gate.id) ?? window
            }
    }

    // MARK: - Fetch

    /// Fired when the picker OPENS, not when a date is chosen: the assumption
    /// is that someone opening a calendar is heading forward, and giving the
    /// round trip the whole browsing interaction is the difference between a
    /// spinner and no spinner.
    ///
    /// Nothing here touches this view's state directly. `fetchOnlineWindow`
    /// merges, saves, and bumps `ChsFitService.onlineFetchStamp`, which the
    /// `.onReceive` above reloads on — the fetch lands and the window updates
    /// itself. A failure is silent BY DESIGN: the user has not asked
    /// for that week yet, so there is nothing to apologise for. If they do
    /// land there and it is missing, `applyAnchor` below says so properly.
    private func prefetchNextBlock() {
        guard let window, net.online, !fetching else { return }
        let from = prefetchAnchor(after: window, tz: tz)
        Task { try? await ChsFitService.fetchOnlineWindow(for: gate, from: from) }
    }

    /// The anchor moved. If the window covers it we are done; if not, this is
    /// the same situation `.onAppear` already handles — fetch when online, and
    /// when offline say nothing, because the honesty card `timeline == nil`
    /// already puts on screen says it better than a flag would.
    ///
    /// `timeline == nil` IS the coverage question, asked once via
    /// `window.covers(anchor:)`, not re-derived here.
    ///
    /// No `rebuild()` call, and deliberately: this view's `timeline` is a
    /// COMPUTED property (unlike the other three details, which store theirs in
    /// `@State`), so setting `anchor` is already enough — SwiftUI re-evaluates
    /// it on the next render.
    private func applyAnchor() {
        if timeline == nil, net.online { fetchNow(from: anchor) }
    }

    /// Always fetches the block the WINDOW is parked on — no default, so no
    /// caller can quietly ask for today's block while the user is looking at
    /// September. That is what "Try again" used to do from the honesty card:
    /// fetch today's 30 days, fail the same coverage check, and redraw the
    /// identical card, with no way out but the back button. (Named `from`, not
    /// `anchor`, so it cannot be mistaken for this view's `@State anchor`.)
    private func fetchNow(from: Date) {
        guard !fetching else { return }
        fetching = true
        fetchFailed = false
        Task { @MainActor in
            do {
                // Persists itself and bumps ChsFitService.onlineFetchStamp on
                // success — this view's own `window` update below is for its
                // OWN redraw; the stamp is what tells any other still-mounted
                // card/detail for this gate to reload the disk copy too.
                //
                // What comes back is the MERGED window, not just the block
                // that was fetched, so assigning it never narrows what this
                // view knows it has. `timeline` is computed off it, so there is
                // no stored data to rebuild.
                let fresh = try await ChsFitService.fetchOnlineWindow(for: gate, from: from)
                window = fresh
                fetching = false
            } catch {
                fetching = false
                fetchFailed = true
            }
        }
    }

    // MARK: - Fetched: readout above the strip

    private func setDegrees(_ signed: Double, _ window: ChsOnlineWindow) -> Double {
        signed >= 0 ? window.floodDirection : window.ebbDirection
    }

    private func readout(_ window: ChsOnlineWindow) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                if phase == .slack {
                    Text("Slack").font(.largeTitle)
                        .foregroundStyle(CurrentDetailView.phaseColor(phase))
                    Text("under \(formatSpeed(slackKn, unit: speedUnit)) \(speedUnitLabel(speedUnit))")
                        .font(.footnote.monospacedDigit()).foregroundStyle(SN.foam.opacity(0.7))
                } else {
                    (Text(formatSpeed(abs(scrubSigned), unit: speedUnit)).font(.largeTitle.monospacedDigit())
                     + Text(" \(speedUnitLabel(speedUnit))").font(.footnote))
                        .foregroundStyle(.white)
                    HStack(spacing: 4) {
                        // The plain-word gloss for non-sailors (#59) — this
                        // hero has the room; list cards lead with direction.
                        Text(phase.gloss.map { "\(phase.word) · \($0)" } ?? phase.word)
                            .font(.footnote)
                        CompassArrow(deg: setDegrees(scrubSigned, window)).font(.footnote)
                        Text(compass16(setDegrees(scrubSigned, window))).font(.footnote)
                    }
                    .foregroundStyle(CurrentDetailView.phaseColor(phase))
                }
            }
            Spacer()
            if let slack = nextSlack {
                // Same two-line window form as CurrentDetailView, minus its
                // tilde/amber provisional treatment — an online gate is never
                // provisional, the published numbers are all there is (#55).
                VStack(alignment: .trailing, spacing: 1) {
                    MonoLabel(text: "Next slack", color: SN.foam.opacity(0.5), tracking: 1.4)
                    if let win = slackWin {
                        // Counts to the window OPENING, not the slack instant:
                        // this readout answers "when can I be there", and the
                        // window is when the pass is transitable. The window
                        // brackets the slack, so it is often already open —
                        // then it says `now` (gutter spec §5).
                        Text(win.start > scrubTime
                             ? "in \(countdown(from: scrubTime, to: win.start))"
                             : "now")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(SN.go)
                        // Time REMAINING, not the window's original length —
                        // an already-open window must not claim its full run.
                        // The threshold prints HERE, once, and not on the
                        // strip.
                        Text("for \(countdown(from: max(scrubTime, win.start), to: win.end)) @ \(formatSpeed(Timeline.slackThresholdKn, unit: speedUnit)) \(speedUnitLabel(speedUnit))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(SN.foam.opacity(0.7))
                            .accessibilityIdentifier("slack-window")
                    } else {
                        Text("in \(countdown(from: scrubTime, to: slack.time))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(SN.go)
                    }
                }
            }
        }
    }

    // MARK: - Fetched: provenance footer (online-gates spec §2, inverse of the fitted footer)

    private func provenance(_ window: ChsOnlineWindow) -> some View {
        DetailFooter {
            Text("CHS-published predictions · fetched \(monthDay(window.fetchedAt, tz)), covers to \(monthDay(window.end, tz)) — not computed on this device")
                .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("online-provenance")
        }
    }

    // MARK: - Unfetched/expired/fetch-failed: the honesty card

    private var honestyCard: some View {
        // `fetching` already makes a tap during the auto-fetch a no-op
        // (fetchNow's own `guard !fetching`) — but "Try again" during that
        // window reads as broken, not busy. Smallest fix: say so. (No
        // wall-clock figure here on purpose: the 30-day fetch is five or six
        // weekly chunks × two series, up from the old 7.5-day window's two or
        // three, and nobody has timed the new one.)
        ChsAmberCard(title: "No offline prediction here", headline: gate.onlineNote ?? "",
                     expectation: expectation, action: fetching ? "Fetching…" : "Try again",
                     identifier: "online-honesty-card") { fetchNow(from: anchor) }
    }

    private var expectation: String {
        // "About a month", not "about a week": one fetch is
        // `Timeline.onlineFetchDays` forward of the anchor. The footer two
        // views up prints the real covers-to date, and the two lines sat on
        // one screen contradicting each other.
        var text = net.online
            ? "Slackwater fetches CHS's official predictions when you're connected — they cover about a month ahead."
            : "Connect for a moment and Slackwater fetches CHS's official predictions — they cover about a month ahead."
        if let window {
            text += " Last fetch covered to \(monthDay(window.end, tz))."
        }
        if fetchFailed {
            text += " The last attempt didn't finish."
        }
        return text
    }

    @ViewBuilder private var nearestGateLink: some View {
        if let nearest = nearestShipped {
            BranchLink(text: "Try \(nearest.name) instead", id: "nearest-gate-link") {
                openChsRoute(.currentGate(nearest))
            }
            .padding(.horizontal, 36)  // lines up with ChsAmberCard's text inset (16 outer + 20 inner)
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
        // And the same coverage check every other anchor move gets. A
        // far-forward pick's fetch can have discarded today's block (disjoint
        // blocks: the incoming one wins), so coming back can land on a month
        // this gate no longer holds — honesty card with no fetch attempted,
        // online or not. `applyAnchor` asks `timeline`, which is computed off
        // the `anchor`/`live` just set here, and fetches when it says nil.
        applyAnchor()
    }
}
