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
    /// time already behind waits one second while the event is ahead.
    func testNotificationWaitIsMeasuredFromTheClockHandedIn() {
        func entry(fireIn seconds: TimeInterval) -> AlertEntry {
            let fire = now.addingTimeInterval(seconds)
            return AlertEntry(stationID: "a",
                              occurrence: AlertOccurrence(ruleID: UUID(), event: fire.addingTimeInterval(1_800), fire: fire),
                              copy: AlertCopy(title: "t", body: "b"), url: nil,
                              place: AlertPlace(name: "a", tz: .current))
        }
        XCTAssertEqual(notificationWait(for: entry(fireIn: 60), from: now), 60)
        XCTAssertEqual(notificationWait(for: entry(fireIn: 0), from: now), 1)
        XCTAssertEqual(notificationWait(for: entry(fireIn: -1), from: now), 1)
    }

    func testOnlyAnEditInsideTheLeadAuthorizesAnImmediateReminder() {
        let rule = AlertRule(stationID: "a", trigger: .slack, lead: 1_800)
        let event = now.addingTimeInterval(900)
        let occurrence = AlertOccurrence(ruleID: rule.id, event: event, fire: now)
        XCTAssertNil(immediateAlertKey(occurrence, rule: rule, editTimes: [:]))
        XCTAssertNil(immediateAlertKey(occurrence, rule: rule, editTimes: [rule.id.uuidString: now.addingTimeInterval(-1_000).timeIntervalSince1970]))
        XCTAssertNotNil(immediateAlertKey(occurrence, rule: rule, editTimes: [rule.id.uuidString: now.timeIntervalSince1970]))
        XCTAssertNil(immediateAlertKey(occurrence, rule: rule, editTimes: [rule.id.uuidString: now.timeIntervalSince1970], previous: rule))
        var shorter = rule
        shorter.lead = 300
        XCTAssertNotNil(immediateAlertKey(occurrence, rule: rule, editTimes: [rule.id.uuidString: now.timeIntervalSince1970], previous: shorter))
        var disabled = rule
        disabled.enabled = false
        let earlier = AlertRuleRevision(rule: rule, ended: now.addingTimeInterval(-300))
        XCTAssertNil(immediateAlertKey(occurrence, rule: rule, editTimes: [rule.id.uuidString: now.timeIntervalSince1970], previous: disabled, history: [earlier]))
        XCTAssertNil(immediateAlertKey(occurrence, rule: rule, editTimes: [rule.id.uuidString: event.timeIntervalSince1970]))
    }

    func testARepeatingRuleKeepsItsFirstImmediateSelectionAcrossPasses() {
        let rule = AlertRule(stationID: "a", trigger: .slack, lead: 86_400)
        let first = AlertOccurrence(ruleID: rule.id, event: now.addingTimeInterval(3_600), fire: now)
        let second = AlertOccurrence(ruleID: rule.id, event: now.addingTimeInterval(7_200), fire: now)
        let edits = [rule.id.uuidString: now.timeIntervalSince1970]
        let immediate = [first.key: "first", second.key: "second"]
        var selected: [String: String] = [:]
        XCTAssertEqual(selectImmediateReminders([second, first], immediate: immediate, editTimes: edits, selected: &selected),
                       [first.key: "first"])
        XCTAssertTrue(selectImmediateReminders([second], immediate: immediate, editTimes: edits, selected: &selected).isEmpty)
    }

    func testImmediateReminderIsSentOnceAndPendingIsKept() {
        XCTAssertEqual(immediateReminderAction(hasEdit: false, handled: false, pending: false), .skip)
        XCTAssertEqual(immediateReminderAction(hasEdit: true, handled: false, pending: false), .send)
        XCTAssertEqual(immediateReminderAction(hasEdit: true, handled: true, pending: true), .keep)
        XCTAssertEqual(immediateReminderAction(hasEdit: true, handled: true, pending: false), .skip)
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
