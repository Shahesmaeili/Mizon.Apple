import Foundation
import MizonAPIClient

/// Fetches at most the manifest's exact piece length. A nil result means the source lacks that piece.
public struct PeerMediaChunkProvider: Sendable {
    public let availablePieces: IndexSet?
    private let fetch: @Sendable (Int) async throws -> Data?

    public init(availablePieces: IndexSet? = nil, fetch: @escaping @Sendable (Int) async throws -> Data?) {
        self.availablePieces = availablePieces
        self.fetch = fetch
    }

    func piece(_ index: Int) async throws -> Data? { try await fetch(index) }
}

public enum PeerMediaTransferError: Error, Equatable {
    case unsupportedFileSize
    case invalidDestination
    case alreadyDownloading
    case transferCapacityExceeded
    case missingOriginPiece(Int)
    case invalidOriginPiece(Int)
    case fileIntegrityMismatch
}

public actor PeerMediaTransfer {
    public static let maximumFileSize: Int64 = 8 * 1024 * 1024 * 1024

    private static let maximumActiveTransfers = 2
    private static let maximumPeers = 8
    private static let maximumPeerAttempts = 3
    private static let maximumWaiters = 16
    private static let maximumQueuedTransfers = 16

    private struct ActiveDownload {
        let manifest: VerifiedMediaManifest
        let destination: URL
        var waiters: [UUID: CheckedContinuation<URL, any Error>] = [:]
    }

    private struct CapacityWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let store: PeerMediaPartialStore
    private let maximumConcurrentChunks: Int
    private var active: [String: ActiveDownload] = [:]
    private var destinations: Set<URL> = []
    private var capacityQueue: [CapacityWaiter] = []
    private var reservedCapacity: Set<UUID> = []

    public init(partialDirectory: URL, maximumConcurrentChunks: Int = 4) {
        store = PeerMediaPartialStore(directory: partialDirectory)
        self.maximumConcurrentChunks = min(8, max(1, maximumConcurrentChunks))
    }

    public func download(manifest: VerifiedMediaManifest, origin: PeerMediaChunkProvider,
                         peers: [PeerMediaChunkProvider], destination: URL) async throws -> URL {
        try Task.checkCancellation()
        try Self.checkFileSize(manifest)
        guard store.isValidDestination(destination) else { throw PeerMediaTransferError.invalidDestination }

        let key = PeerMediaPartialStore.key(for: manifest)
        let destination = destination.standardizedFileURL
        if try canJoin(key: key, manifest: manifest, destination: destination) {
            return try await waitForDownload(key: key)
        }

        if active.count + reservedCapacity.count >= Self.maximumActiveTransfers {
            let reservation = try await waitForCapacity()
            reservedCapacity.remove(reservation)
        }

        guard try beginDownload(key: key, manifest: manifest, destination: destination) else {
            return try await waitForDownload(key: key)
        }
        let result: Result<URL, any Error>
        do {
            let url = try await assemble(manifest, origin: origin, peers: peers, destination: destination, key: key)
            result = .success(url)
        } catch {
            result = .failure(error)
        }
        destinations.remove(destination)
        if let finished = active.removeValue(forKey: key) {
            for waiter in finished.waiters.values { waiter.resume(with: result) }
        }
        grantCapacity()
        return try result.get()
    }

    private func canJoin(key: String, manifest: VerifiedMediaManifest, destination: URL) throws -> Bool {
        if let current = active[key] {
            guard current.manifest == manifest, current.destination == destination,
                  current.waiters.count < Self.maximumWaiters else { throw PeerMediaTransferError.alreadyDownloading }
            return true
        }
        guard !destinations.contains(destination) else { throw PeerMediaTransferError.alreadyDownloading }
        return false
    }

    private func beginDownload(key: String, manifest: VerifiedMediaManifest, destination: URL) throws -> Bool {
        defer { grantCapacity() }
        try Task.checkCancellation()
        if try canJoin(key: key, manifest: manifest, destination: destination) { return false }
        active[key] = ActiveDownload(manifest: manifest, destination: destination)
        destinations.insert(destination)
        return true
    }

    private func waitForCapacity() async throws -> UUID {
        guard capacityQueue.count < Self.maximumQueuedTransfers else {
            throw PeerMediaTransferError.transferCapacityExceeded
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                capacityQueue.append(CapacityWaiter(id: id, continuation: continuation))
                grantCapacity()
            }
        } onCancel: {
            Task { await self.cancelCapacityWaiter(id) }
        }
        return id
    }

    private func grantCapacity() {
        while active.count + reservedCapacity.count < Self.maximumActiveTransfers, !capacityQueue.isEmpty {
            let waiter = capacityQueue.removeFirst()
            reservedCapacity.insert(waiter.id)
            waiter.continuation.resume()
        }
    }

    private func cancelCapacityWaiter(_ id: UUID) {
        guard let index = capacityQueue.firstIndex(where: { $0.id == id }) else { return }
        capacityQueue.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func assemble(_ manifest: VerifiedMediaManifest, origin: PeerMediaChunkProvider,
                          peers: [PeerMediaChunkProvider], destination: URL, key: String) async throws -> URL {
        if try await PeerMediaFileIntegrity.matches(destination, manifest: manifest) { return destination }
        try Task.checkCancellation()
        let otherTransfers = active.filter { $0.key != key }.mapValues(\.manifest.fileSize)
        try store.reserve(manifest, active: otherTransfers)
        let peers = Array(peers.prefix(Self.maximumPeers))
        let rejected = RejectedPeerSources()
        let partial = store.payloadURL(for: manifest)
        try await fillMissing(manifest, origin: origin, peers: peers, rejected: rejected)
        if try await PeerMediaFileIntegrity.matches(partial, manifest: manifest) == false {
            let damaged = try await PeerMediaFileIntegrity.invalidPieces(in: partial, manifest: manifest)
            guard !damaged.isEmpty else {
                try? store.discard(manifest)
                throw PeerMediaTransferError.fileIntegrityMismatch
            }
            try store.invalidate(damaged, manifest: manifest)
            try await fillMissing(manifest, origin: origin, peers: peers, rejected: rejected)
            guard try await PeerMediaFileIntegrity.matches(partial, manifest: manifest) else {
                try? store.discard(manifest)
                throw PeerMediaTransferError.fileIntegrityMismatch
            }
        }

        try await PeerMediaFileIntegrity.publish(partial, to: destination, manifest: manifest)
        return destination
    }

    private func waitForDownload(key: String) async throws -> URL {
        let id = UUID()
        let url = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<URL, any Error>) in
                guard !Task.isCancelled, active[key] != nil else {
                    waiter.resume(throwing: CancellationError())
                    return
                }
                active[key]?.waiters[id] = waiter
            }
        } onCancel: {
            Task { await self.cancelWaiter(id, key: key) }
        }
        try Task.checkCancellation()
        return url
    }

    private func cancelWaiter(_ id: UUID, key: String) {
        active[key]?.waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    /// Returns durable commit markers. Serving separately validates the bytes still on disk.
    public func verifiedPieces(for manifest: VerifiedMediaManifest) throws -> IndexSet {
        try Self.checkFileSize(manifest)
        return try store.availablePieces(for: manifest)
    }

    public func verifiedPiece(_ index: Int, from manifest: VerifiedMediaManifest, completedFile: URL? = nil) throws -> Data? {
        try Task.checkCancellation()
        try Self.checkFileSize(manifest)
        guard let range = manifest.range(for: index) else { return nil }
        if (try? store.contains(index, manifest: manifest)) == true {
            if let data = try? PeerMediaFileIntegrity.read(range, from: store.payloadURL(for: manifest)),
               manifest.verify(data, at: index) {
                try Task.checkCancellation()
                return data
            }
            try? store.invalidate(IndexSet(integer: index), manifest: manifest)
        }

        try Task.checkCancellation()
        guard let completedFile, completedFile.isFileURL,
              let data = try PeerMediaFileIntegrity.read(range, from: completedFile),
              manifest.verify(data, at: index) else { return nil }
        try Task.checkCancellation()
        return data
    }

    public func discard(_ manifest: VerifiedMediaManifest) throws {
        guard active[PeerMediaPartialStore.key(for: manifest)] == nil else {
            throw PeerMediaTransferError.alreadyDownloading
        }
        try store.discard(manifest)
    }

    private static func checkFileSize(_ manifest: VerifiedMediaManifest) throws {
        guard manifest.fileSize > 0, manifest.fileSize <= maximumFileSize else {
            throw PeerMediaTransferError.unsupportedFileSize
        }
    }

    private func fillMissing(_ manifest: VerifiedMediaManifest, origin: PeerMediaChunkProvider,
                             peers: [PeerMediaChunkProvider], rejected: RejectedPeerSources) async throws {
        let all = IndexSet(integersIn: 0..<manifest.pieceCount)
        let saved = try store.availablePieces(for: manifest)
        let missing = all.subtracting(saved)
        let preferred = peers.reduce(into: IndexSet()) { preferred, peer in
            if let availability = peer.availablePieces {
                preferred.formUnion(availability.intersection(missing))
            }
        }
        var order = (Array(preferred) + Array(missing.subtracting(preferred))).makeIterator()

        try await withThrowingTaskGroup(of: VerifiedTransferPiece.self) { group in
            for _ in 0..<maximumConcurrentChunks {
                guard let index = order.next() else { break }
                group.addTask { try await Self.fetch(index, manifest: manifest, peers: peers, origin: origin, rejected: rejected) }
            }

            while let piece = try await group.next() {
                try Task.checkCancellation()
                try store.write(piece, manifest: manifest)
                if let index = order.next() {
                    group.addTask { try await Self.fetch(index, manifest: manifest, peers: peers, origin: origin, rejected: rejected) }
                }
            }
        }
    }

    private static func fetch(_ index: Int, manifest: VerifiedMediaManifest, peers: [PeerMediaChunkProvider],
                              origin: PeerMediaChunkProvider, rejected: RejectedPeerSources) async throws -> VerifiedTransferPiece {
        var attempts = 0
        for source in candidates(for: index, from: peers) {
            try Task.checkCancellation()
            if attempts == maximumPeerAttempts { break }
            guard await !rejected.contains(source) else { continue }
            attempts += 1
            do {
                if let bytes = try await peers[source].piece(index) {
                    if let piece = VerifiedTransferPiece(index: index, bytes: bytes, manifest: manifest) {
                        try Task.checkCancellation()
                        return piece
                    }
                    await rejected.insert(source)
                }
            } catch {
                try Task.checkCancellation()
                await rejected.insert(source)
            }
        }

        try Task.checkCancellation()
        guard let bytes = try await origin.piece(index) else { throw PeerMediaTransferError.missingOriginPiece(index) }
        try Task.checkCancellation()
        guard let piece = VerifiedTransferPiece(index: index, bytes: bytes, manifest: manifest) else {
            throw PeerMediaTransferError.invalidOriginPiece(index)
        }
        return piece
    }

    private static func candidates(for index: Int, from peers: [PeerMediaChunkProvider]) -> [Int] {
        guard !peers.isEmpty else { return [] }
        let start = index % peers.count
        let rotated = Array(start..<peers.count) + Array(0..<start)
        let exact = rotated.filter { peers[$0].availablePieces?.contains(index) == true }
        let unknown = rotated.filter { peers[$0].availablePieces == nil }
        return exact + unknown
    }
}

/// Suppresses a failing source for the current transfer. Missing pieces on a live partial peer are normal.
private actor RejectedPeerSources {
    private var peers = Set<Int>()

    func contains(_ index: Int) -> Bool { peers.contains(index) }
    func insert(_ index: Int) { peers.insert(index) }
}

/// Construct this value only after validating both the exact byte count and the trusted SHA-256.
struct VerifiedTransferPiece: Sendable {
    let index: Int
    let bytes: Data

    fileprivate init?(index: Int, bytes: Data, manifest: VerifiedMediaManifest) {
        guard manifest.verify(bytes, at: index) else { return nil }
        self.index = index
        self.bytes = bytes
    }
}
