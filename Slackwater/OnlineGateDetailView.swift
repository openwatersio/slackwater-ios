// Slackwater — GPL v3. The 7 online (fit-reject) gates' detail (online-gates
// spec §2/§3): no on-device model exists for these, ever — the fetched CHS
// window is the only source of truth. Modeled on CurrentDetailView's
// post-split single-track anatomy, minus everything fit/provisional (there is
// no fast answer here, only the real published numbers or an honest why-not).
import SwiftUI
import TideEngine

struct OnlineGateDetailView: View {
    let gate: ChsCurrentGateInfo
    @AppStorage(speedUnitKey, store: AppGroup.defaults) private var speedUnit = "kn"
    @AppStorage(AppGroup.slackWindowSpeedKey, store: AppGroup.defaults)
    private var slackWindowSpeed = defaultSlackThresholdKn
    @ObservedObject private var net = Connectivity.shared
    @Environment(\.openChsRoute) private var openChsRoute

    @State private var live = appNow()
    @State private var scrubTime = appNow()
    /// The store's block for the current `anchor` — narrower than "this
    /// gate's whole store" since #67 item 4: the disjoint blocks live on
    /// disk, and `window` is only ever the one covering where the view is
    /// parked. Re-picked via `block(covering: anchor)` on `onAppear`,
    /// `.onReceive`, and `applyAnchor`.
    @State private var window: ChsOnlineWindow?
    /// The local midnight the window hangs from. Only `returnToNow` and (in
    /// Plan B) the range bar move it; everything else reads it.
    @State private var anchor = Date.distantPast
    @State private var fetching = false
    @State private var fetchFailed = false

    private var tz: TimeZone { gate.tz }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        return calendar
    }

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
                                    lat: gate.latitude, lon: gate.longitude, now: live, anchor: anchor,
                                    threshold: normalizedSlackThresholdKn(slackWindowSpeed))
        return window.covers(anchor: anchor) ? tl : nil
    }

    private var scrubSigned: Double { timeline?.velocityAt(scrubTime) ?? 0 }
    private var phase: CurrentPhase { currentPhase(signed: scrubSigned) }
    private var activeSlackWin: (slack: Date, start: Date, end: Date)? {
        timeline?.containingSlackWindow(at: scrubTime)
    }
    private var nextSlack: CurrentEvent? {
        timeline?.currentEvents.first { $0.kind == .slack && $0.time > scrubTime }
    }
    private var slackWin: (start: Date, end: Date)? {
        guard let slack = nextSlack, let tl = timeline else { return nil }
        return slackWindow(tl.currentPoints, around: slack.time,
                           threshold: slackThresholdKn)
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
                            scrubSummary: { tl in
                                guard let range = currentPeakToPeakRange(tl.currentEvents, around: scrubTime) else { return nil }
                                return ("Range", "\(formatSpeed(range, unit: speedUnit)) \(speedUnitLabel(speedUnit))")
                            },
                            above: { EmptyView() },
                            card: { tl in
                                if let window {
                                    readout(window)
                                    TimelineScrubStrip(data: tl, geo: TimelineGeo(data: tl),
                                                       speedUnit: speedUnit, now: live,
                                                       floodDeg: window.floodDirection, ebbDeg: window.ebbDirection,
                                                       scrubTime: $scrubTime, onReturn: returnToNow)
                                        .padding(.horizontal, -16)  // full-bleed strip
                                        .padding(.top, 12)
                                }
                            },
                            links: {
                                if let port = pairedTide { TideAtPortLink(port: port) }
                            },
                            bottom: {
                                if let note = gate.magnitudeNote {
                                    Text("Large-tide context: \(note). Not a prediction for this pass.")
                                        .font(.caption2)
                                        .foregroundStyle(SN.foam.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                }
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
                if window == nil { window = ChsModelStore.loadOnline(gate.id)?.block(covering: anchor) }
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
                window = ChsModelStore.loadOnline(gate.id)?.block(covering: anchor) ?? window
            }
            .onChange(of: net.online) { _, online in
                if online, timeline == nil { fetchNow(from: anchor) }
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

    /// The anchor moved. The store may already hold a block for it — paging back
    /// to a week the app has must be a disk read, never a refetch (#67 item 4) —
    /// so re-pick first; only then is a nil timeline a real gap worth a fetch.
    private func applyAnchor() {
        if let block = ChsModelStore.loadOnline(gate.id)?.block(covering: anchor) { window = block }
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
                if let win = activeSlackWin {
                    Text("Slack").font(.title2.weight(.medium))
                        .foregroundStyle(CurrentDetailView.phaseColor(.slack))
                    Text(slackWindowTiming(start: win.start, end: win.end, tz: tz))
                        .font(.title3.monospacedDigit()).foregroundStyle(SN.foam.opacity(0.7))
                } else {
                    Text("\(phase.gloss?.capitalized ?? phase.word) · \(phase.word)")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(CurrentDetailView.phaseColor(phase))
                    HStack(spacing: 4) {
                        Text("\(formatSpeed(abs(scrubSigned), unit: speedUnit)) \(speedUnitLabel(speedUnit))")
                            .font(.title3.monospacedDigit())
                        CompassArrow(deg: setDegrees(scrubSigned, window)).font(.title3)
                        Text(compass16(setDegrees(scrubSigned, window))).font(.title3)
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
                        Text("for \(countdown(from: max(scrubTime, win.start), to: win.end)) @ \(formatSpeed(slackThresholdKn, unit: speedUnit)) \(speedUnitLabel(speedUnit))")
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
            Text(onlineDownloadValidity(end: window.offlineValidUntil, calendar: calendar))
                .font(.caption2).foregroundStyle(SN.foam.opacity(0.55))
            Button("Refresh") { fetchNow(from: todayLocal(tz)) }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(net.online ? SN.leaf : SN.foam.opacity(0.45))
                .disabled(fetching || !net.online)
        }
    }

    // MARK: - Download status

    private var honestyCard: some View {
        ChsAmberCard(title: downloadTitle, headline: gate.onlineNote ?? "",
                     expectation: expectation, action: downloadAction,
                     identifier: "online-honesty-card", status: downloadStatus) {
            fetchNow(from: anchor)
        }
    }

    private var downloadStatus: CardStatus {
        if fetching { return .downloading }
        if fetchFailed { return .failed }
        return onlineGateStatus(window, online: net.online)
    }

    private var downloadTitle: String {
        switch downloadStatus {
        case .downloading: "Downloading"
        case .failed: "Download failed"
        case .offline: "Waiting for signal"
        case .expired: "Offline download expired"
        default: "Download for offline use"
        }
    }

    private var downloadAction: String {
        switch downloadStatus {
        case .downloading: "Downloading…"
        case .failed: "Retry"
        case .expired: "Download"
        case .offline: "Connect to download"
        default: "Download"
        }
    }

    private var expectation: String {
        // "About a month", not "about a week": one fetch is
        // `Timeline.onlineFetchDays` forward of the anchor. The footer two
        // views up prints the real covers-to date, and the two lines sat on
        // one screen contradicting each other.
        var text = net.online
            ? "Downloads cover about a month and can be refreshed at any time."
            : "Connect for a moment to download about a month of predictions."
        // Deliberate: a disk read per body evaluation, but this only renders
        // on the honesty path — re-pick into state if it ever shows in a trace.
        if let window = ChsModelStore.loadOnline(gate.id)?.blocks.last {
            text += " \(onlineDownloadValidity(end: window.offlineValidUntil, calendar: calendar))."
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
        // And the same coverage check every other anchor move gets.
        // `applyAnchor` asks `timeline`, which is computed off the
        // `anchor`/`live` just set here, and fetches when it says nil.
        applyAnchor()
    }
}
