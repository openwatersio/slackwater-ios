// Slackwater — GPL v3. Pending station cards keep the loaded card's footprint
// while their data arrives (#263).
import SwiftUI
import UIKit
import XCTest
@testable import Slackwater

final class StationCardLoadingTests: XCTestCase {
    @MainActor
    func testPendingCardsKeepTheCurveCardHeight() throws {
        for status in [CardStatus.downloading, .queued, .notDownloaded] {
            let image = try card(status)
            XCTAssertEqual(image.size.height, 168, "\(status) collapsed below a loaded card")
        }
    }

    @MainActor
    func testPendingCardsDrawInTheLowerGraphBand() throws {
        let blank = inkFraction(try lowerHalf(try card(.offline, minHeight: 168)))

        for status in [CardStatus.downloading, .queued, .notDownloaded] {
            let pending = inkFraction(try lowerHalf(try card(status, minHeight: 168)))
            XCTAssertGreaterThan(pending, blank + 0.01,
                                 "\(status)'s graph band is blank: \(pending) vs \(blank)")
        }
    }

    @MainActor
    func testActiveQueueStatesShowOnlyTheirIcons() {
        let reference = statusSize(.notDownloaded).width

        XCTAssertLessThan(statusSize(.downloading).width, reference * 0.3)
        XCTAssertLessThan(statusSize(.queued).width, reference * 0.3)
        XCTAssertGreaterThan(reference, 60, "Tap to download should remain visible")
    }

    @MainActor
    private func card(_ status: CardStatus, minHeight: CGFloat? = nil) throws -> UIImage {
        let renderer = ImageRenderer(content:
            StationCard(name: "Victoria Harbour", region: "British Columbia",
                        status: status, minHeight: minHeight) { EmptyView() }
                .frame(width: 364)
                .background(SN.canvas))
        return try XCTUnwrap(renderer.uiImage)
    }

    @MainActor
    private func statusSize(_ status: CardStatus) -> CGSize {
        UIHostingController(rootView: CardStatusStrip(status: status))
            .sizeThatFits(in: CGSize(width: 300, height: 100))
    }

    private func lowerHalf(_ image: UIImage) throws -> UIImage {
        let source = try XCTUnwrap(image.cgImage)
        let rect = CGRect(x: 0, y: source.height / 2,
                          width: source.width, height: source.height / 2)
        return UIImage(cgImage: try XCTUnwrap(source.cropping(to: rect)))
    }
}
