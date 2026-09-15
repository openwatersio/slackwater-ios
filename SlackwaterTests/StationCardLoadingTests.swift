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
    func testAutomaticQueueStatesShowTheirProgress() {
        XCTAssertGreaterThan(statusSize(.downloading, detail: "19 of 31 to go").width, 80)
        XCTAssertGreaterThan(statusSize(.queued, detail: "4th in line").width, 60)
    }

    func testQueueCardCopyUsesProgressPositionAndRetryTime() {
        var downloading = job(status: .downloading)
        downloading.done = 12
        downloading.total = 31
        XCTAssertEqual(cardDownloadLabel(downloading, position: 1, at: t0), "19 of 31 to go")

        XCTAssertEqual(cardDownloadLabel(job(), position: 4, at: t0), "4th in line")
        XCTAssertEqual(cardDownloadLabel(job(), position: 1, at: t0), "Next")

        var retrying = job()
        retrying.retryAfter = t0.addingTimeInterval(60)
        XCTAssertEqual(cardDownloadLabel(retrying, position: 2, at: t0), "Retrying in 1 min")
        retrying.retryAfter = t0
        XCTAssertEqual(cardDownloadLabel(retrying, position: 2, at: t0), "Retrying")
    }

    func testOfflineCardsNameWhyTheyNeedSignal() {
        XCTAssertEqual(onlineGateStatus(nil, online: false), .notDownloaded)
        XCTAssertEqual(onlineGateStatus(window(), online: false), .expired)
        XCTAssertEqual(onlineGateStatus(nil, online: false, state: .failed("gone")), .failed)
        XCTAssertEqual(CardStatus.notDownloaded.label, "Not downloaded")
        XCTAssertEqual(CardStatus.failed.label, "Failed")
    }

    func testOnlineGateWaitingInTheAutomaticQueueShowsItsPosition() {
        XCTAssertEqual(onlineGateStatus(nil, online: true, state: .idle, position: 3), .queued)
        XCTAssertEqual(onlineCardDownloadLabel(state: .idle, position: 3, at: t0), "3rd in line")
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
    private func statusSize(_ status: CardStatus, detail: String? = nil) -> CGSize {
        UIHostingController(rootView: CardStatusStrip(status: status, detail: detail))
            .sizeThatFits(in: CGSize(width: 300, height: 100))
    }

    private func job(status: ChsJobStatus = .pending) -> ChsJob {
        ChsJob(id: "test", name: "Test", region: "BC", isCurrent: false,
               latitude: 48, longitude: -123, fitDays: 60, status: status)
    }

    private func window() -> ChsOnlineWindow {
        ChsOnlineWindow(stationID: "test", iwlsName: "Test", timezone: "UTC",
                        fetchedAt: t0, start: t0, end: t0.addingTimeInterval(86_400),
                        floodDirection: 0, ebbDirection: 180, times: [], speeds: [])
    }

    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    private func lowerHalf(_ image: UIImage) throws -> UIImage {
        let source = try XCTUnwrap(image.cgImage)
        let rect = CGRect(x: 0, y: source.height / 2,
                          width: source.width, height: source.height / 2)
        return UIImage(cgImage: try XCTUnwrap(source.cropping(to: rect)))
    }
}
