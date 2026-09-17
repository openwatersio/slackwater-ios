import SwiftUI
import UIKit
import XCTest
@testable import Slackwater

final class SummaryTileTests: XCTestCase {
    @MainActor
    func testTileHugsItsContentVertically() {
        let tile = ReadoutTile(label: "Range", caption: "low to high", accessibility: "Range") {
            EmptyView()
        } value: {
            Text("0.8 ft").font(ReadoutType.hero)
        }

        let size = UIHostingController(rootView: tile.frame(width: 180))
            .sizeThatFits(in: CGSize(width: 180, height: 1_000))

        XCTAssertLessThan(size.height, 100)
    }
}
