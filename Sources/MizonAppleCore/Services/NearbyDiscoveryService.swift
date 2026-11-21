import Foundation
import MizonAPIClient
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
        let mediaAccess: NearbyMediaAccess?
        let mediaServer: PeerMediaTransportServer?
        var lastEvent = NearbyDiscoveryEvent.searching
        var trustedMedia: [PeerMediaAssetKey: NearbySharedMedia] = [:]
        var restoringMedia: [PeerMediaAssetKey: Task<NearbySharedMedia?, Error>] = [:]
        var outgoing: [UUID: Task<Data?, Error>] = [:]

        func close(endingWith event: NearbyDiscoveryEvent? = nil) {
            browser.stateUpdateHandler = nil
            browser.browseResultsChangedHandler = nil
            listener.stateUpdateHandler = nil
            browser.cancel()
            listener.cancel()
            mediaServer?.close()
            restoringMedia.values.forEach { $0.cancel() }
            outgoing.values.forEach { $0.cancel() }
            observer.cancel()
            pulse.finish()
            if let event { output.yield(event) }
            output.finish()
        }
    }

    private let networkQueue = DispatchQueue(label: "app.mizon.nearby-discovery")
    private let mediaTransfer: PeerMediaTransfer
    private var session: Session?

    public init() {
        mediaTransfer = PeerMediaTransfer(partialDirectory: URL.cachesDirectory
            .appending(path: "Mizon/PeerMedia/Parts", directoryHint: .isDirectory))
    }

    init(partialDirectory: URL) {
        mediaTransfer = PeerMediaTransfer(partialDirectory: partialDirectory)
    }

    deinit { session?.close() }

    public func start(advertising advertisement: NearbyPresenceAdvertisement) async -> AsyncStream<NearbyDiscoveryEvent> {
        startPresence(advertising: advertisement, mediaAccess: nil)
    }

    public func start(advertising advertisement: NearbyPresenceAdvertisement,
                      mediaAccess: NearbyMediaAccess) async -> AsyncStream<NearbyDiscoveryEvent> {
        startPresence(advertising: advertisement, mediaAccess: mediaAccess)
    }

    private func startPresence(advertising advertisement: NearbyPresenceAdvertisement,
                               mediaAccess: NearbyMediaAccess?) -> AsyncStream<NearbyDiscoveryEvent> {
        let (events, output) = AsyncStream<NearbyDiscoveryEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
        guard !Task.isCancelled else {
            output.finish()
            return events
        }
        closeSession()
        let generation = UUID()
        let identity = mediaAccess.flatMap { _ in try? PeerMediaTransportIdentity() }
        let secureListener = identity.flatMap { try? NWListener(using: $0.listenerParameters()) }
        let sharingAccess = secureListener == nil ? nil : mediaAccess
        let mediaServer = sharingAccess.map { _ in
            PeerMediaTransportServer { [weak self] request in
                await self?.serveMedia(request, generation: generation)
            }
        }
        let announced = advertisement.advertisingMedia(certificateSHA256: sharingAccess == nil ? nil : identity?.fingerprint)
        guard let record = NearbyAdvertisementCodec.encode(announced),
              let listener = secureListener ?? (try? NWListener(using: .tcp)) else {
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
        if let mediaServer {
            listener.newConnectionHandler = { mediaServer.accept($0) }
        } else {
            listener.newConnectionLimit = 0
            listener.newConnectionHandler = { $0.cancel() }
        }

        // Every signal asks for the current snapshot. Coalescing preserves correctness without queuing LAN bursts.
        let (signals, pulse) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        browser.stateUpdateHandler = { _ in pulse.yield(()) }
        browser.browseResultsChangedHandler = { _, _ in pulse.yield(()) }
        listener.stateUpdateHandler = { _ in pulse.yield(()) }

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
            pulse: pulse, output: output, observer: observer, mediaAccess: sharingAccess, mediaServer: mediaServer)
        output.yield(.searching)
        listener.start(queue: networkQueue)
        browser.start(queue: networkQueue)
        return events
    }

    public func stop() async { closeSession() }

    func canFetchPeerMedia(sessionID: UUID) -> Bool {
        guard let current = session, current.mediaAccess?.sessionID == sessionID else { return false }
        return current.listener.state == .ready && current.browser.state == .ready
    }

    func downloadPeerMedia(_ manifest: VerifiedMediaManifest, mediaID: UUID, destination: URL,
                           sessionID: UUID, origin: PeerMediaChunkProvider) async throws -> URL {
        try Task.checkCancellation()
        await offerVerifiedMedia(manifest, mediaID: mediaID, destination: destination, sessionID: sessionID)
        try Task.checkCancellation()
        var providers: [PeerMediaChunkProvider] = []
        if let current = session, canFetchPeerMedia(sessionID: sessionID) {
            let generation = current.generation
            providers = candidates(in: current).map { source in
                PeerMediaChunkProvider { [weak self] index in
                    guard let count = manifest.pieceLength(at: index) else { return nil }
                    let request = PeerMediaTransportRequest(sha256: manifest.rawFileHash,
                                                            chunkSize: manifest.chunkSize, index: index)
                    return try await self?.fetchMedia(request, from: source, length: count, generation: generation)
                }
            }
        }
        return try await mediaTransfer.download(manifest: manifest, origin: origin, peers: providers, destination: destination)
    }

    // The manifest and destination come from the authenticated origin and the SDK cache.
    func offerVerifiedMedia(_ manifest: VerifiedMediaManifest, mediaID: UUID, destination: URL, sessionID: UUID) async {
        guard !Task.isCancelled, canFetchPeerMedia(sessionID: sessionID), let access = session?.mediaAccess else { return }
        let key = PeerMediaAssetKey(manifest)
        register(NearbySharedMedia(manifest: manifest, completedFile: destination), for: key)
        await access.remember(mediaID, key: key)
    }

    private func candidates(in current: Session) -> [NearbyMediaSource] {
        let samples = current.browser.browseResults.prefix(NearbyPeerList.maximumResults)
        let results = NearbyPeerList.make(from: samples.lazy.compactMap(Self.advertisement), excluding: current.ourID)
        let mediaPeers = results.filter { $0.advertisement.mediaCertificateSHA256 != nil }.prefix(12)
        return mediaPeers.compactMap { peer in
            guard let fingerprint = peer.advertisement.mediaCertificateSHA256,
                  let result = samples.first(where: { Self.advertisement(from: $0) == peer.advertisement }) else { return nil }
            return NearbyMediaSource(endpoint: result.endpoint, fingerprint: fingerprint)
        }
    }

    private func fetchMedia(_ request: PeerMediaTransportRequest, from source: NearbyMediaSource,
                            length: Int, generation: UUID) async throws -> Data? {
        try Task.checkCancellation()
        guard let current = session, current.generation == generation, current.outgoing.count < 12 else { return nil }
        let id = UUID()
        let fetch = Task {
            try await PeerMediaTransport.fetchPiece(from: source.endpoint, fingerprint: source.fingerprint,
                                                    request: request, expectedLength: length)
        }
        session?.outgoing[id] = fetch
        defer {
            if session?.generation == generation { session?.outgoing[id] = nil }
        }
        return try await withTaskCancellationHandler {
            try await fetch.value
        } onCancel: {
            fetch.cancel()
        }
    }

    private func serveMedia(_ request: PeerMediaTransportRequest, generation: UUID) async -> Data? {
        guard !Task.isCancelled, session?.generation == generation,
              let access = session?.mediaAccess else { return nil }
        let key = PeerMediaAssetKey(request)
        let asset: NearbySharedMedia
        if let approved = session?.trustedMedia[key], .now < approved.expiresAt {
            asset = approved
        } else {
            guard let approved = await restoreMedia(key, access: access, generation: generation) else { return nil }
            asset = approved
        }
        guard !Task.isCancelled, session?.generation == generation else { return nil }
        let data = try? await mediaTransfer.verifiedPiece(request.index, from: asset.manifest,
                                                          completedFile: asset.completedFile)
        return !Task.isCancelled && session?.generation == generation ? data : nil
    }

    private func restoreMedia(_ key: PeerMediaAssetKey, access: NearbyMediaAccess, generation: UUID) async -> NearbySharedMedia? {
        if let pending = session?.restoringMedia[key] { return try? await pending.value }
        guard let current = session, current.generation == generation, current.restoringMedia.count < 4 else { return nil }
        let lookup = Task { try await access.restore(key) }
        session?.restoringMedia[key] = lookup
        let asset = try? await lookup.value
        guard session?.generation == generation else { return nil }
        session?.restoringMedia[key] = nil
        if let asset { register(asset, for: key) }
        return asset
    }

    private func register(_ asset: NearbySharedMedia, for key: PeerMediaAssetKey) {
        if let current = session, current.trustedMedia[key] == nil, current.trustedMedia.count >= 128,
           let oldest = current.trustedMedia.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
            session?.trustedMedia[oldest] = nil
        }
        session?.trustedMedia[key] = asset
    }

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
