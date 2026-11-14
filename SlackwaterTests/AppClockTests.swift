// Slackwater — GPL v3. The app runs on one clock, `appNow()`, which a Debug
// launch pins with `-nowEpoch`. A wait or filter that reads the real clock
// instead drifts from everything planned on the pinned one (#802).
import XCTest
@testable import Slackwater

final class AppClockTests: XCTestCase {
    /// A moment the pin could sit on, far from the real clock either way.
    private let now = Date(timeIntervalSince1970: 1_789_000_000)  // 2026-09-09 PDT

    /// A retry due five minutes after a pinned now waits five minutes, not
    /// until the real clock reaches a 2026 instant.
    func testRetryWaitIsMeasuredOnTheAppClock() {
        XCTAssertEqual(ChsQueue.retryWait(until: now.addingTimeInterval(300), now: now), 300)
        XCTAssertEqual(ChsQueue.retryWait(until: now.addingTimeInterval(-300), now: now), 1,
                       "a retry already due still yields the loop")
    }

    /// A notification's wait is measured from the clock it is handed. A fire
    /// time already behind yields no wait: nothing records what iOS has
    /// delivered, and the plan moves such a reminder to now on every pass, so
    /// requesting it would buzz again on each one.
    func testNotificationWaitIsMeasuredFromTheClockHandedIn() {
        func entry(fireIn seconds: TimeInterval) -> AlertEntry {
            let fire = now.addingTimeInterval(seconds)
            return AlertEntry(stationID: "a",
                              occurrence: AlertOccurrence(ruleID: UUID(), event: fire.addingTimeInterval(1_800), fire: fire),
                              copy: AlertCopy(title: "t", body: "b"), url: nil,
                              place: AlertPlace(name: "a", tz: .current))
        }
        XCTAssertEqual(notificationWait(for: entry(fireIn: 60), from: now), 60)
        XCTAssertNil(notificationWait(for: entry(fireIn: 0), from: now), "on the tie it is behind")
        XCTAssertNil(notificationWait(for: entry(fireIn: -1), from: now))
    }

    /// `timeIntervalSinceNow` is always the real clock; a sleep or a filter in
    /// the app measures from `appNow()` instead.
    func testNoAppSourceMeasuresAWaitOnTheRealClock() throws {
        var offenders: [String] = []
        for (name, source) in try appSources() {
            for (n, line) in source.components(separatedBy: .newlines).enumerated()
            where codeOnly(line).contains("timeIntervalSinceNow") {
                offenders.append("\(name):\(n + 1)")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "real-clock interval in app source; measure from appNow():\n" + offenders.joined(separator: "\n"))
    }

    /// A `Date` default is the only clock a caller that passes none ever sees,
    /// so it is the app clock. The one exception is a default compared with a
    /// `CLLocation` timestamp, which the system stamps on the real clock; the
    /// scan allows it only on a line that names that type.
    func testDateDefaultsTakeTheAppClock() throws {
        var offenders: [String] = []
        for (name, source) in try appSources() {
            for (n, line) in source.components(separatedBy: .newlines).enumerated() {
                let code = codeOnly(line)
                guard !code.contains("CLLocation") else { continue }
                if code.contains(": Date = .now") || code.contains(": Date = Date()") || code.contains(": Date = Date.now") {
                    offenders.append("\(name):\(n + 1)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "Date default on the real clock; default to appNow():\n" + offenders.joined(separator: "\n"))
    }
}
