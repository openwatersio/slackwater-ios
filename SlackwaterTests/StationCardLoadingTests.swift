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
    func testDownloadProgressFillsTheSkeletonWaveFromTheLeadingEdge() throws {
        let empty = try lowerHalf(try card(.downloading, progress: 0))
        let half = try lowerHalf(try card(.downloading, progress: 5))
        let attachment = XCTAttachment(image: half)
        attachment.name = "station-download-wave-half"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertGreaterThan(differingFraction(try horizontalHalf(empty, leading: true),
                                               try horizontalHalf(half, leading: true)), 0.001)
        XCTAssertLessThan(differingFraction(try horizontalHalf(empty, leading: false),
                                            try horizontalHalf(half, leading: false)), 0.0002)
    }

    @MainActor
    func testAutomaticQueueStatesShowTheirProgress() {
        XCTAssertGreaterThan(statusSize(.downloading, detail: "Downloading").width, 80)
        XCTAssertGreaterThan(statusSize(.queued, detail: "4th in line").width, 60)
    }

    func testQueueCardCopyUsesProgressPositionAndRetryTime() {
        var downloading = job(status: .downloading)
        downloading.done = 12
        downloading.total = 31
        XCTAssertEqual(cardDownloadLabel(downloading, position: 1, at: t0), "Downloading")

        XCTAssertEqual(cardDownloadLabel(job(), position: 4, at: t0), "4th in line")
        XCTAssertEqual(cardDownloadLabel(job(), position: 1, at: t0), "Next")

        var retrying = job()
        retrying.retryAfter = t0.addingTimeInterval(60)
        XCTAssertEqual(cardDownloadLabel(retrying, position: 2, at: t0), "Retrying in 1 min")
        retrying.retryAfter = t0
        XCTAssertEqual(cardDownloadLabel(retrying, position: 2, at: t0), "Retrying")
    }

    func testOfflineOnlineGateDetailsRequireSignal() {
        XCTAssertEqual(onlineGateStatus(nil, online: false), .offline)
        XCTAssertEqual(onlineGateStatus(window(), online: false), .offline)
        XCTAssertEqual(onlineGateStatus(nil, online: false, state: .failed("gone")), .failed)
        XCTAssertEqual(CardStatus.notDownloaded.label, "Not downloaded")
        XCTAssertEqual(CardStatus.failed.label, "Failed")
    }

    func testOnlineGateWaitingInTheAutomaticQueueShowsItsPosition() {
        XCTAssertEqual(onlineGateStatus(nil, online: true, state: .idle, position: 3), .queued)
        XCTAssertEqual(onlineCardDownloadLabel(state: .idle, position: 3, at: t0), "3rd in line")
    }

    @MainActor
    private func card(_ status: CardStatus, minHeight: CGFloat? = nil,
                      progress: Double? = nil) throws -> UIImage {
        let renderer = ImageRenderer(content:
            StationCard(name: "Victoria Harbour", region: "British Columbia",
                        status: status, downloadProgress: progress,
                        minHeight: minHeight) { EmptyView() }
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

    private func horizontalHalf(_ image: UIImage, leading: Bool) throws -> UIImage {
        let source = try XCTUnwrap(image.cgImage)
        let rect = CGRect(x: leading ? 0 : source.width / 2, y: 0,
                          width: source.width / 2, height: source.height)
        return UIImage(cgImage: try XCTUnwrap(source.cropping(to: rect)))
    }
}
