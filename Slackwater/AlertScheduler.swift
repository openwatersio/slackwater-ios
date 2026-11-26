// Slackwater — GPL v3. Runs the alert pipeline — rules → occurrences → plan → writers — on launch and on every change (docs/alerts.md §6).
import Foundation

/// A detached resolution is valid only for rules that still match its snapshot.
func unchangedResolvedRules(_ snapshot: [AlertRule], current: [AlertRule]) -> [AlertRule] {
    snapshot.filter { current.contains($0) }
}

func activeRuleIDs(_ rules: [AlertRule]) -> Set<UUID> {
    Set(rules.filter(\.enabled).map(\.id))
}

struct AlertActivityPolicy {
    let reviewIDs: Set<UUID>
    let expiryProtected: Set<UUID>
    let liveRuleIDs: Set<UUID>
}

func alertActivityPolicy(rules: [AlertRule], reviewCandidates: Set<UUID>, measuredWindows: Set<UUID>,
                         runningActivities: Set<UUID>, runningWindows: Set<UUID>, heldWindows: Set<UUID>,
                         threshold: Double) -> AlertActivityPolicy {
    let active = activeRuleIDs(rules)
    let running = runningActivities.intersection(active)
    let currentRules = Set(rules.filter { $0.trigger == .slackWindowOpens }.map(\.id))
    let offWindows = slackWindowIsOff(threshold) ? runningWindows.intersection(active).intersection(currentRules) : []
    return AlertActivityPolicy(reviewIDs: reviewCandidates.subtracting(running),
                               expiryProtected: measuredWindows.union(running),
                               liveRuleIDs: active.subtracting(heldWindows.union(offWindows)))
}

/// One planned delivery with everything a writer needs.
struct AlertEntry {
    /// Which station's calendar this belongs in.
    let stationID: String
    let occurrence: AlertOccurrence
    let copy: AlertCopy
    let url: URL?
    let place: AlertPlace
}

struct ResolvedAlerts: Sendable {
    /// From rules: what becomes a notification.
    var occurrences: [AlertOccurrence] = []
    /// From station subscriptions: what the calendar publishes.
    var calendarOccurrences: [AlertOccurrence] = []
    /// The throwaway rules behind `calendarOccurrences`, so copy has a trigger to read.
    var calendarRules: [UUID: AlertRule] = [:]
    /// Which station each of those belongs to, so the writer knows the calendar.
    var calendarStations: [UUID: String] = [:]
    /// Keyed by station id.
    var places: [String: AlertPlace] = [:]
    /// Keyed by station id: which glyph a Live Activity draws.
    var kinds: [String: StationCalendarKind] = [:]
    /// Keyed by station id: the series a Live Activity's face is cut from.
    var stations: [String: WidgetStation] = [:]
    /// Enabled rules whose station can't be loaded yet — a CHS station not fitted on this
    /// device, or an id that left the catalog.
    var unresolved: Set<UUID> = []
    /// Off-mode current rules for which the available predictions contain no true slack.
    var noSlack: Set<UUID> = []
    var heldWindows: Set<UUID> = []
    /// Once selections whose comfort window still contains the present.
    var activeWindows: Set<UUID> = []
    var legacyReview: Set<UUID> = []
    /// Subscribed current stations with predictions but no true slack in Off mode.
    var calendarNoSlack: Set<String> = []
    var calendarEmpty: Set<String> = []
    /// Subscribed stations that can't be loaded. Their calendars are left exactly as they
    /// are: an empty plan is "nothing known yet", not "delete the next 90 days".
    var unresolvedStations: Set<String> = []
}

func offModeHasNoSlack(_ rule: AlertRule, station: WidgetStation, position: (lat: Double, lon: Double),
                       now: Date, until: Date, occurrences: [AlertOccurrence]) -> Bool {
    if let moment = rule.once {
        var selected = rule
        selected.sun = nil
        let slacks = alertOccurrences(selected, station: station, position: position,
                                      from: moment.addingTimeInterval(-21_600),
                                      to: moment.addingTimeInterval(21_600), threshold: 0)
        if rule.currentWindowRule { return slacks.isEmpty }
        return !slacks.contains { abs($0.event.timeIntervalSince(alertMinute(moment))) <= 120 }
    }
    var withoutSun = rule
    withoutSun.sun = nil
    withoutSun.once = nil
    let allSlacks = rule.sun == nil && rule.once == nil ? occurrences : alertOccurrences(withoutSun, station: station,
        position: position, from: now, to: until, threshold: 0)
    return allSlacks.isEmpty
}

/// Occurrences for every enabled rule and every subscribed station, from `now` to the calendar
/// horizon. Off the main actor: a season-scale scan per station is real work.
/// ponytail: two rules on one station load it twice; share the record if that ever measures.
func resolveAlerts(_ rules: [AlertRule], subscriptions: [String],
                   now: Date, threshold: Double) -> ResolvedAlerts {
    var resolved = ResolvedAlerts()
    let until = now.addingTimeInterval(AlertHorizon.calendar)

    for rule in rules where rule.enabled && rule.slackNeedsReview != true {
        if rule.currentWindowRule && ((!rule.currentWindowWasOff && slackWindowIsOff(threshold))
            || (rule.currentWindowWasOff && !slackWindowIsOff(threshold) && rule.once.map { $0 > now } == true)) {
            resolved.heldWindows.insert(rule.id)
            continue
        }
        guard let record = WidgetStationLoader.loadRecord(id: rule.stationID, at: now) else {
            resolved.unresolved.insert(rule.id)
            continue
        }
        resolved.places[rule.stationID] = record.alertPlace
        resolved.kinds[rule.stationID] = record.calendarKind
        let station = WidgetStationLoader.station(from: record)
        resolved.stations[rule.stationID] = station
        // TODO(#944): Retire the legacy-rule review after older builds are no longer supported.
        // Old rules can refer to an axis crossing that is not a true slack. The new
        // event list cannot reconstruct that selection, so do not silently retarget it.
        if rule.trigger == .slackWindowOpens, let once = rule.once,
           (!rule.currentWindowRule || rule.currentWindowWasOff),
           once.addingTimeInterval(21_600) >= now, !slackWindowIsOff(threshold),
           case .current = station {
            resolved.legacyReview.insert(rule.id)
            continue
        }
        if rule.trigger == .slackWindowOpens, rule.currentWindowRule, !slackWindowIsOff(threshold),
           let selected = rule.once, selected < now, case .current(let current, _, _) = station {
            let minute = alertMinute(selected)
            let windows = slackWindowOpenings(current, from: minute, to: now, threshold: threshold)
            let containing = windows.first {
                alertMinute($0.event) <= minute && ($0.end ?? $0.observedThrough).map { minute <= alertMinute($0) } == true
            }
            let next = windows.first { alertMinute($0.event) >= minute
                && alertMinute($0.event).timeIntervalSince(minute) <= 21_600 }
            if let selected = containing ?? next,
               (selected.end ?? selected.observedThrough).map({ $0 >= now }) == true {
                resolved.activeWindows.insert(rule.id)
            }
        }
        let occurrences = alertOccurrences(rule, station: station, position: record.alertPosition,
                                           from: now, to: until, threshold: threshold)
        if rule.trigger == .slackWindowOpens, slackWindowIsOff(threshold),
           case .current(let current, _, _) = station,
           current.speeds(from: now, to: now.addingTimeInterval(600), step: 600).count >= 2 {
            if offModeHasNoSlack(rule, station: station, position: record.alertPosition,
                                 now: now, until: until, occurrences: occurrences) {
                resolved.noSlack.insert(rule.id)
                continue
            }
        }
        resolved.occurrences += occurrences
    }

    for stationID in subscriptions {
        guard let record = WidgetStationLoader.loadRecord(id: stationID, at: now) else {
            resolved.unresolvedStations.insert(stationID)
            continue
        }
        resolved.places[stationID] = record.alertPlace
        resolved.kinds[stationID] = record.calendarKind
        let station = WidgetStationLoader.station(from: record)
        for trigger in calendarTriggers(for: record.calendarKind) {
            // A throwaway rule per trigger. Its id only has to be unique within this run:
            // a calendar event is matched by its content, never by an occurrence key.
            let rule = AlertRule(stationID: stationID, trigger: trigger)
            resolved.calendarRules[rule.id] = rule
            resolved.calendarStations[rule.id] = stationID
            let occurrences = alertOccurrences(rule, station: station, position: record.alertPosition,
                                               from: now, to: until, threshold: threshold)
            resolved.calendarOccurrences += occurrences
            if trigger == .slackWindowOpens, slackWindowIsOff(threshold), occurrences.isEmpty,
               case .current(let current, _, _) = station,
               current.speeds(from: now, to: now.addingTimeInterval(600), step: 600).count >= 2 {
                resolved.calendarNoSlack.insert(stationID)
            }
        }
    }
    let withEvents = Set(resolved.calendarOccurrences.compactMap { resolved.calendarStations[$0.ruleID] })
    resolved.calendarEmpty = Set(subscriptions).subtracting(resolved.unresolvedStations).subtracting(withEvents)
    return resolved
}

struct AlertStatusSnapshot: Equatable {
    var scheduledThrough: [UUID: Date] = [:]
    var unresolved: Set<UUID> = []
    var noSlack: Set<UUID> = []
    var heldWindows: Set<UUID> = []
    var reviewPending: Set<UUID> = []
    var calendarNoSlack: Set<String> = []
    var calendarEmpty: Set<String> = []
    var notificationsAuthorized = false
}

@MainActor final class AlertScheduler: ObservableObject {
    static let shared = AlertScheduler()

    @Published private(set) var status = AlertStatusSnapshot()
    private var running = false
    private var again = false

    /// Safe from anywhere. One run at a time; any number of requests during a run buy
    /// exactly one more.
    nonisolated static func requestReschedule() {
        Task { @MainActor in await shared.coalesced() }
    }

    private func coalesced() async {
        if running { again = true; return }
        running = true
        repeat {
            again = false
            await reschedule()
        } while again
        running = false
    }

    /// The pass in flight, if any. Every pass runs after the one before it: a direct call and a
    /// coalesced one never interleave, so neither can write off a snapshot the other has already
    /// superseded — `AlertNotifications.apply` suspends between removing requests and adding
    /// them, and an older pass resuming there would restore what a newer one had cleared after a
    /// rule or tier change.
    private var pass: Task<Void, Never>?

    /// One full pass: expire what's due, resolve 90 days off the main actor, then write the
    /// calendars and the notifications. Queued behind any pass already running, and awaited to
    /// completion: `CalendarStationsView.subscribeAndVerify` reads whether a calendar came out of
    /// this exact pass, which is the only signal that a source refused to make one. Routing it
    /// through the coalescer would return before the work it is inspecting happened.
    func reschedule(now: Date = appNow()) async {
        let previous = pass
        let mine = Task { @MainActor in
            await previous?.value
            while !(await self.runPass(now: now)) {}
        }
        pass = mine
        await mine.value
    }

    private func runPass(now: Date) async -> Bool {
        _ = ChsFitService.shared
        let storedRules = AlertRuleStore.shared.rules
        let threshold = slackThresholdKn
        let premium = PremiumStore.shared.isPremium
        let premiumEnds = PremiumStore.shared.hasPurchased ? nil : FreeDayStore.shared.current?.end
        let imperial = heightUnits() != "metric"

        let stored = StationCalendarStore.shared.subscriptions
        let subscriptions = publishingStations(stored, premium: premium)
        let stopped = Set(stored.map(\.stationID)).subtracting(subscriptions)

        let resolved = await Task.detached(priority: .utility) {
            resolveAlerts(storedRules, subscriptions: subscriptions, now: now, threshold: threshold)
        }.value
        // A preference change can land while the prediction scan is off the main actor.
        // Discard its old result before changing alerts, then resolve the new setting.
        guard threshold == slackThresholdKn else { return false }
        // ActivityKit stores absolute times even when the app's debug clock is pinned.
        let activityClock = Date()
        let liveRecords = AlertLiveActivities.activeRecords()
        let liveActivities = liveActivityRuleIDs(liveRecords, now: activityClock)
        let liveWindows = liveWindowRuleIDs(liveRecords, now: activityClock)
        let policy = alertActivityPolicy(rules: storedRules, reviewCandidates: resolved.legacyReview,
                                         measuredWindows: resolved.activeWindows, runningActivities: liveActivities,
                                         runningWindows: liveWindows,
                                         heldWindows: resolved.heldWindows, threshold: threshold)
        _ = AlertRuleStore.shared.markSlackNeedsReview(storedRules, ids: policy.reviewIDs)
        let expired = Set(expiredUnchangedRules(storedRules, current: AlertRuleStore.shared.rules,
                                                now: now, occurrences: resolved.occurrences, unresolved: resolved.unresolved,
                                                noSlack: resolved.noSlack, heldWindows: resolved.heldWindows,
                                                activeWindows: policy.expiryProtected))
        for id in expired { AlertRuleStore.shared.remove(id) }
        await AlertNotifications.notifySlackReview(AlertRuleStore.shared.rules, places: resolved.places, premium: premium)
        let rules = unchangedResolvedRules(storedRules, current: AlertRuleStore.shared.rules)
            .filter { !expired.contains($0.id) }
        let plan = deliveryPlan(rules: rules, occurrences: resolved.occurrences,
                                calendarOccurrences: resolved.calendarOccurrences,
                                now: now, premium: premium, premiumEnds: premiumEnds)
        // A duplicated rule id would trap uniqueKeysWithValues; keep the first, as deliveryPlan does.
        let byID = Dictionary(rules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .merging(resolved.calendarRules) { mine, _ in mine }

        func entries(_ list: [AlertOccurrence], includeLead: Bool, includePlace: Bool) -> [AlertEntry] {
            list.compactMap { o in
                guard let rule = byID[o.ruleID], let place = resolved.places[rule.stationID] else { return nil }
                return AlertEntry(
                    stationID: rule.stationID,
                    occurrence: o,
                    copy: alertCopy(rule, o, place: place, imperial: imperial,
                                    threshold: threshold, includeLead: includeLead,
                                    includePlace: includePlace),
                    url: shareURL(forStationID: rule.stationID, at: o.event, tz: place.tz)
                        ?? deepLink(forStationID: rule.stationID),
                    place: place)
            }
        }

        AlertCalendar.apply(entries(plan.calendar, includeLead: false, includePlace: false),
                            subscribed: subscriptions, skipping: resolved.unresolvedStations,
                            stopped: stopped, now: now)
        // Candidates first: an occurrence the system takes as a scheduled activity is delivered by
        // that activity's start alert, so it leaves the notification list for this run (spec §5.3).
        let kinds = resolved.kinds, stations = resolved.stations
        let currentLiveRules = AlertRuleStore.shared.rules
        let unchangedIDs = Set(unchangedResolvedRules(storedRules, current: currentLiveRules).map(\.id))
        let livePolicy = alertActivityPolicy(rules: currentLiveRules, reviewCandidates: [],
                                             measuredWindows: [], runningActivities: liveActivities,
                                             runningWindows: liveWindows,
                                             heldWindows: resolved.heldWindows.intersection(unchangedIDs), threshold: threshold)
        let placed = await AlertLiveActivities.apply(
            entries(plan.liveActivities, includeLead: false, includePlace: true),
            water: { kinds[$0] == .tide ? .tide : .current },
            curve: { entry in stations[entry.stationID].flatMap { liveActivityCurve($0, around: entry.occurrence.event) } },
            liveRuleIDs: livePolicy.liveRuleIDs, imperial: imperial)
        await AlertNotifications.apply(entries(plannedNotifications(plan, placed: placed),
                                               includeLead: true, includePlace: true))

        status = AlertStatusSnapshot(scheduledThrough: scheduledThrough(plan),
                                     unresolved: resolved.unresolved.intersection(Set(rules.map(\.id))),
                                     noSlack: resolved.noSlack.intersection(Set(rules.map(\.id))),
                                     heldWindows: resolved.heldWindows.intersection(Set(rules.map(\.id))),
                                     reviewPending: Set(rules.filter { $0.once != nil && !$0.currentWindowRule
                                         && resolved.noSlack.contains($0.id) }.map(\.id)),
                                     calendarNoSlack: resolved.calendarNoSlack.intersection(Set(StationCalendarStore.shared.subscriptions.map(\.stationID))),
                                     calendarEmpty: resolved.calendarEmpty.intersection(Set(StationCalendarStore.shared.subscriptions.map(\.stationID))),
                                     notificationsAuthorized: await AlertNotifications.authorized())
        return true
    }
}
