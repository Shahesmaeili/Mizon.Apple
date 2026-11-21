import Foundation
import Network
import dnssd

public enum NearbyDiscoveryEvent: Equatable, Sendable {
    case peers([NearbyDiscoveredPeer])
    case searching
    case unavailable
    case permissionDenied
}

public protocol NearbyDiscovering: Sendable {
    func start(advertising: NearbyPresenceAdvertisement) async -> AsyncStream<NearbyDiscoveryEvent>
    func stop() async
}

public actor NearbyDiscoveryService: NearbyDiscovering {
    private struct Session: Sendable {
        let generation: UUID
        let ourID: UUID
        let browser: NWBrowser
        let listener: NWListener
        let pulse: AsyncStream<Void>.Continuation
        let output: AsyncStream<NearbyDiscoveryEvent>.Continuation
        let observer: Task<Void, Never>
        var lastEvent = NearbyDiscoveryEvent.searching

        func close(endingWith event: NearbyDiscoveryEvent? = nil) {
            browser.stateUpdateHandler = nil
            browser.browseResultsChangedHandler = nil
            listener.stateUpdateHandler = nil
            browser.cancel()
            listener.cancel()
            observer.cancel()
            pulse.finish()
            if let event { output.yield(event) }
            output.finish()
        }
    }

    private let networkQueue = DispatchQueue(label: "app.mizon.nearby-discovery")
    private var session: Session?

    public init() {}

    deinit { session?.close() }

    public func start(advertising advertisement: NearbyPresenceAdvertisement) async -> AsyncStream<NearbyDiscoveryEvent> {
        let (events, output) = AsyncStream<NearbyDiscoveryEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
        guard !Task.isCancelled else {
            output.finish()
            return events
        }
        closeSession()
        guard let record = NearbyAdvertisementCodec.encode(advertisement), let listener = try? NWListener(using: .tcp) else {
            output.yield(.unavailable)
            output.finish()
            return events
        }

        let type = NearbyAdvertisementCodec.serviceType
        let domain = NearbyAdvertisementCodec.domain
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: domain), using: .tcp)
        var service = NWListener.Service(name: NearbyAdvertisementCodec.serviceName(for: advertisement.id),
            type: type, domain: domain, txtRecord: NWTXTRecord(record))
        service.noAutoRename = true
        listener.service = service
        listener.newConnectionLimit = 0
        listener.newConnectionHandler = { connection in connection.cancel() }

        // Every signal asks for the current snapshot. Coalescing preserves correctness without queuing LAN bursts.
        let (signals, pulse) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        browser.stateUpdateHandler = { _ in pulse.yield(()) }
        browser.browseResultsChangedHandler = { _, _ in pulse.yield(()) }
        listener.stateUpdateHandler = { _ in pulse.yield(()) }

        let generation = UUID()
        output.onTermination = { [weak self] _ in
            Task { await self?.closeSession(generation: generation) }
        }
        let observer = Task { [weak self] in
            for await _ in signals {
                guard !Task.isCancelled, let self else { return }
                await self.refresh(generation: generation)
            }
        }
        session = Session(generation: generation, ourID: advertisement.id, browser: browser, listener: listener,
            pulse: pulse, output: output, observer: observer)
        output.yield(.searching)
        listener.start(queue: networkQueue)
        browser.start(queue: networkQueue)
        return events
    }

    public func stop() async { closeSession() }

    private func closeSession(generation: UUID? = nil, endingWith event: NearbyDiscoveryEvent? = nil) {
        guard let current = session, generation == nil || current.generation == generation else { return }
        session = nil
        current.close(endingWith: event)
    }

    private func refresh(generation: UUID) {
        guard let current = session, current.generation == generation else { return }
        let listener = Self.status(current.listener.state)
        let browser = Self.status(current.browser.state)
        if listener == .denied || browser == .denied {
            closeSession(generation: generation, endingWith: .permissionDenied)
            return
        }
        if listener == .failed || browser == .failed {
            closeSession(generation: generation, endingWith: .unavailable)
            return
        }

        let event: NearbyDiscoveryEvent
        if listener == .waitingForPermission || browser == .waitingForPermission {
            event = .permissionDenied
        } else if listener == .waiting || browser == .waiting {
            event = .unavailable
        } else if listener == .ready && browser == .ready {
            let candidates = current.browser.browseResults.prefix(NearbyPeerList.maximumResults).lazy.compactMap(Self.advertisement)
            event = .peers(NearbyPeerList.make(from: candidates, excluding: current.ourID))
        } else {
            event = .searching
        }
        if event != current.lastEvent {
            session?.lastEvent = event
            current.output.yield(event)
        }
    }

    private enum Status { case setup, ready, waiting, waitingForPermission, denied, failed }

    private static func status(_ state: NWBrowser.State) -> Status {
        switch state {
        case .setup: .setup
        case .ready: .ready
        case .waiting(let error): isPolicyDenied(error) ? .waitingForPermission : .waiting
        case .failed(let error): isPolicyDenied(error) ? .denied : .failed
        case .cancelled: .failed
        @unknown default: .failed
        }
    }

    private static func status(_ state: NWListener.State) -> Status {
        switch state {
        case .setup: .setup
        case .ready: .ready
        case .waiting(let error): isPolicyDenied(error) ? .waitingForPermission : .waiting
        case .failed(let error): isPolicyDenied(error) ? .denied : .failed
        case .cancelled: .failed
        @unknown default: .failed
        }
    }

    private static func isPolicyDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return code == kDNSServiceErr_PolicyDenied }
        return false
    }

    private static func advertisement(from result: NWBrowser.Result) -> NearbyPresenceAdvertisement? {
        guard case .service(let name, let type, let domain, _) = result.endpoint,
              type == NearbyAdvertisementCodec.serviceType || type == NearbyAdvertisementCodec.serviceType + ".",
              domain.lowercased() == NearbyAdvertisementCodec.domain,
              case .bonjour(let record) = result.metadata else { return nil }
        return NearbyAdvertisementCodec.decode(record.data, serviceName: name)
    }
}

enum NearbyPeerList {
    static let maximumResults = 256
    static let maximumPeers = 64

    static func make(from advertisements: some Sequence<NearbyPresenceAdvertisement>, excluding ourID: UUID) -> [NearbyDiscoveredPeer] {
        var byID: [UUID: NearbyPresenceAdvertisement] = [:]
        var conflicts: Set<UUID> = []
        for item in advertisements.prefix(maximumResults) where item.id != ourID {
            if let existing = byID[item.id], existing != item { conflicts.insert(item.id) }
            byID[item.id] = item
        }
        return byID.values.filter { !conflicts.contains($0.id) }.sorted { left, right in
            let deviceOrder = left.deviceName.localizedStandardCompare(right.deviceName)
            if deviceOrder == .orderedSame { return left.id.uuidString < right.id.uuidString }
            return deviceOrder == .orderedAscending
        }.prefix(maximumPeers).map(NearbyDiscoveredPeer.init(advertisement:))
    }
}
