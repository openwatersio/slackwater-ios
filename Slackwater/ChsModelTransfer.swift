// Slackwater — GPL v3. Private fitted-model reuse between the user's paired devices.
import Foundation
import WatchConnectivity

struct ChsModelRequest: Codable {
    let stationID: String
    let isCurrent: Bool

    func decode(_ data: Data) -> ChsModel? {
        guard let model = try? JSONDecoder().decode(ChsModel.self, from: data),
              model.schemaVersion == 1, model.stationID == stationID,
              model.offset.isFinite, model.rms.isFinite, !model.constituents.isEmpty,
              model.constituents.allSatisfy({ $0.amplitude.isFinite && $0.phase.isFinite }) else { return nil }
        if isCurrent {
            guard let gate = ChsCurrentGateInfo.all.first(where: { $0.id == stationID }),
                  !gate.isOnline, !gate.isProvisional(model) else { return nil }
        } else {
            guard ChsStationInfo.all.contains(where: { $0.id == stationID }) else { return nil }
        }
        return model
    }

    func reply(from directory: URL = ChsModelStore.dir) -> Data {
        // Resolve only bundled identities before constructing a file path.
        let known = isCurrent
            ? ChsCurrentGateInfo.all.contains { $0.id == stationID && !$0.isOnline }
            : ChsStationInfo.all.contains { $0.id == stationID }
        guard known else { return Data() }
        let name = stationID + (isCurrent ? "-current" : "") + ".json"
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
              data.count <= 60 * 1024, decode(data) != nil else { return Data() }
        return data
    }
}

final class ChsModelTransfer: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = ChsModelTransfer()
    private let session: WCSession?
    private let send: ((Data, @escaping (Data?) -> Void) -> Void)?
    private let timeout: TimeInterval

    private override init() {
        send = nil
        timeout = 5
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || networkKillSwitch || IwlsFetcher.usesFixture
        session = !testing && WCSession.isSupported() ? WCSession.default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    init(send: @escaping (Data, @escaping (Data?) -> Void) -> Void, timeout: TimeInterval) {
        self.send = send
        self.timeout = timeout
        session = nil
        super.init()
    }

    func model(for request: ChsModelRequest) async throws -> ChsModel? {
        try Task.checkCancellation()
        if send == nil {
            guard let session else { return nil }
            // Cold launches can reach the queue before session activation finishes.
            for _ in 0..<20 where session.activationState != .activated {
                try await Task.sleep(for: .milliseconds(100))
            }
            guard session.activationState == .activated, session.isReachable else { return nil }
        }
        let data = try JSONEncoder().encode(request)
        let reply = PendingModelReply()
        let response: Data? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                reply.start(continuation)
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { reply.finish(nil) }
                if let send {
                    send(data) { reply.finish($0) }
                } else {
                    session?.sendMessageData(data, replyHandler: { reply.finish($0) },
                                             errorHandler: { _ in reply.finish(nil) })
                }
            }
        } onCancel: {
            reply.finish(nil)
        }
        try Task.checkCancellation()
        return response.flatMap(request.decode)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}

    func session(_ session: WCSession, didReceiveMessageData messageData: Data,
                 replyHandler: @escaping (Data) -> Void) {
        #if os(iOS)
        let request = try? JSONDecoder().decode(ChsModelRequest.self, from: messageData)
        replyHandler(request?.reply() ?? Data())
        #else
        replyHandler(Data())
        #endif
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}

/// Replies, timeout, and scene cancellation can race; resume the waiter once.
private final class PendingModelReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?
    private var finished = false

    func start(_ continuation: CheckedContinuation<Data?, Never>) {
        lock.lock()
        if finished {
            lock.unlock()
            continuation.resume(returning: nil)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func finish(_ data: Data?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: data)
    }
}
