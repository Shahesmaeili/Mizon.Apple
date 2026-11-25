#if os(macOS) || os(iOS) || os(watchOS)
import Foundation
import MizonAPI

protocol AccountPresenceTransport: Sendable {
    var windowPresence: ClientWindowPresenceResponse? { get async }
    func events() async -> AsyncStream<MizonSocketEvent>
    func start() async throws
    func setWindowPresence(isActive: Bool) async throws
    func watchAccountPresence() async throws -> ClientAccountPresenceResponse
    func dispose() async
}

extension MizonSocket: AccountPresenceTransport {}

@MainActor
public final class AccountPresenceCoordinator {
    public private(set) var isOnline = false
    private let clientPublicID: UUID
    private let transport: any AccountPresenceTransport
    private let onChange: @MainActor (Bool) -> Void
    private let retryDelays: [Duration]
    private var observedState: HubConnectionState = .disconnected
    private var connectionGeneration = UUID()
    private var windowActive = false
    private var localOnline = false
    private var watchesAccount = false
    private var accountSnapshot: ClientAccountPresenceResponse?
    private var stopped = false
    private var exhaustedConnectionAttempts = false
    private var eventTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var reportTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var reportID: UUID?

    public convenience init(socket: MizonSocket, clientPublicID: UUID,
                            onChange: @escaping @MainActor (Bool) -> Void = { _ in }) {
        self.init(transport: socket, clientPublicID: clientPublicID, onChange: onChange)
    }

    init(transport: any AccountPresenceTransport, clientPublicID: UUID,
         retryDelays: [Duration] = [.zero, .seconds(1), .seconds(2), .seconds(5)],
         onChange: @escaping @MainActor (Bool) -> Void) {
        self.transport = transport
        self.clientPublicID = clientPublicID
        self.retryDelays = retryDelays
        self.onChange = onChange
    }

    /// The Mac menu bar follows the account even with no foreground Mizon window.
    public func observeAccount() {
        guard !stopped, !watchesAccount else { return }
        watchesAccount = true
        exhaustedConnectionAttempts = false
        receiveEvents()
        connectIfNeeded()
        subscribeIfConnected()
    }

    public func setWindowActive(_ active: Bool) {
        guard !stopped, windowActive != active else { return }
        windowActive = active
        localOnline = false
        publishOnline()
        if active {
            exhaustedConnectionAttempts = false
            receiveEvents()
            connectIfNeeded()
        }
        reportWindowPresence()
    }

    public func stop() async {
        guard !stopped else { return }
        stopped = true
        eventTask?.cancel()
        eventTask = nil
        connectTask?.cancel()
        connectTask = nil
        clearConnectionState()
        await transport.dispose()
    }

    private var shouldConnect: Bool { !stopped && (windowActive || watchesAccount) }

    private func receiveEvents() {
        guard eventTask == nil else { return }
        eventTask = Task { [weak self, transport] in
            let events = await transport.events()
            for await event in events {
                guard !Task.isCancelled else { return }
                switch event {
                case .stateChanged(let state): self?.connectionChanged(state)
                case .accountPresenceChanged(let snapshot?): self?.acceptAccountSnapshot(snapshot)
                case .accountPresenceChanged(nil):
                    self?.accountSnapshot = nil
                    self?.publishOnline()
                default: break
                }
            }
        }
    }

    private func connectionChanged(_ state: HubConnectionState) {
        guard !stopped, observedState != state else { return }
        observedState = state
        if state == .connected {
            exhaustedConnectionAttempts = false
            subscribeIfConnected()
            reportWindowPresence()
        } else {
            clearConnectionState()
            connectIfNeeded()
        }
    }

    private func clearConnectionState() {
        connectionGeneration = UUID()
        watchTask?.cancel()
        watchTask = nil
        cancelWindowReport()
        accountSnapshot = nil
        localOnline = false
        publishOnline()
    }

    private func connectIfNeeded() {
        guard shouldConnect, observedState == .disconnected, connectTask == nil, !exhaustedConnectionAttempts else { return }
        connectTask = Task { [weak self, transport, retryDelays] in
            defer { self?.connectTask = nil }
            repeat {
                for delay in retryDelays {
                    do {
                        try await Task.sleep(for: delay)
                        guard self?.shouldConnect == true, self?.observedState == .disconnected else { return }
                        try await transport.start()
                        return
                    } catch is CancellationError {
                        return
                    } catch {
                        // The SDK handles reconnects on a connection that has already started.
                    }
                }
                guard self?.watchesAccount == true else {
                    self?.exhaustedConnectionAttempts = true
                    return
                }
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            } while self?.shouldConnect == true
        }
    }

    private func subscribeIfConnected() {
        guard watchesAccount, observedState == .connected, watchTask == nil else { return }
        let generation = connectionGeneration
        watchTask = Task { [weak self, transport] in
            // Earlier servers can still acknowledge local focus without supporting the account feed.
            guard let snapshot = try? await transport.watchAccountPresence(), !Task.isCancelled,
                  let self, self.connectionGeneration == generation else { return }
            self.acceptAccountSnapshot(snapshot)
        }
    }

    private func acceptAccountSnapshot(_ snapshot: ClientAccountPresenceResponse) {
        guard !stopped, watchesAccount, observedState == .connected,
              snapshot.clientPublicId == clientPublicID, snapshot.revision >= 0,
              accountSnapshot.map({ snapshot.revision > $0.revision }) ?? true else { return }
        accountSnapshot = snapshot
        publishOnline()
    }

    private func reportWindowPresence() {
        cancelWindowReport()
        guard observedState == .connected else { return }
        let active = windowActive
        let id = UUID()
        reportID = id
        reportTask = Task { [weak self, transport, clientPublicID, retryDelays] in
            for delay in retryDelays {
                do {
                    try await Task.sleep(for: delay)
                    try await transport.setWindowPresence(isActive: active)
                    let confirmation = await transport.windowPresence
                    guard !Task.isCancelled, let self, self.reportID == id else { return }
                    guard let confirmation, confirmation.clientPublicId == clientPublicID,
                          confirmation.isOnline == active else { continue }
                    self.localOnline = active
                    self.publishOnline()
                    return
                } catch is CancellationError {
                    return
                } catch {
                    // Keep the independent account feed while this focus report retries.
                }
            }
        }
    }

    private func cancelWindowReport() {
        reportID = nil
        reportTask?.cancel()
        reportTask = nil
    }

    private func publishOnline() {
        let online = accountSnapshot?.isOnline ?? localOnline
        guard isOnline != online else { return }
        isOnline = online
        onChange(online)
    }
}
#endif
