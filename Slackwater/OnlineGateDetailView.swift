// Slackwater — GPL v3. The 7 online (fit-reject) gates' detail (online-gates
// spec §2/§3): no on-device model exists for these, ever — the fetched CHS
// window is the only source of truth. Modeled on CurrentDetailView's
// post-split single-track anatomy, minus everything fit/provisional (there is
// no fast answer here, only the real published numbers or an honest why-not).
import SwiftUI
import TideEngine

struct OnlineGateDetailView: View {
    let gate: ChsCurrentGateInfo
    @AppStorage(unitsKey) private var units = "imperial"
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
    // `TimelineScrubStrip` wants this even though the strip is current-only
    // here (no tide track, ever) — same dead parameter CurrentDetailView
    // carries for the same reason.
    private var imperial: Bool { units == "imperial" }

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
    /// cached in `@State`: a few hundred filtered/sorted points is cheap next
    /// to the tide/current harmonic synthesis `CurrentDetailView` caches for.
    ///
    /// Computed, not `@State` — unlike the other three details, which store
    /// their `TimelineData`. It re-reads `window`/`anchor`/`live` on every
    /// access, so nothing here needs an explicit rebuild when the anchor
    /// moves; SwiftUI re-evaluates it. Don't add a `rebuild()` seam for
    /// symmetry with the others — it would have an empty body.
    private var timeline: TimelineData? {
        guard let window, window.covers(anchor: anchor, today: todayLocal(tz)) else { return nil }
        return TimelineData.build(onlinePoints: window.points, tz: tz,
                                  lat: gate.latitude, lon: gate.longitude, now: live, anchor: anchor)
    }

    private var scrubSigned: Double { timeline?.velocityAt(scrubTime) ?? 0 }
    private var phase: CurrentPhase { currentPhase(signed: scrubSigned) }
    private var nextSlack: CurrentEvent? {
        timeline?.currentEvents.first { $0.kind == .slack && $0.time > scrubTime }
    }
    /// The peak after the next slack — "then Max ebb 3.1 kn" (web `following`).
    private var following: CurrentEvent? {
        nextSlack.flatMap { slack in
            timeline?.currentEvents.first { $0.kind != .slack && $0.time > slack.time }
        }
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
        ScrollView {
            VStack(spacing: 0) {
                // Bare gate.id, per PR #31 — left as-is (task-5-brief).
                MapHeader(name: gate.name, region: gate.region,
                          latitude: gate.latitude, longitude: gate.longitude, favoriteId: gate.id)
                if let window, let tl = timeline {
                    scrubCard(tl, window)
                    scheduleCard(tl, window)
                        .padding(.top, 14)
                    provenance(window)
                        .padding(.top, 14)
                } else {
                    honestyCard
                        .padding(.top, 14)
                    nearestGateLink
                        .padding(.top, 14)
                }
            }
            .padding(.bottom, 42)
        }
        .ignoresSafeArea(edges: .top)
        .background(SN.page.ignoresSafeArea())
        .environment(\.timeZone, tz)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if anchor == .distantPast { anchor = todayLocal(tz) }
            if window == nil { window = ChsModelStore.loadOnline(gate.id) }
            RecentsStore.shared.record(gate.id)
            if window?.covers(anchor: anchor, today: todayLocal(tz)) != true, net.online { fetchNow() }
        }
    }

    // MARK: - Fetch

    private func fetchNow() {
        guard !fetching else { return }
        fetching = true
        fetchFailed = false
        Task { @MainActor in
            do {
                // Persists itself and bumps ChsFitService.onlineFetchStamp on
                // success — this view's own `window` update below is for its
                // OWN redraw; the stamp is what tells any other still-mounted
                // card/detail for this gate to reload the disk copy too.
                let fresh = try await ChsFitService.fetchOnlineWindow(for: gate)
                window = fresh
                fetching = false
            } catch {
                fetching = false
                fetchFailed = true
            }
        }
    }

    // MARK: - Fetched: scrub card, strip, current readout, tide-at-port link

    private func setDegrees(_ signed: Double, _ window: ChsOnlineWindow) -> Double {
        signed >= 0 ? window.floodDirection : window.ebbDirection
    }

    private func scrubCard(_ tl: TimelineData, _ window: ChsOnlineWindow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TimelineScrubStrip(data: tl, geo: TimelineGeo(data: tl),
                               imperial: imperial, speedUnit: speedUnit,
                               now: live,
                               floodDeg: window.floodDirection, ebbDeg: window.ebbDirection,
                               scrubTime: $scrubTime)
                .padding(.horizontal, -16)  // full-bleed strip
                .padding(.top, 12)

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
                            Text(phaseWord(phase)).font(.footnote)
                            CompassArrow(deg: setDegrees(scrubSigned, window)).font(.footnote)
                            Text(compass16(setDegrees(scrubSigned, window))).font(.footnote)
                        }
                        .foregroundStyle(CurrentDetailView.phaseColor(phase))
                    }
                }
                Spacer()
                if let slack = nextSlack {
                    VStack(alignment: .trailing, spacing: 1) {
                        MonoLabel(text: "Next slack", color: SN.foam.opacity(0.5), tracking: 1.4)
                        Text("in \(countdown(from: scrubTime, to: slack.time)) · \(cardTime(slack.time, tz))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(SN.go)
                        if let win = slackWin {
                            // "under 0.5 kn" is restored here for the same reason
                            // it came back on the current detail: this is the one
                            // place the threshold earns its space.
                            Text("under \(formatSpeed(Timeline.slackThresholdKn, unit: speedUnit)) \(speedUnitLabel(speedUnit)) · \(cardTime(win.start, tz))–\(cardTime(win.end, tz)) · \(countdown(from: win.start, to: win.end))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(SN.foam.opacity(0.7))
                                .accessibilityIdentifier("slack-window")
                        }
                        if let then = following {
                            Text("then \(then.turnLabel.lowercased()) \(formatSpeed(abs(then.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit))")
                                .font(.caption.monospacedDigit()).foregroundStyle(SN.foam.opacity(0.7))
                        }
                    }
                }
            }
            .padding(.top, 8)

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

    // MARK: - Fetched: rolling multi-day schedule

    private func scheduleCard(_ tl: TimelineData, _ window: ChsOnlineWindow) -> some View {
        MultiDaySchedule(entries: scheduleEntries(tl, window), tz: tz, anchor: tl.anchor,
                         today: tl.today, days: tl.days,
                         scrubTime: scrubTime, onTap: { scrubTime = $0 })
            .background(SN.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(SN.cardStroke, lineWidth: 0.5))
            .padding(.horizontal, 16)
    }

    private func scheduleEntries(_ tl: TimelineData, _ window: ChsOnlineWindow) -> [ScheduleEntry] {
        let out: [ScheduleEntry] = tl.currentEvents
            .filter { tl.scheduleRange.contains($0.time) }
            .map { e in
                switch e.kind {
                case .slack:
                    ScheduleEntry(time: e.time, pill: .slack)
                case .maxFlood:
                    ScheduleEntry(time: e.time, pill: .flood,
                                  value: "\(formatSpeed(abs(e.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit))",
                                  arrowDeg: window.floodDirection)
                case .maxEbb:
                    ScheduleEntry(time: e.time, pill: .ebb,
                                  value: "\(formatSpeed(abs(e.speed), unit: speedUnit)) \(speedUnitLabel(speedUnit))",
                                  arrowDeg: window.ebbDirection)
                }
            }
        return out.sorted { $0.time < $1.time }
    }

    // MARK: - Fetched: provenance footer (online-gates spec §2, inverse of the fitted footer)

    private func provenance(_ window: ChsOnlineWindow) -> some View {
        VStack(spacing: 6) {
            MonoLabel(text: "Predictions — not for navigation",
                      color: SN.foam.opacity(0.4), tracking: 1.4)
            Text("CHS-published predictions · fetched \(monthDay(window.fetchedAt, tz)), covers to \(monthDay(window.end, tz)) — not computed on this device")
                .font(.caption2).foregroundStyle(SN.foam.opacity(0.3))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("online-provenance")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    // MARK: - Unfetched/expired/fetch-failed: the honesty card

    private var honestyCard: some View {
        // `fetching` already makes a tap during the ~30s auto-fetch a no-op
        // (fetchNow's own `guard !fetching`) — but "Try again" during that
        // window reads as broken, not busy. Smallest fix: say so.
        ChsAmberCard(title: "No offline prediction here", headline: gate.onlineNote ?? "",
                     expectation: expectation, action: fetching ? "Fetching…" : "Try again",
                     identifier: "online-honesty-card") { fetchNow() }
    }

    private var expectation: String {
        var text = net.online
            ? "Slackwater fetches CHS's official predictions when you're connected — they cover about a week."
            : "Connect for a moment and Slackwater fetches CHS's official predictions — they cover about a week."
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
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption2.weight(.semibold))
                Text("Try \(nearest.name) instead")
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(SN.leaf)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { openChsRoute(.currentGate(nearest)) }
            .padding(.horizontal, 36)  // lines up with ChsAmberCard's text inset (16 outer + 20 inner)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("nearest-gate-link")
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
    }
}
