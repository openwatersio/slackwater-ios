import XCTest
@testable import Slackwater

final class TypeScaleTests: XCTestCase {

    /// Repo-wide, not file-scoped, and deliberately so: the last time this
    /// project guarded a retired token one file at a time, the survivor was in
    /// the file nobody thought to check.
    func testNoSourceFileSpellsARetiredFont() throws {
        let retired = [".fraunces(", ".geist(", ".geistMono(",
                       "Fraunces-", "Geist-", "GeistMono-"]
        var offenders: [String] = []
        for (name, source) in try appSources() {
            for (n, line) in source.components(separatedBy: .newlines).enumerated() {
                for token in retired where line.contains(token) {
                    offenders.append("\(name):\(n + 1): \(token)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "retired font reference still in source:\n" + offenders.joined(separator: "\n"))
    }

    /// The bundled families must not come back via Info.plist either.
    func testNoBundledFontsDeclared() throws {
        let projectYml = try repoSource("project.yml")
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
    ///      - `scheduleEntries()` in the four detail views, consumed by
    ///        `MultiDaySchedule`'s `Text(e.value ?? "—")` in a FIFTH file
    ///        (TimelineStrip.swift)
    ///    (`TimelineStrip.compactTime(_:)` was a fifth until the NEAPS pass
    ///    deleted it along with the gutter — its `cardTime(` reading now
    ///    prints as 24h `clockTime(`, which is not a watched formatter.)
    ///    That allowlist is a point-in-time attestation, not a live check:
    ///    if a future edit strips the mono font from one of those
    ///    consuming `Text`s, this test will NOT catch it — the regression
    ///    would be invisible to source-text scanning. Closing that gap needs
    ///    real data-flow analysis (a SwiftSyntax pass), out of scope for an
    ///    XCTest that reads files as strings.
    func testNumericFormattersAreMonospacedDigit() throws {
        let formatters = ["formatHeight(", "formatSpeed(", "formatNm(", "cardTime("]
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
            // The NEAPS bands: both tracks format their reading at the
            // `drawBand(...)` call and the `.monospacedDigit()` lives in
            // `drawBand`'s own value `Text`, one renderer for the whole chart.
            // Two entries buy back what the gutter's five separate label
            // builders used to cost.
            "TimelineStrip.swift:drawTide",
            "TimelineStrip.swift:drawCurrent",
        ]
        // The `detail:` exemption below rests on one fact: StationCard's own
        // `Text(detail)` is hardcoded `.monospacedDigit()`. That's an
        // assumption about a file this loop may not even visit that line of
        // on a given run, so don't take it forever on faith — check the live
        // source once, and if it's ever no longer true (someone strips the
        // mono trait from StationCard.swift), every `detail:` site below
        // reverts to being checked normally instead of waved through blind.
        let stationCardLines = try repoSource("Slackwater/StationCard.swift")
            .components(separatedBy: .newlines)
        let detailIsMono: Bool = {
            guard let i = stationCardLines.firstIndex(where: { $0.contains("Text(detail)") })
            else { return false }
            let hi = min(stationCardLines.count, i + 3)
            return stationCardLines[i..<hi].joined(separator: "\n").contains("monospacedDigit()")
        }()
        var checked = 0
        var offenders: [String] = []
        for (name, source) in try appSources() {
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
                   knownIndirections.contains("\(name):\(owner)") { continue }
                offenders.append("\(name):\(n + 1): \(trimmed)")
            }
        }
        // Count is 33, measured across this merge. The gutter branch dropped it
        // to 23 — the readouts lost their absolute cardTime()/formatSpeed()
        // lines when exact times moved to the strip's gutter — and the branch
        // lowered this floor to 20 to match. Merging online-gates put it back
        // up: OnlineGateDetailView alone contributes 7 sites. The floor returns
        // to 25 because the premise for lowering it is gone, not because 25 is
        // magic; 33 against 25 is the same order of headroom the number was
        // originally chosen with. A floor of 5 would survive the scan silently
        // collapsing to a handful of files — the same "found nothing, passed
        // forever" failure the retired-font test guards with its `scanned > 10`.
        XCTAssertGreaterThan(checked, 25, "expected to find numeric Text sites, found \(checked)")
        XCTAssertTrue(offenders.isEmpty,
                      "numeric reading without mono treatment (or a named indirection exception):\n"
                      + offenders.joined(separator: "\n"))
    }

    /// The chrome lived in four places and drifted. One shell owns it now;
    /// this fails if a variant grows its own copy back.
    func testCardChromeLivesInExactlyOnePlace() throws {
        var sites: [String] = []
        for (name, source) in try appSources() {
            for (n, line) in source.components(separatedBy: .newlines).enumerated()
            where line.contains("minHeight: 96") {
                sites.append("\(name):\(n + 1)")
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
        var sites: [String] = []
        for (name, source) in try appSources() {
            for (n, line) in source.components(separatedBy: .newlines).enumerated()
            where line.contains("minimumScaleFactor") {
                sites.append("\(name):\(n + 1)")
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
        let cardLines = try repoSource("Slackwater/StationCard.swift")
            .components(separatedBy: .newlines)
        // A real declaration, not a mention: same line carries the property
        // wrapper and the name, and it is not a comment.
        XCTAssertTrue(cardLines.contains {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return !t.hasPrefix("//") && t.contains("@ScaledMetric") && t.contains("glyphSize")
        }, "glyphSize must be declared @ScaledMetric — it sits beside the name and has to grow with it")
        // …and the declaration has to reach the glyph, or it scales nothing.
        XCTAssertTrue(cardLines.contains { $0.contains("size: glyphSize") },
                      "StationGlyph must be given the scaled glyphSize")

        let appLines = try repoSource("Slackwater/SlackwaterApp.swift")
            .components(separatedBy: .newlines)
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

extension TypeScaleTests {
    /// The two current details drifted a redesign apart (#55): the online
    /// gates kept the strip above the readout and the pre-redesign next-slack
    /// copy long after `CurrentDetailView` moved on. Both tag the same
    /// readout `slack-window`, so the cheap guard is that both still spell it
    /// the same way and put it in the same place.
    ///
    /// Source text, like every other check in this file — SwiftUI exposes no
    /// way to read a rendered hierarchy back. It catches a divergence, not a
    /// rendering difference.
    func testSlackWindowReadoutMatchesAcrossCurrentDetails() throws {
        let window = "for \\(countdown(from: max(scrubTime, win.start), to: win.end)) @ "
        for file in ["Slackwater/CurrentDetailView.swift",
                     "Slackwater/OnlineGateDetailView.swift"] {
            let src = try repoSource(file)
            XCTAssertTrue(src.contains(window),
                          "\(file) must print the slack window in the shared two-line form")
            XCTAssertTrue(src.contains(".accessibilityIdentifier(\"slack-window\")"),
                          "\(file) must tag that line slack-window")
        }
        // …and above the strip, which is the half of #55 that was visible.
        let online = try repoSource("Slackwater/OnlineGateDetailView.swift")
        let readout = try XCTUnwrap(online.range(of: "readout(window)"))
        let strip = try XCTUnwrap(online.range(of: "TimelineScrubStrip("))
        XCTAssertLessThan(readout.lowerBound, strip.lowerBound,
                          "the readout goes above the strip, same as CurrentDetailView")
    }
}
