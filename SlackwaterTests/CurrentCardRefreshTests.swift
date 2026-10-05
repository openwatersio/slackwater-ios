import SwiftUI
import UIKit
import XCTest
@testable import Slackwater

final class CurrentCardRefreshTests: XCTestCase {
    @MainActor
    func testMountedCurrentCardsExpandTheirWindowWhenThresholdChanges() async throws {
        let defaults = AppGroup.defaults
        let key = AppGroup.slackWindowSpeedKey
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        let record = CurrentStationRecord(
            id: "noaa/refresh-test", name: "Test current", region: "Test", aliases: [],
            latitude: 48, longitude: -123, timezone: "UTC",
            floodDirection: 90, ebbDirection: 270, meanFlow: 0, tideReference: nil,
            constituents: [.init(name: "M2", amplitude: 2, phase: 0)])

        for eager in [false, true] {
            defaults.set(0.1, forKey: key)
            let host = UIHostingController(rootView:
                CurrentCardView(record: record, eager: eager)
                    .frame(width: 364, height: 168)
                    .background(SN.canvas))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 364, height: 168))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            let narrowImage = snapshot(host.view)
            let narrow = try greenPixels(narrowImage)

            defaults.set(10.0, forKey: key)
            try await Task.sleep(for: .milliseconds(300))
            host.view.layoutIfNeeded()
            let wide = try greenPixels(snapshot(host.view))
            XCTAssertGreaterThan(wide, narrow * 2,
                                 "The mounted \(eager ? "eager" : "lazy") card kept its old slack window")
            let reopened = ImageRenderer(content:
                CurrentCardView(record: record, eager: true)
                    .frame(width: 364, height: 168)
                    .background(SN.canvas))
            reopened.scale = narrowImage.scale
            XCTAssertGreaterThan(try greenPixels(XCTUnwrap(reopened.uiImage)), narrow * 2,
                                 "Reopening the preview reused the old cached window")
        }
    }

    @MainActor
    func testMountedOnlineCardExpandsItsWindowWhenThresholdChanges() async throws {
        let defaults = AppGroup.defaults
        let key = AppGroup.slackWindowSpeedKey
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        let gate = try XCTUnwrap(ChsCurrentGateInfo.all.first { $0.isOnline })
        let now = appNow()
        let offsets = stride(from: -12.0 * 3600, through: 16 * 3600, by: 600).map { $0 }
        let model = ChsOnlineWindow(
            stationID: gate.id, iwlsName: gate.name, timezone: "UTC", fetchedAt: now,
            start: now.addingTimeInterval(offsets.first!), end: now.addingTimeInterval(offsets.last!),
            floodDirection: 90, ebbDirection: 270,
            times: offsets.map { now.timeIntervalSince1970 + $0 },
            speeds: offsets.map { 2 * sin($0 / (6.21 * 3600) * .pi) })
        defaults.set(0.1, forKey: key)
        let host = UIHostingController(rootView:
            OnlineGateCardView(gate: gate, window: model)
                .frame(width: 364, height: 168)
                .background(SN.canvas))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 364, height: 168))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        let narrow = try greenPixels(snapshot(host.view))

        defaults.set(10.0, forKey: key)
        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutIfNeeded()
        XCTAssertGreaterThan(try greenPixels(snapshot(host.view)), narrow * 2,
                             "The mounted online card kept its old slack window")
    }

    @MainActor
    private func snapshot(_ view: UIView) -> UIImage {
        UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }

    private func greenPixels(_ image: UIImage) throws -> Int {
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes, width: cg.width, height: cg.height, bitsPerComponent: 8,
            bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return stride(from: 0, to: bytes.count, by: 4).filter {
            let r = Int(bytes[$0]), g = Int(bytes[$0 + 1]), b = Int(bytes[$0 + 2])
            return g > r + 15 && r > b + 15
        }.count
    }
}
