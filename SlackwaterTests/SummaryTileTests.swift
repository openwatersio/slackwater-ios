import SwiftUI
import UIKit
import XCTest
@testable import Slackwater

final class SummaryTileTests: XCTestCase {
    @MainActor
    private func height<Value: View>(@ViewBuilder value: @escaping () -> Value) -> CGFloat {
        let tile = ReadoutTile(label: "Tile", caption: "caption", accessibility: "Tile") {
            EmptyView()
        } value: {
            value()
        }

        return UIHostingController(rootView: tile.frame(width: 180))
            .sizeThatFits(in: CGSize(width: 180, height: 1_000)).height
    }

    @MainActor
    func testTileHugsItsContentVertically() {
        let tileHeight = height {
            Text("0.8 ft").font(ReadoutType.hero)
        }

        XCTAssertLessThan(tileHeight, 100)
    }

    @MainActor
    func testNumericAndTextTilesHaveEqualHeight() {
        let numeric = height { Text("0.8 ft").font(ReadoutType.hero) }
        let text = height { Text("First Quarter").font(ReadoutType.tileText) }

        XCTAssertEqual(text, numeric, accuracy: 0.5)
    }
}
