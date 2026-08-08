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
    ///    distance limit on where you can call a function. Four real sites
    ///    are exactly this shape and are hand-verified into
    ///    `knownIndirections` below rather than silently passing unseen:
    ///      - `CurrentCardView.nextLine(_:)` (SlackwaterApp.swift)
    ///      - `RecentRowLabel.reading` (SlackwaterApp.swift)
    ///      - `scheduleEntries()` in the three detail views, consumed by
    ///        `MultiDaySchedule`'s `Text(e.value ?? "—")` in a FOURTH file
    ///        (TimelineStrip.swift)
    ///      - `TimelineStrip.compactTime(_:)` calls `cardTime(` and returns
    ///        a `String` that is only ever rendered through `gutterText(_:)`
    ///        (and `mergedGutterText(_:_:)` once a later task lands), both
    ///        of which apply `.system(size: 10).monospaced()` — so the
    ///        output is mono by construction, but the mono trait sits
    ///        outside the ±4-line window.
    ///    That allowlist is a point-in-time attestation, not a live check:
    ///    if a future edit strips the mono font from one of those four
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
            "TimelineStrip.swift:compactTime", // calls cardTime() but .monospaced() is in gutterText() renderer
        ]
        // The `detail:` exemption below rests on one fact: StationCard's own
        // `Text(detail)` is hardcoded `.monospacedDigit()`. That's an
        // assumption about a file this loop may not even visit that line of
        // on a given run, so don't take it forever on faith — check the live
        // source once, and if it's ever no longer true (someone strips the
        // mono trait from StationCard.swift), every `detail:` site below
        // reverts to being checked normally instead of waved through blind.
        let stationCardLines = try String(
            contentsOf: root.appendingPathComponent("StationCard.swift"), encoding: .utf8)
            .components(separatedBy: .newlines)
        let detailIsMono: Bool = {
            guard let i = stationCardLines.firstIndex(where: { $0.contains("Text(detail)") })
            else { return false }
            let hi = min(stationCardLines.count, i + 3)
            return stationCardLines[i..<hi].joined(separator: "\n").contains("monospacedDigit()")
        }()
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
                // `StationCard`'s `detail` `Text` is hardcoded `.monospacedDigit()`
                // (verified live above, `detailIsMono`), so any string reaching a
                // `detail:` argument is mono by construction — this codebase always
                // shapes it as `detail: <expr>.map { next in` with the formatted
                // string on the very next line, hence the n-1 check alongside
                // same-line.
                //
                // `message:` deliberately gets NO such exemption: StationCard
                // renders `message` as plain `.caption`, no mono treatment — it is
                // prose, not a reading, and a formatter feeding it would be a real
                // bug this guard should still catch. That asymmetry is the whole
                // point, so it needs its own guard here: this codebase writes one
                // named argument per line, and `!line.contains("message:")`
                // stops a `message:` line from inheriting the exemption via the
                // n-1 check just because the previous line happened to say
                // `detail:` (a `StationCard(detail: ..., message: someFormatter(...))`
                // call would otherwise wave the `message:` line through blind —
                // no call site does this today, but the ordinary one-arg-per-line
                // convention would produce exactly that shape the first time one
                // did). This is a bare substring test, not scoped to a `StationCard(`
                // call — `SlackwaterApp.swift`'s `} detail: {` (NavigationSplitView's
                // unrelated trailing-closure label) shares the literal token with no
                // formatter anywhere near it today, so the false-positive risk is
                // theoretical, not live; tightening past that would need a real
                // parser, out of scope for a line-text guard.
                if detailIsMono, !line.contains("message:"),
                   line.contains("detail:") || (n > 0 && lines[n - 1].contains("detail:")) { continue }
                let lo = max(0, n - 4), hi = min(lines.count, n + 5)
                let window = lines[lo..<hi].joined(separator: "\n")
                if windowTokens.contains(where: window.contains) { continue }
                if let owner = enclosingDeclaration(lines, n),
                   knownIndirections.contains("\(url.lastPathComponent):\(owner)") { continue }
                offenders.append("\(url.lastPathComponent):\(n + 1): \(trimmed)")
            }
        }
        // Count is 29 after split-scrubbers deletions (31 before): CurrentDetailView
        // lost its paired-tide readout (two formatHeight sites) and the
        // schedule's tide-extremes rows (one more) — the track it used to
        // borrow, not a regression here. A floor of 25 keeps the same headroom;
        // a floor of 5 would survive the scan silently collapsing to a handful
        // of files — the same "found nothing, passed forever" failure the
        // retired-font test guards with its `scanned > 10`.
        XCTAssertGreaterThan(checked, 25, "expected to find numeric Text sites, found \(checked)")
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

    /// The wordmark's minimumScaleFactor is load-bearing: it shares the 320pt
    /// iPad sidebar row with two 34pt buttons and would break as "Slackwat/er".
    /// Every other name wraps instead of shrinking. This fails in both
    /// directions — a blanket removal, or a fresh one creeping back in.
    func testOnlyTheWordmarkShrinks() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Slackwater")
        let files = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var sites: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            for (n, line) in source.components(separatedBy: .newlines).enumerated()
            where line.contains("minimumScaleFactor") {
                sites.append("\(url.lastPathComponent):\(n + 1)")
            }
        }
        XCTAssertEqual(sites.count, 1,
                       "exactly one minimumScaleFactor should remain (the wordmark), found: \(sites)")
        XCTAssertTrue(sites[0].hasPrefix("SlackwaterApp.swift:"),
                      "the survivor must be the wordmark, found \(sites[0])")
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

extension TypeScaleTests {
    /// ViewThatFits gives no supported way to ask which candidate it chose, so
    /// the split is: unit-test what each tier CONTAINS, screenshot which one
    /// gets PICKED. Do not try to unit-test the picker — that road ends in a
    /// weakened test, which is how this project's colour guard went wrong four
    /// times before it was restructured.
    ///
    /// Two tiers, not three: a third "essential" tier (dropping region) shipped
    /// once and broke two things at once — see the CardTier doc comment.
    /// `ProvisionalBadge` disappearing and `testM50MatchingStationChooser`
    /// failing on the iPad Pro 11" sidebar were the same bug wearing two faces.
    /// `CardField` now has exactly the two cases `content(for:)` consults, so
    /// this is the whole tier contract in one test — and unlike the three it
    /// replaces (`testTiersShedInTheSpecifiedOrder`,
    /// `testEveryTierKeepsNameAndTrailing`, `testRegionNeverSheds`) it can
    /// actually fail for the reason it claims. Those three asserted `.glyph`,
    /// `.name`, `.region` and `.trailing` in `fields`, which no code ever
    /// read: the four render unconditionally, deliberately, because the
    /// region-shedding tier that DID gate them shipped once and broke
    /// `ProvisionalBadge` and `testM50MatchingStationChooser` at the same time
    /// (see the `CardTier` doc comment). The tests passed either way, so they
    /// guarded nothing while reading as if they guarded that.
    ///
    /// Region's own protection is now structural rather than asserted — there
    /// is no `.region` case to put back without also writing the
    /// `if fields.contains(.region)` that the doc comment forbids.
    ///
    /// Both directions, so neither an empty `.full` nor a non-empty `.reduced`
    /// slips through.
    func testDistanceAndDetailShedTogether() {
        XCTAssertEqual(CardTier.full.fields, [.distance, .detail],
                       "the full tier shows both sheddable fields")
        XCTAssertTrue(CardTier.reduced.fields.isEmpty,
                      "distance and detail shed together into reduced, "
                      + "found \(CardTier.reduced.fields)")
    }
}

extension TypeScaleTests {
    /// Anything sized in points beside scaling text has to scale too, or it
    /// becomes a 24pt mark next to 40pt type. @ScaledMetric is the sanctioned
    /// exception to "no literal sizes" — it scales a non-text dimension.
    ///
    /// Both halves of this used to be theatre and are written positively now.
    /// `card.contains("@ScaledMetric")` passed on a *comment* mentioning the
    /// token, and `XCTAssertFalse(app.contains("Color.clear.frame(height: 96)"))`
    /// banned one retired literal — `height: 100` sailed straight through. A
    /// ban on one string is not a guarantee about the surviving code.
    func testGlyphAndFabClearanceScale() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Slackwater")
        let cardLines = try String(contentsOf: root.appendingPathComponent("StationCard.swift"),
                                   encoding: .utf8).components(separatedBy: .newlines)
        // A real declaration, not a mention: same line carries the property
        // wrapper and the name, and it is not a comment.
        XCTAssertTrue(cardLines.contains {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return !t.hasPrefix("//") && t.contains("@ScaledMetric") && t.contains("glyphSize")
        }, "glyphSize must be declared @ScaledMetric — it sits beside the name and has to grow with it")
        // …and the declaration has to reach the glyph, or it scales nothing.
        XCTAssertTrue(cardLines.contains { $0.contains("size: glyphSize") },
                      "StationGlyph must be given the scaled glyphSize")

        let appLines = try String(contentsOf: root.appendingPathComponent("SlackwaterApp.swift"),
                                  encoding: .utf8).components(separatedBy: .newlines)
        let spacers = appLines.filter {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                && $0.contains("Color.clear.frame(height:")
        }
        XCTAssertEqual(spacers.count, 1,
                       "expected exactly one FAB clearance spacer, found \(spacers.count)")
        // Names the surviving expression instead of blacklisting a dead one:
        // any bare literal height fails this, not just the retired 96.
        XCTAssertTrue(spacers.first?.contains("fabClearance") == true,
                      "the FAB clearance spacer must be driven by fabClearance, not a literal: "
                      + (spacers.first ?? "<none>"))
    }
}
