import XCTest
import SwiftUI
import WidgetKit
@testable import Slackwater

final class AccessoryWidgetTests: XCTestCase {
    @MainActor
    func testLockedAndLoadingAccessoriesRenderTheTideIcon() throws {
        for placeholder in [false, true] {
            let entry = SlackwaterEntry(date: .distantPast, snapshot: nil, card: nil,
                                        premium: placeholder, stationID: nil, isPlaceholder: placeholder)
            for family in [WidgetFamily.accessoryInline, .accessoryCircular, .accessoryRectangular] {
                let renderer = ImageRenderer(content: AccessoryWidgetView(entry: entry, family: family)
                    .frame(width: 76, height: 76)
                    .environment(\.colorScheme, .dark)
                    .redacted(reason: placeholder ? .placeholder : []))
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertGreaterThan(try ink(in: image, rows: 20..<56), 20)
                let attachment = XCTAttachment(image: image)
                attachment.name = "accessory-\(family)-\(placeholder ? "loading" : "locked")"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    @MainActor
    func testSubscriberWithoutDataIsToldToOpenTheApp() throws {
        func ink(premium: Bool, _ family: WidgetFamily) throws -> Int {
            let entry = SlackwaterEntry(date: .distantPast, snapshot: nil, card: nil,
                                        premium: premium, stationID: nil)
            let renderer = ImageRenderer(content: AccessoryWidgetView(entry: entry, family: family)
                .frame(width: 160, height: 76)
                .environment(\.colorScheme, .dark))
            return try self.ink(in: try XCTUnwrap(renderer.uiImage), rows: 20..<56)
        }
        // The prompt is words, wider than the locked state's lone icon.
        for family in [WidgetFamily.accessoryInline, .accessoryRectangular] {
            XCTAssertGreaterThan(try ink(premium: true, family), 2 * (try ink(premium: false, family)),
                                 "\(family) must say to open the app, not draw the locked icon")
        }
    }

    @MainActor
    func testAccessoryCurvesRenderAtLockScreenSizes() throws {
        let now = Date(timeIntervalSince1970: 1_755_800_000)
        let tide = try XCTUnwrap(WidgetStationLoader.loadRecord(id: TideStationRecord.fridayHarborID))
        let current = try XCTUnwrap(WidgetStationLoader.loadRecord(id: "current:" + CurrentStationRecord.all.first!.id))
        let gate = try XCTUnwrap(ChsGateInfo.all.first)
        let port = try XCTUnwrap(ChsStationInfo.all.first { $0.id == gate.reference })
        let model = ChsModel(stationID: port.id, iwlsID: "test", iwlsName: port.name,
                             fittedAt: now, fitStartMs: 0, fitEndMs: 1, offset: 1, rms: 0,
                             constituents: [.init(name: "M2", amplitude: 1, phase: 0)])
        let derived = WidgetRecord.derived(DerivedGateRecord(gate: gate, port: port.record(with: model)))

        for (record, kind) in [(tide, "tide"), (current, "current"), (derived, "gate")] {
            let snapshot = WidgetSnapshot.build(WidgetStationLoader.station(from: record), now: now)
            let graph = record.accessoryGraph(at: now)
            XCTAssertLessThan(try XCTUnwrap(graph.points.first).time, now)
            XCTAssertGreaterThan(try XCTUnwrap(graph.points.last).time, try XCTUnwrap(snapshot.next).time)
            if snapshot.curveKind == .tide {
                let next = try XCTUnwrap(snapshot.next)
                let curveTurn = try XCTUnwrap(graph.extremes.first { $0.time > now })
                XCTAssertEqual(next.time.timeIntervalSince(curveTurn.time), 0, accuracy: 60,
                               "the next-event header and curve turn describe the same tide")
            }
            for locale in ["en", "fr-CA", "es-ES"] {
                let circle = ImageRenderer(content: AccessoryCircularContent(snapshot: snapshot, graph: graph)
                    .frame(width: 76, height: 76).environment(\.locale, Locale(identifier: locale))
                    .environment(\.colorScheme, .dark))
                let rectangle = ImageRenderer(content: AccessoryRectangularContent(snapshot: snapshot, graph: graph)
                    .frame(width: 160, height: 72).environment(\.locale, Locale(identifier: locale))
                    .environment(\.colorScheme, .dark))
                let circularImage = try XCTUnwrap(circle.uiImage)
                let rectangularImage = try XCTUnwrap(rectangle.uiImage)
                XCTAssertGreaterThan(try ink(in: circularImage, rows: 8..<40), 25,
                                     "the circle must draw a curve above its event time")
                XCTAssertGreaterThan(try ink(in: rectangularImage, rows: 25..<60), 50,
                                     "the rectangle must draw a curve below its heading")
                for (image, shape) in [(circularImage, "circular"), (rectangularImage, "rectangular")] {
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "accessory-\(shape)-\(kind)-\(locale)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    private func ink(in image: UIImage, rows: Range<Int>) throws -> Int {
        let cg = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        CIContext().render(CIImage(cgImage: cg), toBitmap: &pixels,
                           rowBytes: cg.width * 4,
                           bounds: CGRect(x: 0, y: 0, width: cg.width, height: cg.height),
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return rows.reduce(0) { count, row in
            count + (0..<cg.width).filter { pixels[(row * cg.width + $0) * 4 + 3] > 32 }.count
        }
    }
}
