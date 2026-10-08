import XCTest

/// Reduce Motion, executable. The value-driven sites — the scrubber's scale
/// glide, the slack-window preview — already spell `reduceMotion ? nil :` in
/// their `.animation(_:value:)`, and the sky's twinkle pauses its timeline.
/// The imperative `withAnimation` sites had no such habit, and two of them
/// animated regardless (#602): the schedule's day disclosure and the
/// first-run tour's scroll. Scanned repo-wide rather than per file, like the
/// retired-font and glass scans, because the survivor is always in the file
/// nobody thought to check.
final class ReduceMotionTests: XCTestCase {

    /// `withAnimation` and its guard on ONE line, which is why this scan is a
    /// line scan: an `Animation?` lifted into a computed property reads fine
    /// and is invisible here, so the house spelling keeps them together.
    /// `nil` is the no-motion animation — SwiftUI applies the state change
    /// without one — so no site needs a second branch.
    func testEveryWithAnimationHonoursReduceMotion() throws {
        var offenders: [String] = []
        for (name, source) in try appSources() {
            for (n, line) in source.components(separatedBy: .newlines).enumerated() {
                let code = codeOnly(line)
                guard code.contains("withAnimation") else { continue }
                guard !code.contains("reduceMotion") else { continue }
                offenders.append("\(name):\(n + 1): \(code.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "withAnimation must pass `reduceMotion ? nil : <animation>` on the same line:\n"
                      + offenders.joined(separator: "\n"))
    }
}
