import XCTest
@testable import Slackwater

final class ScrubWhenTests: XCTestCase {

    private let vancouver = TimeZone(identifier: "America/Vancouver")!

    /// Local-midnight day boundaries, not 24h intervals: 23:30 → 00:00+30m is
    /// "tomorrow" even though only half an hour passed.
    func testDayOffsetCrossesLocalMidnightNotDayLengths() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = vancouver
        let live = cal.date(from: DateComponents(year: 2026, month: 8, day: 3,
                                                 hour: 23, minute: 30))!
        XCTAssertEqual(scrubDayOffset(live, from: live, vancouver), 0)
        XCTAssertEqual(scrubDayOffset(live.addingTimeInterval(3600), from: live, vancouver), 1,
                       "30 min after midnight is tomorrow")
        XCTAssertEqual(scrubDayOffset(live.addingTimeInterval(-48 * 3600), from: live, vancouver), -2)
    }
}
