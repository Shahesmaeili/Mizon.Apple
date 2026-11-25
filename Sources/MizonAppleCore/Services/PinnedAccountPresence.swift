#if os(macOS) || os(iOS) || os(watchOS)
import Foundation
import MizonAPI

/// SignalR's default transport creates its own URLSession. A pinned development
/// origin uses the app's session for the two account-presence hub methods.
actor PinnedAccountPresence: AccountPresenceTransport {
    private enum Failure: Error {
        case disconnected, invalidMessage, invocationRejected, timedOut
    }

    private enum Presence: Decodable, Sendable {
        case window(ClientWindowPresenceResponse)
        case account(ClientAccountPresenceResponse)

        init(from decoder: any Decoder) throws {
            if let window = try? ClientWindowPresenceResponse(from: decoder) {
                self = .window(window)
            } else {
                self = .account(try ClientAccountPresenceResponse(from: decoder))
            }
        }
    }

    private struct Frame: Decodable {
        let type: Int?
        let invocationId: String?
        let error: String?
        let result: Presence?
        let target: String?
        let arguments: [ClientAccountPresenceResponse]?

        private enum CodingKeys: CodingKey { case type, invocationId, error, result, target, arguments }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decodeIfPresent(Int.self, forKey: .type)
            invocationId = try container.decodeIfPresent(String.self, forKey: .invocationId)
            error = try container.decodeIfPresent(String.self, forKey: .error)
            result = try? container.decode(Presence.self, forKey: .result)
            target = try container.decodeIfPresent(String.self, forKey: .target)
            arguments = target?.lowercased() == "accountpresencechanged"
                ? try container.decodeIfPresent([ClientAccountPresenceResponse].self, forKey: .arguments) : nil
        }
    }

    private struct Invocation<Arguments: Encodable>: Encodable {
        let type = 1
        let invocationId: String
        let target: String
        let arguments: Arguments
    }

    private struct WindowArguments: Encodable {
        let active: Bool
        let revision: Int64

        func encode(to encoder: any Encoder) throws {
            var values = encoder.unkeyedContainer()
            try values.encode(active)
            try values.encode(revision)
        }
    }

    private struct Pending {
        let continuation: CheckedContinuation<Frame, any Error>
        let timeout: Task<Void, Never>
    }

    private static let separator: Character = "\u{001e}"
    private let hub: URL
    private let clientID: UUID
    private let api: MizonApi
    private let network: URLSession
    private let updates = AsyncStream<MizonSocketEvent>.makeStream(bufferingPolicy: .bufferingNewest(32))
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var pending: [String: Pending] = [:]
    private var lastResponse = ContinuousClock.now
    private var revision: Int64 = 0
    private var disposed = false
    private(set) var windowPresence: ClientWindowPresenceResponse?

    init(hub: URL, clientID: UUID, api: MizonApi, network: URLSession) {
        self.hub = hub
        self.clientID = clientID
        self.api = api
        self.network = network
        updates.continuation.yield(.stateChanged(.disconnected))
    }

    func events() -> AsyncStream<MizonSocketEvent> { updates.stream }

    func start() async throws {
        guard !disposed, socket == nil else { throw CancellationError() }
        let token = await api.getToken()
        try Task.checkCancellation()
        guard !disposed, socket == nil, let token, MizonSocket.clientPublicId(from: token) == clientID,
              var address = URLComponents(url: hub, resolvingAgainstBaseURL: false), address.scheme == "https" else {
            throw Failure.disconnected
        }
        // Native WebSockets support direct SignalR connections without an HTTP negotiation round-trip.
        address.scheme = "wss"
        guard let url = address.url else { throw Failure.disconnected }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let task = network.webSocketTask(with: request)
        task.maximumMessageSize = 128 * 1024
        socket = task
        updates.continuation.yield(.stateChanged(.connecting))
        task.resume()
        receiveTask = Task { [weak self] in await self?.receive(from: task) }
        do {
            let reply = try await exchange(#"{"protocol":"json","version":1}"#, id: handshakeID(for: task), over: task)
            guard reply.error == nil, socket === task else { throw Failure.invocationRejected }
            lastResponse = .now
            keepAliveTask = Task { [weak self] in await self?.keepAlive(on: task) }
            updates.continuation.yield(.stateChanged(.connected))
        } catch {
            disconnect(task)
            throw error
        }
    }

    func setWindowPresence(isActive: Bool) async throws {
        revision += 1
        let sequence = revision
        windowPresence = nil
        let result = try await invoke("SetWindowPresence", arguments: WindowArguments(active: isActive, revision: sequence))
        try Task.checkCancellation()
        guard case .window(let window) = result, window.clientPublicId == clientID,
              window.revision == revision, window.revision == sequence, window.isOnline == isActive,
              !window.connectionId.isEmpty else { return }
        windowPresence = window
    }

    func watchAccountPresence() async throws -> ClientAccountPresenceResponse {
        guard case .account(let account) = try await invoke("WatchAccountPresence", arguments: [Bool]()),
              account.clientPublicId == clientID, account.revision >= 0 else { throw Failure.invalidMessage }
        return account
    }

    func dispose() {
        disposed = true
        if let socket { disconnect(socket) }
        updates.continuation.finish()
    }

    private func invoke<Arguments: Encodable>(_ target: String, arguments: Arguments) async throws -> Presence {
        guard let socket else { throw Failure.disconnected }
        let id = UUID().uuidString
        let message = try JSONEncoder().encode(Invocation(invocationId: id, target: target, arguments: arguments))
        let reply = try await exchange(String(decoding: message, as: UTF8.self), id: id, over: socket)
        try Task.checkCancellation()
        guard self.socket === socket else { throw Failure.disconnected }
        guard reply.error == nil, let result = reply.result else { throw Failure.invocationRejected }
        return result
    }

    private func exchange(_ message: String, id: String, over task: URLSessionWebSocketTask) async throws -> Frame {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(10)) } catch { return }
                    await self?.resolve(id, with: .failure(Failure.timedOut))
                }
                pending[id] = Pending(continuation: continuation, timeout: timeout)
                Task { [weak self] in
                    do { try await task.send(.string(message + String(Self.separator))) }
                    catch { await self?.disconnect(task) }
                }
            }
        } onCancel: {
            Task { await self.resolve(id, with: .failure(CancellationError())) }
        }
    }

    private func resolve(_ id: String, with result: Result<Frame, any Error>) {
        guard let call = pending.removeValue(forKey: id) else { return }
        call.timeout.cancel()
        call.continuation.resume(with: result)
    }

    private func receive(from task: URLSessionWebSocketTask) async {
        do {
            while socket === task, !Task.isCancelled {
                let message = try await task.receive()
                guard socket === task else { return }
                lastResponse = .now
                let text: String
                switch message {
                case .string(let value): text = value
                case .data(let value): text = String(decoding: value, as: UTF8.self)
                @unknown default: throw Failure.invalidMessage
                }
                guard text.last == Self.separator else { throw Failure.invalidMessage }
                for record in text.split(separator: Self.separator) {
                    let frame = try JSONDecoder().decode(Frame.self, from: Data(record.utf8))
                    switch frame.type {
                    case nil: resolve(handshakeID(for: task), with: .success(frame))
                    case 1:
                        if let account = frame.arguments?.first, account.clientPublicId == clientID, account.revision >= 0 {
                            updates.continuation.yield(.accountPresenceChanged(account))
                        }
                    case 3:
                        if let id = frame.invocationId { resolve(id, with: .success(frame)) }
                    case 7: throw Failure.disconnected
                    default: break
                    }
                }
            }
        } catch {
            disconnect(task)
        }
    }

    private func handshakeID(for task: URLSessionWebSocketTask) -> String { "handshake-\(task.taskIdentifier)" }

    private func keepAlive(on task: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(10))
                guard socket === task else { return }
                guard lastResponse.duration(to: .now) < .seconds(40) else { throw Failure.timedOut }
                try await task.send(.string(#"{"type":6}"# + String(Self.separator)))
            }
        } catch {
            disconnect(task)
        }
    }

    private func disconnect(_ task: URLSessionWebSocketTask) {
        guard socket === task else { return }
        socket = nil
        task.cancel(with: .normalClosure, reason: nil)
        receiveTask?.cancel()
        receiveTask = nil
        keepAliveTask?.cancel()
        keepAliveTask = nil
        windowPresence = nil
        for id in Array(pending.keys) { resolve(id, with: .failure(Failure.disconnected)) }
        updates.continuation.yield(.stateChanged(.disconnected))
    }
}
#endif
