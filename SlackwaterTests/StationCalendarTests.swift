// Slackwater — GPL v3. Station calendar subscriptions: what each kind publishes, what it's
// called, and the free tier's one-at-a-time rule.
import XCTest
@testable import Slackwater

final class StationCalendarTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "station-calendar-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }

    // MARK: what a kind publishes

    func testATideStationPublishesBothExtremesAndEclipses() {
        XCTAssertEqual(calendarTriggers(for: .tide), [.tideExtreme(high: true),
                                                      .tideExtreme(high: false), .eclipse])
    }

    func testACurrentStationPublishesSlackWindowsAndEclipses() {
        XCTAssertEqual(calendarTriggers(for: .current), [.slackWindowOpens, .eclipse])
    }

    func testADerivedGatePublishesItsSlacksAndEclipses() {
        XCTAssertEqual(calendarTriggers(for: .derived), [.slack, .eclipse])
    }

    func testMaxFloodAndEbbAreNotPublished() {
        // ~8 events a day would make the calendar unreadable (spec §5.1).
        XCTAssertFalse(calendarTriggers(for: .current).contains(.currentPeak(flood: true)))
        XCTAssertFalse(calendarTriggers(for: .current).contains(.currentPeak(flood: false)))
    }

    // MARK: titles

    func testATideAndACurrentStationSharingANameGetDifferentTitles() {
        // Friday Harbor is both a tide station and a current station. One title between them
        // would have each run adopt the other's calendar and rewrite its events.
        XCTAssertNotEqual(stationCalendarTitle(name: "Friday Harbor", kind: .tide),
                          stationCalendarTitle(name: "Friday Harbor", kind: .current))
    }

    func testATitleNamesTheStationAndItsSeries() {
        XCTAssertEqual(stationCalendarTitle(name: "Friday Harbor", kind: .tide), "Friday Harbor Tides")
        XCTAssertEqual(stationCalendarTitle(name: "Race Passage", kind: .current), "Race Passage Currents")
        XCTAssertEqual(stationCalendarTitle(name: "Dodd Narrows", kind: .derived), "Dodd Narrows Currents")
    }

    // MARK: the free tier's one calendar

    func testAFreeUsersFirstStationJustGoesOn() {
        XCTAssertEqual(calendarSubscriptionChange([], stationID: "a", premium: false), .add)
    }

    func testAFreeUsersSecondStationReplacesTheFirst() {
        let on = [StationCalendar(stationID: "a", calendarID: "cal-a")]
        XCTAssertEqual(calendarSubscriptionChange(on, stationID: "b", premium: false),
                       .replace(stationID: "a"))
    }

    func testAFreeUserWhoKeptSeveralCalendarsCannotAddAnother() {
        // A lapsed Premium keeps what it published (spec §5.1). Swapping one of them for a new
        // station would make the free tier hold as many calendars as Premium ever did.
        let on = (1...3).map { StationCalendar(stationID: "s\($0)", calendarID: "cal-\($0)") }

        XCTAssertEqual(calendarSubscriptionChange(on, stationID: "new", premium: false), .upsell)
        XCTAssertEqual(calendarSubscriptionChange(on, stationID: "s2", premium: false), .remove,
                       "turning one of them off is still allowed")
    }

    func testPremiumAddsAlongsideWhatIsAlreadyOn() {
        let on = [StationCalendar(stationID: "a", calendarID: "cal-a")]
        XCTAssertEqual(calendarSubscriptionChange(on, stationID: "b", premium: true), .add)
    }

    func testTurningOffTheStationThatIsOnRemovesIt() {
        let on = [StationCalendar(stationID: "a", calendarID: "cal-a")]
        XCTAssertEqual(calendarSubscriptionChange(on, stationID: "a", premium: false), .remove)
        XCTAssertEqual(calendarSubscriptionChange(on, stationID: "a", premium: true), .remove)
    }

    // MARK: the store

    @MainActor func testSubscriptionsSurviveARoundTrip() {
        let d = defaults()
        let store = StationCalendarStore(defaults: d)
        store.subscribe("a")
        store.setCalendarID("cal-a", for: "a")

        let reloaded = StationCalendarStore(defaults: d)

        XCTAssertEqual(reloaded.subscriptions, [StationCalendar(stationID: "a", calendarID: "cal-a")])
        XCTAssertEqual(reloaded.calendarID(for: "a"), "cal-a")
    }

    // MARK: which calendars a run rewrites

    private func entry(_ stationID: String) -> AlertEntry {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        return AlertEntry(stationID: stationID,
                          occurrence: AlertOccurrence(ruleID: UUID(), event: t, fire: t),
                          copy: AlertCopy(title: "Slack window", body: "14:32"),
                          url: nil,
                          place: AlertPlace(name: "Race Passage", tz: .gmt))
    }

    func testASubscribedStationWithNoEventsIsStillEmptied() {
        // It resolved and genuinely has nothing in the next 90 days — an empty plan is the
        // truth, and a calendar holding last month's events must be cleared.
        let groups = calendarWriteGroups([], subscribed: ["a"], live: ["a"], skipping: [])

        XCTAssertEqual(Set(groups.keys), ["a"])
        XCTAssertEqual(groups["a"]?.count, 0)
    }

    func testAStationThatCouldNotLoadIsLeftAlone() {
        // "Nothing known yet" is not "delete the next 90 days" — a CHS station waiting on its
        // fit must not have its calendar wiped on every foreground.
        let groups = calendarWriteGroups([], subscribed: ["a", "b"], live: ["a", "b"], skipping: ["b"])

        XCTAssertEqual(Set(groups.keys), ["a"])
    }

    func testEntriesGoToTheirOwnStationsCalendar() {
        let groups = calendarWriteGroups([entry("a"), entry("b"), entry("a")],
                                         subscribed: ["a", "b"], live: ["a", "b"], skipping: [])

        XCTAssertEqual(groups["a"]?.count, 2)
        XCTAssertEqual(groups["b"]?.count, 1)
    }

    func testAStationTurnedOffDuringTheResolveIsNotWritten() {
        // The real shape of it: `subscribed` is the snapshot the 90-day resolve started from, so
        // a station turned off since is still in it, carrying a full plan. Writing that plan
        // would build a fresh calendar seconds after the user watched its own be deleted — one
        // the app holds no id for and can never remove.
        let groups = calendarWriteGroups([entry("gone"), entry("a")],
                                         subscribed: ["a", "gone"], live: ["a"], skipping: [])

        XCTAssertEqual(Set(groups.keys), ["a"])
        XCTAssertEqual(groups["a"]?.count, 1)
    }

    func testAStationTurnedOnDuringTheResolveWaitsForItsOwnPass() {
        // The other side of the intersection: the store holds it, but this run's resolve never
        // planned for it. An empty plan would read as "delete the next 90 days" on a calendar
        // another device may already have filled. Its own toggle drives the pass that fills it.
        let groups = calendarWriteGroups([entry("a")], subscribed: ["a"], live: ["a", "new"],
                                         skipping: [])

        XCTAssertEqual(Set(groups.keys), ["a"])
    }

    func testASkippedStationsEntriesCannotResurrectIt() {
        // A station's own entries must not override a skip: a plan for a station that could not
        // load is a stale leftover, not proof it resolved after all.
        let groups = calendarWriteGroups([entry("b")], subscribed: ["a", "b"], live: ["a", "b"],
                                         skipping: ["b"])

        XCTAssertEqual(Set(groups.keys), ["a"])
    }

    @MainActor func testASubscribedStationWithoutACalendarYetReturnsNilID() {
        let store = StationCalendarStore(defaults: defaults())
        store.subscribe("a")

        XCTAssertNil(store.calendarID(for: "a"), "no EventKit calendar exists for it yet")
    }

    @MainActor func testSubscribingTwiceKeepsOneSubscriptionAndItsCalendar() {
        let store = StationCalendarStore(defaults: defaults())
        store.subscribe("a")
        store.setCalendarID("cal-a", for: "a")
        store.subscribe("a")

        XCTAssertEqual(store.subscriptions.count, 1)
        XCTAssertEqual(store.calendarID(for: "a"), "cal-a")
    }

    @MainActor func testUnsubscribingForgetsTheCalendar() {
        let store = StationCalendarStore(defaults: defaults())
        store.subscribe("a")
        store.setCalendarID("cal-a", for: "a")
        store.unsubscribe("a")

        XCTAssertEqual(store.subscriptions, [])
        XCTAssertNil(store.calendarID(for: "a"))
    }

    @MainActor func testSubscribeSkipsNotifyingOnlyWhenToldTo() {
        // A caller that drives its own `AlertScheduler.reschedule()` and awaits the result
        // (CalendarStationsView.subscribeAndVerify) passes `notify: false` so `onChange` doesn't
        // also fire `requestReschedule()` — that would be a second, unawaited pass over the same
        // 90-day resolve. Every other caller keeps the default.
        let store = StationCalendarStore(defaults: defaults())
        var notified = 0
        store.onChange = { notified += 1 }

        store.subscribe("a", notify: false)
        XCTAssertEqual(notified, 0)

        store.subscribe("b")
        XCTAssertEqual(notified, 1)
    }
}
