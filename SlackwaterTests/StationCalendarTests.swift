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
        let groups = calendarWriteGroups([], subscribed: ["a"], skipping: [])

        XCTAssertEqual(Set(groups.keys), ["a"])
        XCTAssertEqual(groups["a"]?.count, 0)
    }

    func testAStationThatCouldNotLoadIsLeftAlone() {
        // "Nothing known yet" is not "delete the next 90 days" — a CHS station waiting on its
        // fit must not have its calendar wiped on every foreground.
        let groups = calendarWriteGroups([], subscribed: ["a", "b"], skipping: ["b"])

        XCTAssertEqual(Set(groups.keys), ["a"])
    }

    func testEntriesGoToTheirOwnStationsCalendar() {
        let groups = calendarWriteGroups([entry("a"), entry("b"), entry("a")],
                                         subscribed: ["a", "b"], skipping: [])

        XCTAssertEqual(groups["a"]?.count, 2)
        XCTAssertEqual(groups["b"]?.count, 1)
    }

    func testAnUnsubscribedStationsEntriesAreDropped() {
        // Belt and braces: a stale entry can't resurrect a calendar the user turned off.
        let groups = calendarWriteGroups([entry("gone")], subscribed: ["a"], skipping: [])

        XCTAssertEqual(Set(groups.keys), ["a"])
        XCTAssertEqual(groups["a"]?.count, 0)
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
}
