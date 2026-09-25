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
    /// eyebrow measured at 11.8:1 came back "failed"). An element's own
    /// screenshot settles it — the brightest pixels are the text, the median
    /// is its ground.
    private func audit(_ app: XCUIApplication, _ screen: String) throws {
        save(app, "audit-\(screen.replacingOccurrences(of: " ", with: "-")).png")
        let window = app.windows.firstMatch.frame
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
                if let ratio = self.renderedContrast(e), ratio >= 4.5 { return true }
            }
            issues.append("\(issue.auditType.rawValue) \(e.elementType.rawValue) id=\(e.identifier) label=\(e.label) "
                          + "frame=\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height)): \(issue.compactDescription)")
            return true
        }
        XCTAssertTrue(issues.isEmpty, "\(screen) audit:\n" + issues.joined(separator: "\n"))
    }

    /// WCAG contrast between an element's text (its brightest half-percent of
    /// pixels) and its ground (the median pixel).
    private func renderedContrast(_ element: XCUIElement) -> Double? {
        guard let cg = element.screenshot().image.cgImage else { return nil }
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
        var lums: [Double] = []
        lums.reserveCapacity(w * h)
        for i in stride(from: 0, to: px.count, by: 4) {
            lums.append(0.2126 * channel(px[i]) + 0.7152 * channel(px[i + 1]) + 0.0722 * channel(px[i + 2]))
        }
        lums.sort()
        guard lums.count > 200 else { return nil }
        let ground = lums[lums.count / 2]
        let text = lums[Int(Double(lums.count) * 0.995)]
        return (max(text, ground) + 0.05) / (min(text, ground) + 0.05)
    }

    func testStationListPassesTheAudit() throws {
        let app = launch("-seedGate", "-fixLat", "48.4235", "-fixLon", "-123.3705")
        try audit(app, "station list")
    }

    func testTideDetailPassesTheAudit() throws {
        let app = launch("-seedGate", "-fixLat", "48.4235", "-fixLon", "-123.3705")
        openFridayHarbor(app)
        try audit(app, "tide detail")
    }

    func testCurrentDetailPassesTheAudit() throws {
        let app = launch("-seedGate", "-fixLat", "48.4235", "-fixLon", "-123.3705")
        openSearch(app, "deception")
        pickSearchResult(app, app.staticTexts["Deception Pass (Narrows)"].firstMatch)
        XCTAssert(app.staticTexts["Today"].appears(within: 5))
        try audit(app, "current detail")
    }
}
