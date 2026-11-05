import XCTest
@testable import Slackwater

final class FreeDayTests: XCTestCase {
    let seattle: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }()
    func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func testAvailableWhenNeverUsed() { XCTAssertTrue(freeDayAvailable(lastStart: nil, now: date("2026-11-05T12:00:00Z"), calendar: seattle)) }
    func testUsedThisMonthIsUnavailable() {
        XCTAssertFalse(freeDayAvailable(lastStart: date("2026-11-02T18:00:00Z"), now: date("2026-11-20T18:00:00Z"), calendar: seattle))
    }
    func testLateLastMonthLocalIsAvailableOnTheFirst() {
        // Oct 31 23:00 Seattle is Nov 1 06:00 UTC; it still counts for October.
        XCTAssertTrue(freeDayAvailable(lastStart: date("2026-11-01T06:00:00Z"), now: date("2026-11-01T08:30:00Z"), calendar: seattle))
    }
    func testStartedJustAfterLocalMidnightCountsForThatMonth() {
        // Nov 1 00:30 Seattle is Nov 1 07:30 UTC.
        XCTAssertFalse(freeDayAvailable(lastStart: date("2026-11-01T07:30:00Z"), now: date("2026-11-15T12:00:00Z"), calendar: seattle))
    }
    func testClockMovedBackWithinThisMonthIsUnavailable() {
        XCTAssertFalse(freeDayAvailable(lastStart: date("2026-11-25T18:00:00Z"), now: date("2026-11-05T18:00:00Z"), calendar: seattle))
    }
    func testClockMovedBackFromALaterMonthIsAvailable() {
        XCTAssertTrue(freeDayAvailable(lastStart: date("2026-12-10T18:00:00Z"), now: date("2026-11-05T18:00:00Z"), calendar: seattle))
    }
    func testNextFreeDayIsStartOfNextLocalMonth() {
        XCTAssertEqual(nextFreeDayDate(lastStart: date("2026-11-02T18:00:00Z"), calendar: seattle), date("2026-12-01T08:00:00Z"))
    }
    func testRunningForTwentyFourHours() {
        let day = FreeDay(start: date("2026-11-05T22:00:00Z"))
        XCTAssertTrue(freeDayRunning(day, at: date("2026-11-06T21:59:59Z")))
        XCTAssertFalse(freeDayRunning(day, at: date("2026-11-06T22:00:00Z")))
    }
    func testFutureStartIsNotRunning() {
        XCTAssertFalse(freeDayRunning(FreeDay(start: date("2026-11-07T00:00:00Z")), at: date("2026-11-05T00:00:00Z")))
    }
    func testNoFreeDayIsNotRunning() {
        XCTAssertFalse(freeDayRunning(nil, at: date("2026-11-05T00:00:00Z")))
    }
    func testPremiumActive() {
        let day = FreeDay(start: date("2026-11-05T00:00:00Z"))
        XCTAssertTrue(premiumActive(purchased: true, freeDay: nil, at: .distantFuture))
        XCTAssertTrue(premiumActive(purchased: false, freeDay: day, at: date("2026-11-05T12:00:00Z")))
        XCTAssertFalse(premiumActive(purchased: false, freeDay: day, at: date("2026-11-06T00:00:00Z")))
    }

    func testDebugLengthOverrideAcceptsAStringLikeALaunchArgument() {
        UserDefaults.standard.set("300", forKey: "freeDayLength")
        defer { UserDefaults.standard.removeObject(forKey: "freeDayLength") }
        XCTAssertEqual(FreeDay.length, 300)
        UserDefaults.standard.removeObject(forKey: "freeDayLength")
        XCTAssertEqual(FreeDay.length, 86_400)
    }

    func testEntryDatesIncludeTheFreeDayEnd() {
        let now = date("2026-11-05T12:10:00Z"), end = date("2026-11-05T15:47:00Z")
        let dates = widgetEntryDates(now: now, freeDayEnd: end)
        XCTAssertTrue(dates.contains(end)); XCTAssertEqual(dates.first, now); XCTAssertEqual(dates, dates.sorted())
    }
    func testEntryDatesWithoutAFreeDayAreTheStride() {
        XCTAssertEqual(widgetEntryDates(now: date("2026-11-05T12:00:00Z"), freeDayEnd: nil).count, 48)
    }
    func testEntryDatesIgnoreAnEndOutsideTheWindow() {
        let now = date("2026-11-05T12:00:00Z")
        XCTAssertEqual(widgetEntryDates(now: now, freeDayEnd: now.addingTimeInterval(-60)).count, 48)
        XCTAssertEqual(widgetEntryDates(now: now, freeDayEnd: now.addingTimeInterval(86_400)).count, 48)
    }
    func testEntryDatesDoNotRepeatAnEndOnTheStride() {
        let now = date("2026-11-05T12:00:00Z")
        XCTAssertEqual(widgetEntryDates(now: now, freeDayEnd: now.addingTimeInterval(3_600)).count, 48)
    }
    func testStoredFreeDayReadsTheStartAndIsNilWhenAbsent() {
        let defaults = UserDefaults(suiteName: "FreeDayTests.stored")!
        defaults.removePersistentDomain(forName: "FreeDayTests.stored")
        XCTAssertNil(storedFreeDay(defaults))
        let start = date("2026-11-05T12:00:00Z")
        defaults.set(start, forKey: AppGroup.freeDayStartKey)
        XCTAssertEqual(storedFreeDay(defaults), FreeDay(start: start))
    }
}
