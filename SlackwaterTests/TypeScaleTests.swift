import XCTest
@testable import Slackwater

final class TypeScaleTests: XCTestCase {

    /// Repo-wide, not file-scoped, and deliberately so: the last time this
    /// project guarded a retired token one file at a time, the survivor was in
    /// the file nobody thought to check.
    func testNoSourceFileSpellsARetiredFont() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SlackwaterTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Slackwater")
        let retired = [".fraunces(", ".geist(", ".geistMono(",
                       "Fraunces-", "Geist-", "GeistMono-"]
        let files = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil),
            "could not walk \(root.path)")
        var scanned = 0
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            scanned += 1
            let source = try String(contentsOf: url, encoding: .utf8)
            for (n, line) in source.components(separatedBy: .newlines).enumerated() {
                for token in retired where line.contains(token) {
                    offenders.append("\(url.lastPathComponent):\(n + 1): \(token)")
                }
            }
        }
        // A scan that silently found no files would pass forever.
        XCTAssertGreaterThan(scanned, 10, "expected to scan the app's sources, walked \(scanned) files")
        XCTAssertTrue(offenders.isEmpty,
                      "retired font reference still in source:\n" + offenders.joined(separator: "\n"))
    }

    /// The bundled families must not come back via Info.plist either.
    func testNoBundledFontsDeclared() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let projectYml = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        XCTAssertFalse(projectYml.contains("UIAppFonts"),
                       "UIAppFonts must be gone — bundled fonts are retired")
        XCTAssertFalse(projectYml.contains(".ttf"),
                       "no .ttf should be referenced from project.yml")
    }
}

extension TypeScaleTests {
    /// Every formatter that produces a number feeds a Text that must not
    /// jitter as digits change. Asserted on source text because SwiftUI
    /// exposes no way to read a resolved Font back off a view.
    ///
    /// GUARD LIMITS — read before trusting a green run here. This is a
    /// line-proximity text scan, not a compiler, and it has two known blind
    /// spots rather than none:
    ///
    /// 1. It only recognizes mono treatment within a small ±4-line window
    ///    around the formatter call (plus a same-line-only check for
    ///    `MonoLabel(`, whose own `Text` is hardcoded `.monospaced()` in
    ///    Theme.swift). A formatter that happens to sit a few lines from an
    ///    unrelated Text's mono font — coincidence of source layout, not a
    ///    real connection — would pass exactly as readily as a real one; the
    ///    window can't tell the difference. (An earlier draft of this fix
    ///    folded `MonoLabel(` into the window check instead of same-line-only
    ///    and it silently passed a deliberately-broken `cardTime` site two
    ///    lines below an unrelated `MonoLabel` — restored to same-line-only
    ///    after that rehearsal caught it.)
    ///
    /// 2. A formatter relayed through a helper `func`/computed `var` that
    ///    returns a `String`, consumed by a `Text` far away or in another
    ///    file, is invisible to line-proximity scanning — Swift puts no
    ///    distance limit on where you can call a function. Three real sites
    ///    are exactly this shape and are hand-verified into
    ///    `knownIndirections` below rather than silently passing unseen:
    ///      - `CurrentCardView.nextLine(_:)` (SlackwaterApp.swift)
    ///      - `RecentRowLabel.reading` (SlackwaterApp.swift)
    ///      - `scheduleEntries()` in the three detail views, consumed by
    ///        `MultiDaySchedule`'s `Text(e.value ?? "—")` in a FOURTH file
    ///        (TimelineStrip.swift)
    ///    That allowlist is a point-in-time attestation, not a live check:
    ///    if a future edit strips the mono font from one of those three
    ///    consuming `Text`s, this test will NOT catch it — the regression
    ///    would be invisible to source-text scanning. Closing that gap needs
    ///    real data-flow analysis (a SwiftSyntax pass), out of scope for an
    ///    XCTest that reads files as strings.
    func testNumericFormattersAreMonospacedDigit() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Slackwater")
        let formatters = ["formatHeight(", "formatSpeed(", "formatNm(", "cardTime(", "dayLine("]
        // Accepted anywhere in the ±4-line window: .monospacedDigit() fixes
        // digit width; .monospaced() is a strict superset (every glyph fixed).
        let windowTokens = ["monospacedDigit()", ".monospaced()"]
        // See blind spot 2 above — "File.swift:declaringSymbol".
        let knownIndirections: Set<String> = [
            "SlackwaterApp.swift:nextLine",
            "SlackwaterApp.swift:reading",
            "TideDetailView.swift:scheduleEntries",
            "CurrentDetailView.swift:scheduleEntries",
            "DerivedGateDetailView.swift:scheduleEntries",
        ]
        let files = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var checked = 0
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            let lines = source.components(separatedBy: .newlines)
            for (n, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }  // e.g. "formatSpeed(_:unit:)" in a doc comment
                let matched = formatters.filter { line.contains($0) }
                guard !matched.isEmpty else { continue }
                // Skip the formatters' own `func` definitions (Theme.swift /
                // LocationService.swift) — not call sites.
                guard !matched.contains(where: { line.contains("func \($0)") }) else { continue }
                checked += 1
                // Same-line only — see blind-spot-1 note above.
                if line.contains("MonoLabel(") { continue }
                let lo = max(0, n - 4), hi = min(lines.count, n + 5)
                let window = lines[lo..<hi].joined(separator: "\n")
                if windowTokens.contains(where: window.contains) { continue }
                if let owner = enclosingDeclaration(lines, n),
                   knownIndirections.contains("\(url.lastPathComponent):\(owner)") { continue }
                offenders.append("\(url.lastPathComponent):\(n + 1): \(trimmed)")
            }
        }
        XCTAssertGreaterThan(checked, 5, "expected to find numeric Text sites, found \(checked)")
        XCTAssertTrue(offenders.isEmpty,
                      "numeric reading without mono treatment (or a named indirection exception):\n"
                      + offenders.joined(separator: "\n"))
    }

    /// The chrome lived in four places and drifted. One shell owns it now;
    /// this fails if a variant grows its own copy back.
    func testCardChromeLivesInExactlyOnePlace() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Slackwater")
        let files = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var sites: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            for (n, line) in source.components(separatedBy: .newlines).enumerated()
            where line.contains("minHeight: 96") {
                sites.append("\(url.lastPathComponent):\(n + 1)")
            }
        }
        XCTAssertEqual(sites.count, 1, "card chrome must exist once, found: \(sites)")
        XCTAssertTrue(sites[0].hasPrefix("StationCard.swift:"),
                      "chrome must live in StationCard.swift, found \(sites[0])")
    }

    /// The nearest enclosing `func`/computed `var` above line `n`: a line
    /// that (after any access modifiers) contains `func <name>` or
    /// `var <name>` and ends with an unmatched opening brace. Indentation-
    /// free, not a real parser — good enough for this codebase's consistent
    /// style, and it only ever feeds the small hand-verified allowlist
    /// above, never a pass/fail decision by itself.
    private func enclosingDeclaration(_ lines: [String], _ n: Int) -> String? {
        var i = n
        while i >= 0 {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("{"),
               let range = trimmed.range(of: #"\b(func|var)\s+(\w+)"#, options: .regularExpression) {
                let words = trimmed[range].split(separator: " ")
                if words.count >= 2 { return String(words[1]) }
            }
            i -= 1
        }
        return nil
    }
}
