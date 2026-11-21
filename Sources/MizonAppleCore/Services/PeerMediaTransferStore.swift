import Foundation
import MizonAPIClient

/// Uses an exclusive partial-directory owner. Keep the payload and committed-piece bitmap together.
struct PeerMediaPartialStore {
    private static let maximumStoredBytes: Int64 = 16 * 1024 * 1024 * 1024
    private static let maximumArtifacts = 16
    private let directory: URL

    init(directory: URL) {
        self.directory = directory.standardizedFileURL
    }

    static func key(for manifest: VerifiedMediaManifest) -> String {
        "\(manifest.fileHash).\(manifest.chunkSize)"
    }

    func isValidDestination(_ url: URL) -> Bool {
        guard directory.isFileURL, url.isFileURL, !url.hasDirectoryPath else { return false }
        let destination = url.standardizedFileURL
        return !destination.pathComponents.starts(with: directory.pathComponents) &&
            !destination.resolvingSymlinksInPath().pathComponents.starts(with: directory.resolvingSymlinksInPath().pathComponents)
    }

    func reserve(_ manifest: VerifiedMediaManifest, active: [String: Int64]) throws {
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let ownKey = Self.key(for: manifest)
        let reserved = active.values.reduce(manifest.fileSize, +)
        let byteBudget = Self.maximumStoredBytes - reserved
        let artifactBudget = Self.maximumArtifacts - active.count - 1

        let entries = try files.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey, .nameKey],
            options: [.skipsHiddenFiles])
        let candidates = try entries.compactMap { url -> (url: URL, modified: Date, bytes: Int64)? in
            let key = url.lastPathComponent
            guard key != ownKey, active[key] == nil, Self.isArtifactDirectory(key) else { return nil }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            let path = url.appending(path: "payload", directoryHint: .notDirectory)
            let payload = try? path.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
            let bytes = Int64(payload?.totalFileAllocatedSize ?? payload?.fileAllocatedSize ?? payload?.fileSize ?? 0)
            return (url, values.contentModificationDate ?? .distantPast, bytes)
        }.sorted { $0.modified < $1.modified }

        var bytes = candidates.reduce(Int64(0)) { $0 + $1.bytes }
        var count = candidates.count
        for candidate in candidates where bytes > byteBudget || count > artifactBudget {
            try files.removeItem(at: candidate.url)
            bytes -= candidate.bytes
            count -= 1
        }
        try files.createDirectory(at: artifactDirectory(for: manifest), withIntermediateDirectories: true)
    }

    func payloadURL(for manifest: VerifiedMediaManifest) -> URL {
        artifactDirectory(for: manifest).appending(path: "payload", directoryHint: .notDirectory)
    }

    func availablePieces(for manifest: VerifiedMediaManifest) throws -> IndexSet {
        let bitmap = try bitmap(for: manifest)
        var result = IndexSet()
        for index in 0..<manifest.pieceCount where Self.contains(index, in: bitmap) {
            result.insert(index)
        }
        return result
    }

    func contains(_ index: Int, manifest: VerifiedMediaManifest) throws -> Bool {
        guard index >= 0, index < manifest.pieceCount else { return false }
        return try Self.contains(index, in: bitmap(for: manifest))
    }

    func write(_ piece: VerifiedTransferPiece, manifest: VerifiedMediaManifest) throws {
        guard let range = manifest.range(for: piece.index) else { return }
        let payload = payloadURL(for: manifest)
        let files = FileManager.default
        if !files.fileExists(atPath: payload.path) {
            guard files.createFile(atPath: payload.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        }

        let handle = try FileHandle(forUpdating: payload)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(range.lowerBound))
        try handle.write(contentsOf: piece.bytes)
        try handle.synchronize()

        // Writing the payload first ensures an interruption leaves the new piece uncommitted.
        var updated = try bitmap(for: manifest)
        let byte = piece.index / 8
        updated[byte] |= Self.mask(for: piece.index)
        try Data(updated).write(to: mapURL(for: manifest), options: .atomic)
    }

    func invalidate(_ indices: IndexSet, manifest: VerifiedMediaManifest) throws {
        var updated = try bitmap(for: manifest)
        for index in indices where index >= 0 && index < manifest.pieceCount {
            updated[index / 8] &= ~Self.mask(for: index)
        }
        try Data(updated).write(to: mapURL(for: manifest), options: .atomic)
    }

    func discard(_ manifest: VerifiedMediaManifest) throws {
        let url = artifactDirectory(for: manifest)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private func artifactDirectory(for manifest: VerifiedMediaManifest) -> URL {
        directory.appending(path: Self.key(for: manifest), directoryHint: .isDirectory)
    }

    private func mapURL(for manifest: VerifiedMediaManifest) -> URL {
        artifactDirectory(for: manifest).appending(path: "committed", directoryHint: .notDirectory)
    }

    private func bitmap(for manifest: VerifiedMediaManifest) throws -> [UInt8] {
        let count = (manifest.pieceCount + 7) / 8
        let files = FileManager.default
        let map = mapURL(for: manifest)
        guard files.fileExists(atPath: payloadURL(for: manifest).path), files.fileExists(atPath: map.path) else {
            return [UInt8](repeating: 0, count: count)
        }
        let handle = try FileHandle(forReadingFrom: map)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: count + 1), data.count == count else {
            return [UInt8](repeating: 0, count: count)
        }
        return Array(data)
    }

    private static func contains(_ index: Int, in bitmap: [UInt8]) -> Bool {
        bitmap[index / 8] & mask(for: index) != 0
    }

    private static func mask(for index: Int) -> UInt8 { 1 << (index % 8) }

    private static func isArtifactDirectory(_ key: String) -> Bool {
        let components = key.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 2, components[0].utf8.count == 64,
              let size = Int(components[1]), size > 0 else { return false }
        return components[0].utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
