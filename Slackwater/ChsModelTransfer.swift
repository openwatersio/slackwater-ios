// Slackwater — GPL v3. Private fitted-model reuse between the user's paired devices.
import Foundation
import WatchConnectivity

struct ChsModelRequest: Codable, Hashable {
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
        let name = ChsModelStore.url(stationID, suffix: isCurrent ? "-current" : "").lastPathComponent
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
              data.count <= 60 * 1024, decode(data) != nil else { return Data() }
        return data
    }
}

struct ChsModelBatch: Codable {
    let requests: [ChsModelRequest]
    static let limit = 12

    func reply(from directory: URL = ChsModelStore.dir) -> Data {
        var models: [String: Data] = [:]
        for request in requests.prefix(Self.limit) {
            let data = request.reply(from: directory)
            guard !data.isEmpty else { continue }
            var candidate = models
            candidate[request.stationID] = data
            // Watch Connectivity's message budget includes base64 encoding.
            if let encoded = try? JSONEncoder().encode(candidate), encoded.count <= 60 * 1024 {
                models = candidate
            }
        }
        return (try? JSONEncoder().encode(models)) ?? Data()
    }
}

final class ChsModelTransfer: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = ChsModelTransfer()
    private let session: WCSession?
    private let send: ((Data, @escaping (Data?) -> Void) -> Void)?
    private let timeout: TimeInterval
    private let ready: (() -> Bool)?
    private let cacheLock = NSLock()
    private var missing: Set<ChsModelRequest> = []
    private var unavailableUntil = Date.distantPast

    private override init() {
        send = nil
        ready = nil
        timeout = 5
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || networkKillSwitch || IwlsFetcher.usesFixture
        session = !testing && WCSession.isSupported() ? WCSession.default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    init(send: @escaping (Data, @escaping (Data?) -> Void) -> Void, timeout: TimeInterval,
         ready: @escaping () -> Bool = { true }) {
        self.send = send
        self.ready = ready
        self.timeout = timeout
        session = nil
        super.init()
    }

    func resetAvailability() {
        cacheLock.withLock {
            missing.removeAll()
            unavailableUntil = .distantPast
        }
    }

    func model(for request: ChsModelRequest) async throws -> ChsModel? {
        try await models(for: [request])[request.stationID]
    }

    func models(for requests: [ChsModelRequest]) async throws -> [String: ChsModel] {
        try Task.checkCancellation()
        let pending = cacheLock.withLock {
            Date.now < unavailableUntil ? [] : requests.filter { !missing.contains($0) }
        }
        guard !pending.isEmpty, send != nil || session != nil else { return [:] }
        // Reachability can arrive after activation on a cold launch.
        for _ in 0..<20 {
            if ready?() ?? (session?.activationState == .activated && session?.isReachable == true) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard ready?() ?? (session?.activationState == .activated && session?.isReachable == true) else {
            cacheLock.withLock { unavailableUntil = .now.addingTimeInterval(30) }
            return [:]
        }
        var models: [String: ChsModel] = [:]
        for start in stride(from: 0, to: pending.count, by: ChsModelBatch.limit) {
            try Task.checkCancellation()
            let batch = Array(pending[start..<min(start + ChsModelBatch.limit, pending.count)])
            let response = await exchange(try JSONEncoder().encode(ChsModelBatch(requests: batch)))
            try Task.checkCancellation()
            guard let response, let replies = try? JSONDecoder().decode([String: Data].self, from: response) else {
                cacheLock.withLock { unavailableUntil = .now.addingTimeInterval(30) }
                break
            }
            for request in batch {
                if let data = replies[request.stationID], let model = request.decode(data) {
                    models[request.stationID] = model
                } else {
                    _ = cacheLock.withLock { missing.insert(request) }
                }
            }
        }
        return models
    }

    private func exchange(_ data: Data) async -> Data? {
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
        return response
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}

    func session(_ session: WCSession, didReceiveMessageData messageData: Data,
                 replyHandler: @escaping (Data) -> Void) {
        #if os(iOS)
        let request = try? JSONDecoder().decode(ChsModelBatch.self, from: messageData)
        replyHandler(request?.reply() ?? Data())
        #else
        replyHandler(Data())
        #endif
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { resetAvailability() }
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
