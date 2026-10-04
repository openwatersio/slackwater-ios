// Slackwater — GPL v3. Reuse a paired phone's fitted model before fetching IWLS.
import XCTest
@testable import Slackwater

final class ChsModelTransferTests: XCTestCase {
    private func model(_ id: String = "chs-victoria", days: Double? = nil) -> ChsModel {
        ChsModel(stationID: id, iwlsID: "test", iwlsName: "Test",
                 fittedAt: Date(timeIntervalSince1970: 100), fitStartMs: 0, fitEndMs: 1,
                 fitDays: days, offset: 1, rms: 0.01,
                 constituents: [Con(name: "M2", amplitude: 1, phase: 0)])
    }

    func testPhoneReturnsStoredTideModel() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try JSONEncoder().encode(model()).write(to: dir.appendingPathComponent("chs-victoria.json"))
        let request = ChsModelRequest(stationID: "chs-victoria", isCurrent: false)
        let received = try XCTUnwrap(request.decode(request.reply(from: dir)))
        XCTAssertEqual(received.stationID, "chs-victoria")
        XCTAssertEqual(received.fittedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(received.constituents.first?.amplitude, 1)
    }

    func testMissingPhoneModelReturnsNoModel() {
        let request = ChsModelRequest(stationID: "chs-victoria", isCurrent: false)
        XCTAssertNil(request.decode(request.reply(from: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))))
    }

    func testRejectsWrongStationAndUnsupportedSchema() throws {
        let request = ChsModelRequest(stationID: "chs-victoria", isCurrent: false)
        XCTAssertNil(request.decode(try JSONEncoder().encode(model("chs-oak-bay"))))
        var future = model()
        future.schemaVersion = 99
        XCTAssertNil(request.decode(try JSONEncoder().encode(future)))
        XCTAssertNil(request.decode(Data("not a model".utf8)))
    }

    func testCurrentRequiresFinalModelAndCorrectSeries() throws {
        let request = ChsModelRequest(stationID: "chs-dodd-narrows", isCurrent: true)
        XCTAssertNil(request.decode(try JSONEncoder().encode(model("chs-dodd-narrows", days: 60))))
        XCTAssertNotNil(request.decode(try JSONEncoder().encode(model("chs-dodd-narrows", days: 210))))
        let wrongSeries = ChsModelRequest(stationID: "chs-dodd-narrows", isCurrent: false)
        XCTAssertNil(wrongSeries.decode(try JSONEncoder().encode(model("chs-dodd-narrows", days: 210))))
    }

    func testTransferUsesPhoneReply() async throws {
        let bytes = try JSONEncoder().encode(model())
        let transfer = ChsModelTransfer(send: { _, reply in reply(bytes) }, timeout: 0.1)
        let received = try await transfer.model(for: ChsModelRequest(stationID: "chs-victoria", isCurrent: false))
        XCTAssertEqual(received?.stationID, "chs-victoria")
    }

    func testUnresponsivePhoneFallsBack() async throws {
        let transfer = ChsModelTransfer(send: { _, _ in }, timeout: 0.01)
        let received = try await transfer.model(for: ChsModelRequest(stationID: "chs-victoria", isCurrent: false))
        XCTAssertNil(received)
    }

    func testCancelledTransferDoesNotImportLateReply() async {
        let started = expectation(description: "Waiting for the phone")
        let lateReply = expectation(description: "Phone reply after cancellation")
        let bytes = try! JSONEncoder().encode(model())
        let transfer = ChsModelTransfer(send: { _, reply in
            started.fulfill()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                reply(bytes)
                lateReply.fulfill()
            }
        }, timeout: 1)
        let task = Task { try await transfer.model(for: ChsModelRequest(stationID: "chs-victoria", isCurrent: false)) }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("An inactive watch must stop waiting for the phone")
        } catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [lateReply], timeout: 1)
    }

    func testOnlyFirstReplyIsAccepted() async throws {
        let bytes = try JSONEncoder().encode(model())
        let transfer = ChsModelTransfer(send: { _, reply in
            reply(nil)
            reply(bytes)
        }, timeout: 0.01)
        let received = try await transfer.model(for: ChsModelRequest(stationID: "chs-victoria", isCurrent: false))
        XCTAssertNil(received)
    }
}
