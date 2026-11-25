import CryptoKit
import Foundation
import MizonAPI
import MizonAPIClient
import Network

struct PeerMediaAssetKey: Codable, Hashable, Sendable {
    let fileHash: String
    let chunkSize: Int

    init(fileHash: String, chunkSize: Int) {
        self.fileHash = fileHash.lowercased()
        self.chunkSize = chunkSize
    }

    init(_ manifest: VerifiedMediaManifest) {
        self.init(fileHash: manifest.fileHash, chunkSize: manifest.chunkSize)
    }

    init(_ request: PeerMediaTransportRequest) {
        self.init(fileHash: request.sha256.map { String(format: "%02x", $0) }.joined(),
                  chunkSize: request.chunkSize)
    }
}

struct NearbyMediaSource: Sendable {
    let endpoint: NWEndpoint
    let interfaces: [NWInterface]
    let fingerprint: String
    let alternatePort: UInt16?
}

struct NearbySharedMedia: Sendable {
    let manifest: VerifiedMediaManifest
    let completedFile: URL
    let expiresAt: ContinuousClock.Instant

    init(manifest: VerifiedMediaManifest, completedFile: URL) {
        self.manifest = manifest
        self.completedFile = completedFile
        expiresAt = .now.advanced(by: .seconds(300))
    }
}

/// Scope for a signed-in Nearby listener. The persistent index holds references, and the
/// authenticated origin must approve a restored reference before it is shared.
public struct NearbyMediaAccess: Sendable {
    private let api: MizonApi
    let sessionID: UUID
    private let accessToken: String
    private let endpoints: Endpoints
    private let downloader: MediaDownloader
    private let index: NearbyMediaShareIndex

    init(api: MizonApi, session: AuthSession, cacheRoot: URL? = nil) {
        self.api = api
        sessionID = session.sessionPublicId
        accessToken = session.accessToken
        endpoints = Endpoints(baseURL: session.server)
        let root = cacheRoot ?? MusicArtworkStore.cacheDirectory(for: session)
        downloader = MediaDownloader(cacheRoot: root)
        let originKey = SHA256.hash(data: Data(session.server.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        index = NearbyMediaShareIndex(file: root.appending(path: "PeerCatalog-\(originKey).json"))
    }

    func remember(_ mediaID: UUID, key: PeerMediaAssetKey) async {
        await index.remember(mediaID, for: key)
    }

    func restore(_ key: PeerMediaAssetKey) async throws -> NearbySharedMedia? {
        guard let mediaID = await index.mediaID(for: key) else { return nil }
        try Task.checkCancellation()
        guard !accessToken.isEmpty, await api.getToken() == accessToken else { throw CancellationError() }
        let response = await api.sendRequest(MediaOperation(.init(mediaPublicId: mediaID), endpoints: endpoints))
        try Task.checkCancellation()
        guard response.isSuccess, let media = response.content, media.mediaPublicId == mediaID,
              PeerMediaAssetKey(fileHash: media.fileHash, chunkSize: media.chunkSize) == key,
              await api.getToken() == accessToken,
              let manifest = try await downloader.peerManifest(for: media, api: api, endpoints: endpoints),
              PeerMediaAssetKey(manifest) == key else { return nil }
        try Task.checkCancellation()
        guard await api.getToken() == accessToken else { throw CancellationError() }
        return NearbySharedMedia(manifest: manifest, completedFile: try await downloader.getCachedFilePath(media))
    }
}

private actor NearbyMediaShareIndex {
    private struct Entry: Codable {
        let key: PeerMediaAssetKey
        let mediaID: UUID
    }

    private let file: URL
    private var entries: [Entry]?
    private static let limit = 128
    private static let maximumFileBytes = 64 * 1024

    init(file: URL) { self.file = file }

    func mediaID(for key: PeerMediaAssetKey) -> UUID? {
        loadIfNeeded()
        return entries?.first(where: { $0.key == key })?.mediaID
    }

    func remember(_ mediaID: UUID, for key: PeerMediaAssetKey) {
        loadIfNeeded()
        guard var updated = entries else { return }
        if let first = updated.first, first.key == key, first.mediaID == mediaID { return }
        updated.removeAll { $0.key == key }
        updated.insert(Entry(key: key, mediaID: mediaID), at: 0)
        if updated.count > Self.limit { updated.removeLast(updated.count - Self.limit) }
        entries = updated
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: file, options: .atomic)
        } catch {
            // The in-memory authorization and current download still work if the cache is unavailable.
        }
    }

    private func loadIfNeeded() {
        guard entries == nil else { return }
        guard let length = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              length <= Self.maximumFileBytes, let data = try? Data(contentsOf: file),
              data.count <= Self.maximumFileBytes, let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            entries = []
            return
        }
        entries = Array(decoded.prefix(Self.limit))
    }
}
