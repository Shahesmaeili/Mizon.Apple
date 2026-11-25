#if os(macOS)
import Foundation
import MizonAPI

protocol MacProfilePresenceTransport: Sendable {
    var windowPresence: ClientWindowPresenceResponse? { get async }
    func events() async -> AsyncStream<MizonSocketEvent>
    func start() async throws
    func setWindowPresence(isActive: Bool) async throws
    func dispose() async
}

extension MizonSocket: MacProfilePresenceTransport {}

/// Owns the presence connection for one validated account in the Mac window.
@MainActor
public final class MacProfilePresence {
    public private(set) var isOnline = false
    private let clientPublicID: UUID
    private let transport: any MacProfilePresenceTransport
    private let onChange: @MainActor (Bool) -> Void
    private let retryDelays: [Duration]
    private var observedState: HubConnectionState = .disconnected
    private var windowActive = false
    private var stopped = false
    private var exhaustedConnectionAttempts = false
    private var eventTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var requestID: UUID?

    public convenience init(socket: MizonSocket, clientPublicID: UUID,
                            onChange: @escaping @MainActor (Bool) -> Void = { _ in }) {
        self.init(transport: socket, clientPublicID: clientPublicID, onChange: onChange)
    }

    init(transport: any MacProfilePresenceTransport, clientPublicID: UUID,
         retryDelays: [Duration] = [.zero, .seconds(1), .seconds(2), .seconds(5)],
         onChange: @escaping @MainActor (Bool) -> Void) {
        self.transport = transport
        self.clientPublicID = clientPublicID
        self.retryDelays = retryDelays
        self.onChange = onChange
    }

    public func setWindowActive(_ active: Bool) {
        guard !stopped, windowActive != active else { return }
        windowActive = active
        setOnline(false)
        if active {
            exhaustedConnectionAttempts = false
            observeConnection()
            connectIfNeeded()
        }
        sendCurrentPresence()
    }

    public func stop() async {
        guard !stopped else { return }
        stopped = true
        eventTask?.cancel()
        eventTask = nil
        connectTask?.cancel()
        connectTask = nil
        cancelPresenceRequest()
        setOnline(false)
        // The hub removes this connection's presence when it disconnects.
        await transport.dispose()
    }

    private func observeConnection() {
        guard eventTask == nil else { return }
        eventTask = Task { [weak self, transport] in
            let events = await transport.events()
            for await event in events {
                guard !Task.isCancelled else { return }
                if case .stateChanged(let state) = event { self?.connectionChanged(state) }
            }
        }
    }

    private func connectionChanged(_ state: HubConnectionState) {
        guard !stopped, observedState != state else { return }
        observedState = state
        if state == .connected {
            exhaustedConnectionAttempts = false
            sendCurrentPresence()
        } else {
            cancelPresenceRequest()
            setOnline(false)
            connectIfNeeded()
        }
    }

    private func connectIfNeeded() {
        guard windowActive, observedState == .disconnected, connectTask == nil, !exhaustedConnectionAttempts else { return }
        connectTask = Task { [weak self, transport, retryDelays] in
            defer { self?.connectTask = nil }
            for delay in retryDelays {
                do {
                    try await Task.sleep(for: delay)
                    guard self?.windowActive == true else { return }
                    try await transport.start()
                    return
                } catch is CancellationError {
                    return
                } catch {
                    // Wait before retrying an initial failure or an exhausted SDK reconnect.
                }
            }
            self?.exhaustedConnectionAttempts = true
        }
    }

    private func sendCurrentPresence() {
        cancelPresenceRequest()
        guard observedState == .connected else { return }
        let active = windowActive
        let id = UUID()
        requestID = id
        requestTask = Task { [weak self, transport, clientPublicID, retryDelays] in
            for delay in retryDelays {
                do {
                    try await Task.sleep(for: delay)
                    try await transport.setWindowPresence(isActive: active)
                    let confirmation = await transport.windowPresence
                    guard !Task.isCancelled, self?.requestID == id else { return }
                    guard let confirmation, confirmation.clientPublicId == clientPublicID,
                          confirmation.isOnline == active else { continue }
                    self?.setOnline(active)
                    return
                } catch is CancellationError {
                    return
                } catch {
                    // A failed or mismatched acknowledgement leaves the badge offline.
                }
            }
        }
    }

    private func cancelPresenceRequest() {
        requestID = nil
        requestTask?.cancel()
        requestTask = nil
    }

    private func setOnline(_ online: Bool) {
        guard isOnline != online else { return }
        isOnline = online
        onChange(online)
    }
}
#endif
