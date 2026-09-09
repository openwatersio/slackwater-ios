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
    ///    Palette.swift). A formatter that happens to sit a few lines from an
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
    ///      - `CurrentCardView.nextLine(_:)` (StationCard.swift)
    ///      - `scheduleEntries()` in the four detail views, consumed by
    ///        `MultiDaySchedule`'s `Text(e.value ?? "—")` in a FIFTH file
    ///        (TimelineStrip.swift)
    ///      - `WidgetSnapshot.build(_:now:)` (WidgetSnapshot.swift, H2 — the
    ///        allowlist key is `normalize`, not `build`; see the comment on
    ///        that entry below): the formatted height/speed lands in
    ///        `Event.label`, a plain `String` the widget/lock-screen views
    ///        consume as `Text(next.label)` in a SIXTH and SEVENTH file
    ///        (HomeWidgets.swift, AccessoryWidgets.swift) — all four
    ///        consuming sites carry `.monospacedDigit()` themselves,
    ///        verified by hand rather than by this scan.
    ///    (`TimelineStrip.compactTime(_:)` was a sixth until the NEAPS pass
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
            // The card curve: the builders format extreme/axis strings whose
            // one renderer (the Canvas draw code) applies the mono trait.
            "StationCardGraph.swift:cardGraph",
            // previewGraph and the #Preview cards feed that same renderer
            // with synthetic data. The #Preview label closures resolve here
            // too: a `#Preview {` line is no declaration, so the walk climbs
            // to the nearest one above it — previewGraph.
            "StationCard.swift:previewGraph",
            "TideDetailView.swift:scheduleEntries",
            // The summary tile's number: a tide's range and a current's next
            // max are formatted where they are known and consumed by
            // `SummaryTiles`' `Text(primary.value)`, which carries the mono
            // trait (Theme.swift).
            "TideDetailView.swift:range",
            "CurrentLead.swift:nextMax",
            // The fast tide's rate, consumed by `Commentary`'s Text, which
            // carries the mono trait (Theme.swift).
            "TideDetailView.swift:tideRateCommentary",
            "CurrentDetailView.swift:scheduleEntries",
            "CurrentDetailView.swift:body",
            "OnlineGateDetailView.swift:body",
            "TideDetailView.swift:body",
            "DerivedGateDetailView.swift:scheduleEntries",
            // Both tracks format their reading where it is known and hand
            // the string to `CurveDrawing.hangLabel`, whose one `Text`
            // applies the mono trait (CurveDrawing.swift). The card's
            // canvas does the same through its `cardGraph` builders above.
            "TimelineStrip.swift:drawTide",
            "TimelineStrip.swift:drawCurrent",
            // The heuristic's blind spot in miniature: these three calls live
            // in `build(_:now:)`, but `enclosingDeclaration` walks upward to
            // the nearest brace-opening `func`/`var` line by TEXT, not real
            // nesting — and `build` declares a local `func normalize(...)`
            // earlier in its own body, which is textually closer than
            // `build`'s own declaration line. The scanner reports
            // "normalize", not "build"; the key below has to match what it
            // actually computes, not what a real parser would say.
            "WidgetSnapshot.swift:normalize",
        ]
        // Numeric speech is not rendered as Text, so typography cannot apply.
        let knownNonVisual: Set<String> = ["TideShortcuts.swift:spoken"]
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
                // Skip the formatters' own `func` definitions (Units.swift /
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
                // (#93 replaced StationCard's `message:` prose slot with a
                // `status:` enum, so no call site spells `message:` today. The
                // guard stays as a tripwire: the exemption below is what would
                // wave a future prose slot through, and it costs one `contains`.)
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
                // call — `StationListView.swift`'s `} detail: {` (NavigationSplitView's
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
                   knownIndirections.contains("\(name):\(owner)")
                    || knownNonVisual.contains("\(name):\(owner)") { continue }
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

    /// The wordmark's minimumScaleFactor is load-bearing: it shares the 320pt
    /// iPad sidebar row with two 34pt buttons and would break as "Slackwat/er".
    /// Every other name wraps instead of shrinking. This fails in both
    /// directions — a blanket removal, or a fresh one creeping back in.
    ///
    /// **This is a SOURCE-TEXT scan, and it once counted a comment.** The
    /// world-coverage branch fixed a mid-word break on the My Location hero
    /// card with `allowsTightening` and wrote, correctly, `// NOT
    /// minimumScaleFactor: testOnlyTheWordmarkShrinks allows exactly one …`
    /// beside it. That comment — documenting the modifier's *absence* — was
    /// counted as a second site and turned this test red on a file containing
    /// no such modifier. The only fixes on offer were "delete the comment that
    /// explains the rule" and "make the scan read code". Comment text is now
    /// stripped (`codeOnly`), so prose may name the token and a real
    /// `.minimumScaleFactor(…)` outside the wordmark still fails. Both
    /// directions were re-proven red before this note was written.
    func testOnlyTheWordmarkShrinks() throws {
        var sites: [String] = []
        for (name, source) in try appSources() {
            for (n, line) in source.components(separatedBy: .newlines).enumerated()
            where codeOnly(line).contains("minimumScaleFactor") {
                sites.append("\(name):\(n + 1)")
            }
        }
        XCTAssertEqual(sites.count, 1,
                       "exactly one minimumScaleFactor should remain (the wordmark), found: \(sites)")
        // `.first`, not `[0]`: the doc above promises this fails on a blanket
        // removal, and on an empty `sites` the subscript CRASHED the whole
        // test bundle instead — a fail, but the kind that takes the run's
        // other results with it.
        XCTAssertTrue(sites.first?.hasPrefix("StationListView.swift:") == true,
                      "the survivor must be the wordmark, found \(sites)")
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
    /// This used to have a glyph half, asserting `StationCard` gave the kind
    /// mark a scaled `glyphSize`. The mark is gone from every row, and
    /// `StationGlyph` is a caseless enum now, so "no card draws one" is a
    /// compile error rather than something a source scan has to police. A
    /// grep that cannot fail is the theatre the note below is about.
    ///
    /// What remains was theatre once too and is written positively now:
    /// `XCTAssertFalse(app.contains("Color.clear.frame(height: 96)"))` banned
    /// one retired literal — `height: 100` sailed straight through. A ban on
    /// one string is not a guarantee about the surviving code.
    func testFabClearanceScales() throws {
        let appLines = try repoSource("Slackwater/StationListView.swift")
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
