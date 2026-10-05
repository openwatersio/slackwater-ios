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
        try JSONEncoder().encode(model()).write(to: dir.appendingPathComponent(ChsModelStore.url("chs-victoria").lastPathComponent))
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
        let bytes = try JSONEncoder().encode(["chs-victoria": JSONEncoder().encode(model())])
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
        let lock = NSLock()
        var lateReply: ((Data?) -> Void)?
        let bytes = try! JSONEncoder().encode(["chs-victoria": JSONEncoder().encode(model())])
        let transfer = ChsModelTransfer(send: { _, reply in
            lock.withLock { lateReply = reply }
            started.fulfill()
        }, timeout: 1)
        let task = Task { try await transfer.model(for: ChsModelRequest(stationID: "chs-victoria", isCurrent: false)) }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("An inactive watch must stop waiting for the phone")
        } catch { XCTAssertTrue(error is CancellationError) }
        // Release the callback only once cancellation has finished the waiter.
        lock.withLock { lateReply }?(bytes)
    }

    func testOnlyFirstReplyIsAccepted() async throws {
        let bytes = try JSONEncoder().encode(["chs-victoria": JSONEncoder().encode(model())])
        let transfer = ChsModelTransfer(send: { _, reply in
            reply(nil)
            reply(bytes)
        }, timeout: 0.01)
        let received = try await transfer.model(for: ChsModelRequest(stationID: "chs-victoria", isCurrent: false))
        XCTAssertNil(received)
    }
    func testBatchRequestsOnceAndRemembersMissingModelsUntilReset() async throws {
        let victoria = ChsModelRequest(stationID: "chs-victoria", isCurrent: false)
        let oakBay = ChsModelRequest(stationID: "chs-oak-bay", isCurrent: false)
        var requests: [[ChsModelRequest]] = []
        let bytes = try JSONEncoder().encode(["chs-victoria": JSONEncoder().encode(model())])
        let transfer = ChsModelTransfer(send: { data, reply in
            requests.append(try! JSONDecoder().decode(ChsModelBatch.self, from: data).requests)
            reply(bytes)
        }, timeout: 0.1)
        let received = try await transfer.models(for: [victoria, oakBay])
        XCTAssertNotNil(received[victoria.stationID])
        XCTAssertNil(received[oakBay.stationID])
        XCTAssertEqual(requests, [[victoria, oakBay]])
        _ = try await transfer.models(for: [oakBay])
        XCTAssertEqual(requests.count, 1)
        transfer.resetAvailability()
        _ = try await transfer.models(for: [oakBay])
        XCTAssertEqual(requests.count, 2)
    }

    func testLateJobChecksPhoneAfterInitialBatch() async throws {
        let victoria = ChsModelRequest(stationID: "chs-victoria", isCurrent: false)
        let oakBay = ChsModelRequest(stationID: "chs-oak-bay", isCurrent: false)
        var requests: [[ChsModelRequest]] = []
        let bytes = try JSONEncoder().encode([
            "chs-victoria": JSONEncoder().encode(model()),
            "chs-oak-bay": JSONEncoder().encode(model("chs-oak-bay"))])
        let transfer = ChsModelTransfer(send: { data, reply in
            requests.append(try! JSONDecoder().decode(ChsModelBatch.self, from: data).requests)
            reply(bytes)
        }, timeout: 0.1)
        _ = try await transfer.models(for: [victoria])
        let late = try await transfer.models(for: [oakBay])
        XCTAssertNotNil(late[oakBay.stationID])
        XCTAssertEqual(requests, [[victoria], [oakBay]])
    }

    func testWaitsForColdLaunchReachability() async throws {
        let started = Date.now
        let bytes = try JSONEncoder().encode(["chs-victoria": JSONEncoder().encode(model())])
        var sent = false
        let transfer = ChsModelTransfer(send: { _, reply in
            sent = true
            reply(bytes)
        }, timeout: 0.1, ready: { Date.now.timeIntervalSince(started) >= 0.2 })
        let received = try await transfer.model(for: ChsModelRequest(stationID: "chs-victoria", isCurrent: false))
        XCTAssertTrue(sent)
        XCTAssertNotNil(received)
    }

    func testUnresponsivePhoneIsNotQueriedAgainForNextJob() async throws {
        var sends = 0
        let transfer = ChsModelTransfer(send: { _, _ in sends += 1 }, timeout: 0.01)
        _ = try await transfer.models(for: [ChsModelRequest(stationID: "chs-victoria", isCurrent: false)])
        _ = try await transfer.models(for: [ChsModelRequest(stationID: "chs-oak-bay", isCurrent: false)])
        XCTAssertEqual(sends, 1)
    }

    func testBatchPhoneReplyUsesStoreAndFiltersInvalidModels() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let victoria = ChsModelRequest(stationID: "chs-victoria", isCurrent: false)
        let dodd = ChsModelRequest(stationID: "chs-dodd-narrows", isCurrent: true)
        try JSONEncoder().encode(model()).write(to: dir.appendingPathComponent(ChsModelStore.url(victoria.stationID).lastPathComponent))
        try JSONEncoder().encode(model(dodd.stationID, days: 60)).write(to: dir.appendingPathComponent(ChsModelStore.url(dodd.stationID, suffix: "-current").lastPathComponent))
        let batch = ChsModelBatch(requests: [victoria, dodd])
        let replies = try JSONDecoder().decode([String: Data].self, from: batch.reply(from: dir))
        XCTAssertNotNil(replies[victoria.stationID].flatMap(victoria.decode))
        XCTAssertNil(replies[dodd.stationID])
        XCTAssertLessThanOrEqual(batch.reply(from: dir).count, 60 * 1024)
    }

}
