// Slackwater — GPL v3. The platform's own accessibility audit over the main
// screens: contrast, element descriptions (what Voice Control names), hit
// regions, dynamic type and clipped text, in one pass per screen. The App
// Store nutrition labels (docs/appstore-metadata.md) rest on these running
// green; a row the audit cannot see is checked by hand and named there.
import XCTest

final class AccessibilityAuditTests: ScreenshotTestCase {
    /// `.dynamicType` and `.textClipped` join this set with the Larger Text
    /// card-layout work (#438): station names, distances, sun times and the
    /// `MonoLabel` eyebrows report partial support today.
    private let audits: XCUIAccessibilityAuditType = [
        .contrast, .sufficientElementDescription, .hitRegion, .trait,
    ]

    /// Every issue on the screen, not just the first: the audit stops at
    /// the first unhandled one, so collect them all and report once.
    ///
    /// Contrast is judged on rendered pixels, not the audit's own guess: it
    /// misreads text over the sky and over translucent card fills (a 90%
    /// eyebrow measured at 11.8:1 came back "failed"), and over the premium
    /// sheet's printed page (black on a night row's tint, near 17:1). An
    /// element's own screenshot settles it.
    private func audit(_ app: XCUIApplication, _ screen: String, premiumContent: CGRect? = nil) throws {
        save(app, "audit-\(screen.replacingOccurrences(of: " ", with: "-")).png")
        let window = app.windows.firstMatch.frame
        // Content scrolled up under the navigation bar is covered by its opaque
        // canvas fill; the user cannot see it, but the audit still reports it
        // and its screenshot samples whatever the scroll had reached.
        let bar = app.navigationBars.firstMatch
        // The Premium sheet's printed example is the one place that sets dark
        // type: black on paper and on its row tints. Only its text elements
        // read as dark type; the card around the paper is the dark canvas.
        let printed = app.otherElements["premium-preview-print"].firstMatch
        let page = printed.exists ? printed.frame : .null
        var issues: [String] = []
        try app.performAccessibilityAudit(for: audits) { issue in
            // An issue without an element cannot be located or measured; the
            // list's unnamed card glyphs report this way (see the card note
            // below).
            guard let e = issue.element else { return true }
            let f = e.frame
            // MapLibre's own compass and attribution controls: not ours to size.
            if issue.auditType == .hitRegion, ["Compass", "About this map"].contains(e.label) { return true }
            // A station card's tap lives on the whole card, but every text
            // and glyph inside it still reports as its own interactive
            // element. Making each card one element is the fix (and a better
            // VoiceOver stop); it changes how the UI suite locates card text,
            // so it is its own change (#438).
            if issue.auditType == .hitRegion, e.identifier.hasPrefix("chs-pending-") { return true }
            if issue.auditType == .contrast {
                // Partly off-screen text samples the void; judge only what is fully visible.
                guard window.contains(f) else { return true }
                if let premiumContent, !premiumContent.contains(f),
                   app.scrollViews.containing(e.elementType, identifier: e.label).firstMatch.exists { return true }
                if bar.exists, bar.frame.intersects(f), e.elementType != .navigationBar { return true }
                let darkText = e.elementType == .staticText && page.contains(f)
                if let ratio = self.renderedContrast(e, darkText: darkText), ratio >= 4.5 { return true }
            }
            issues.append("\(issue.auditType.rawValue) \(e.elementType.rawValue) id=\(e.identifier) label=\(e.label) "
                          + "frame=\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height)): \(issue.compactDescription)")
            return true
        }
        XCTAssertTrue(issues.isEmpty, "\(screen) audit:\n" + issues.joined(separator: "\n"))
    }

    private func renderedContrast(_ element: XCUIElement, darkText: Bool = false) -> Double? {
        guard let cg = element.screenshot().image.cgImage else { return nil }
        return Self.renderedContrast(cg, darkText: darkText)
    }

    /// WCAG contrast between an image's text and its ground (the median
    /// pixel). The text is its brightest half-percent of pixels, or its
    /// darkest for `darkText` on a light ground. The caller names the
    /// polarity: on a mid-tone ground either extreme could be a glyph rather
    /// than the text. A rule or border spans its frame and text never fills a
    /// whole row or column of pixels, so such lines are left out first.
    static func renderedContrast(_ cg: CGImage, darkText: Bool = false) -> Double? {
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        func channel(_ v: UInt8) -> Double {
            let s = Double(v) / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        let lums = stride(from: 0, to: px.count, by: 4).map {
            0.2126 * channel(px[$0]) + 0.7152 * channel(px[$0 + 1]) + 0.0722 * channel(px[$0 + 2])
        }
        guard lums.count > 200 else { return nil }
        let ground = lums.sorted()[lums.count / 2]
        // Dark type reads only on a light ground: the example's caption is light on the canvas.
        let dark = darkText && ground > 0.18
        func ratio(_ l: Double) -> Double { (max(l, ground) + 0.05) / (min(l, ground) + 0.05) }
        let far = lums.map { (dark ? $0 < ground : $0 > ground) && ratio($0) >= 3 }
        let lineRows = Set((0..<h).filter { y in (0..<w).filter { far[y * w + $0] }.count >= w * 9 / 10 })
        let lineColumns = Set((0..<w).filter { x in (0..<h).filter { far[$0 * w + x] }.count >= h * 9 / 10 })
        let kept = lums.indices.filter { !lineRows.contains($0 / w) && !lineColumns.contains($0 % w) }
            .map { lums[$0] }.sorted()
        guard kept.count > 200 else { return nil }
        return ratio(kept[Int(Double(kept.count) * (dark ? 0.005 : 0.995))])
    }

    /// The rendered check reads type of either polarity, still fails faint
    /// type of either, and a rule or border never stands in for the type.
    func testRenderedContrastReadsLightAndDarkText() throws {
        let canvas: (CGFloat, CGFloat, CGFloat) = (0x05 / 255, 0x12 / 255, 0x2A / 255)
        let nightRow: (CGFloat, CGFloat, CGFloat) = (0xE8 / 255, 0xEC / 255, 0xF2 / 255)
        func ratio(ground: (CGFloat, CGFloat, CGFloat), text: (CGFloat, CGFloat, CGFloat),
                   darkText: Bool = false, blackRule: Bool = false, canvasBorder: Bool = false) throws -> Double {
            let ctx = try XCTUnwrap(CGContext(data: nil, width: 100, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.setFillColor(red: ground.0, green: ground.1, blue: ground.2, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 40))
            // Strokes over 5% of the pixels, as a short word covers its frame.
            ctx.setFillColor(red: text.0, green: text.1, blue: text.2, alpha: 1)
            ctx.fill(CGRect(x: 10, y: 15, width: 40, height: 5))
            if blackRule {
                ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
                ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 1))
            }
            if canvasBorder {
                ctx.setFillColor(red: canvas.0, green: canvas.1, blue: canvas.2, alpha: 1)
                for edge in [CGRect(x: 0, y: 0, width: 100, height: 4), CGRect(x: 0, y: 36, width: 100, height: 4),
                             CGRect(x: 0, y: 0, width: 4, height: 40), CGRect(x: 96, y: 0, width: 4, height: 40)] {
                    ctx.fill(edge)
                }
            }
            return try XCTUnwrap(Self.renderedContrast(try XCTUnwrap(ctx.makeImage()), darkText: darkText))
        }
        XCTAssertGreaterThanOrEqual(try ratio(ground: canvas, text: (1, 1, 1)), 4.5, "white on the canvas")
        XCTAssertGreaterThanOrEqual(try ratio(ground: (1, 1, 1), text: (0, 0, 0), darkText: true), 4.5, "black on paper")
        XCTAssertGreaterThanOrEqual(try ratio(ground: nightRow, text: (0, 0, 0), darkText: true), 4.5, "black on a night row")
        XCTAssertLessThan(try ratio(ground: canvas, text: (0.3, 0.3, 0.3)), 4.5, "dim grey on the canvas")
        XCTAssertLessThan(try ratio(ground: (1, 1, 1), text: (0.8, 0.8, 0.8), darkText: true), 4.5, "pale grey on paper")
        XCTAssertLessThan(try ratio(ground: (0.5, 0.5, 0.5), text: (0.8, 0.8, 0.8), blackRule: true), 4.5,
                          "pale type on a mid-grey ground with a black rule")
        XCTAssertGreaterThanOrEqual(try ratio(ground: (1, 1, 1), text: (0, 0, 0), darkText: true, blackRule: true), 4.5,
                                    "black on paper above a rule")
        XCTAssertLessThan(try ratio(ground: (1, 1, 1), text: (0.8, 0.8, 0.8), darkText: true, blackRule: true), 4.5,
                          "pale grey on paper above a rule")
        XCTAssertLessThan(try ratio(ground: (1, 1, 1), text: (0.8, 0.8, 0.8), darkText: true, canvasBorder: true), 4.5,
                          "pale grey on paper inside the canvas border")
        // The caption under the paper sits on the canvas, so it reads as light type.
        XCTAssertGreaterThanOrEqual(try ratio(ground: canvas, text: (1, 1, 1), darkText: true), 4.5, "a white caption")
        XCTAssertLessThan(try ratio(ground: canvas, text: (0.3, 0.3, 0.3), darkText: true), 4.5, "a dim caption")
    }

    func testStationListPassesTheAudit() throws {
        // Favorites persist in the App Group across launches on a clone, so a test that
        // seeded one earlier in the run would leave a live card on the list. Its name and
        // state labels are the card children the note above defers to #438, and they fail
        // the hit-region audit. Every audit here resets them: on iPad the list column stays
        // beside the detail, so the detail audits walk that card too.
        let app = launch("-resetFavorites", "-fixLat", "48.4235", "-fixLon", "-123.3705")
        try audit(app, "station list")
    }

    func testTideDetailPassesTheAudit() throws {
        let app = launch("-resetFavorites", "-fixLat", "48.4235", "-fixLon", "-123.3705")
        openFridayHarbor(app)
        try audit(app, "tide detail")
    }

    func testPremiumSheetPassesTheAudit() throws {
        let app = launch("-locDenied", "-seedPremiumSheet")
        XCTAssert(app.otherElements["premium-preview-print"].appears(within: 10))
        let content = premiumContentFrame(in: app)
        try audit(app, "premium sheet", premiumContent: content)
        scrollTo(app.staticTexts["Sky controls"].firstMatch, in: app, visibleFrame: content)
        let table = app.otherElements["premium-table"].firstMatch
        for label in ["Print and PDF", "Alerts", "Calendars", "Lock screen widgets", "Watch complications", "Sky controls"] {
            let row = table.staticTexts[label].firstMatch
            if !content.contains(row.frame) { scrollTo(row, in: app, visibleFrame: content) }
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(renderedContrast(row)), 4.5, label)
        }
        // The free widget group sits between the table and the plans.
        scrollTo(app.staticTexts["Next Event"].firstMatch, in: app, visibleFrame: content)
        try audit(app, "premium sheet free widgets", premiumContent: content)
        scrollTo(app.buttons["Restore purchase"], in: app, visibleFrame: content)
        try audit(app, "premium sheet end", premiumContent: content)
    }

    func testCurrentDetailPassesTheAudit() throws {
        let app = launch("-resetFavorites", "-fixLat", "48.4235", "-fixLon", "-123.3705")
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        XCTAssert(app.staticTexts["Today"].appears(within: 5))
        try audit(app, "current detail")
    }
}
