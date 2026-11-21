import CryptoKit
import Darwin
import Foundation
import MizonAPIClient

enum PeerMediaFileIntegrity {
    private static let readBuffer = 1024 * 1024

    static func read(_ range: ClosedRange<Int64>, from file: URL) throws -> Data? {
        guard let handle = try openRegularFile(file) else { return nil }
        defer { try? handle.close() }
        return try read(range, handle: handle)
    }

    @concurrent
    static func matches(_ file: URL, manifest: VerifiedMediaManifest) async throws -> Bool {
        try hash(file, manifest: manifest, copyTo: nil)
    }

    @concurrent
    static func invalidPieces(in file: URL, manifest: VerifiedMediaManifest) async throws -> IndexSet {
        guard let handle = try openRegularFile(file) else { return IndexSet(integersIn: 0..<manifest.pieceCount) }
        defer { try? handle.close() }
        var result = IndexSet()
        for index in 0..<manifest.pieceCount {
            try Task.checkCancellation()
            if let range = manifest.range(for: index), let data = try read(range, handle: handle),
               manifest.verify(data, at: index) { continue }
            result.insert(index)
        }
        return result
    }

    @concurrent
    static func publish(_ file: URL, to destination: URL, manifest: VerifiedMediaManifest) async throws {
        try Task.checkCancellation()
        let files = FileManager.default
        let folder = destination.deletingLastPathComponent()
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let staging = folder.appending(path: ".peer-media-\(UUID().uuidString).incomplete", directoryHint: .notDirectory)
        defer { try? files.removeItem(at: staging) }

        // The clone shares disk blocks where available and leaves the finished inode independent of repairs.
        if clonefile(file.path, staging.path, UInt32(CLONE_NOFOLLOW)) != 0 {
            guard files.createFile(atPath: staging.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
            let output = try FileHandle(forWritingTo: staging)
            defer { try? output.close() }
            guard try hash(file, manifest: manifest, copyTo: output) else {
                throw PeerMediaTransferError.fileIntegrityMismatch
            }
            try output.synchronize()
        }

        try Task.checkCancellation()
        guard Darwin.rename(staging.path, destination.path) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            throw POSIXError(code)
        }
    }

    private static func hash(_ file: URL, manifest: VerifiedMediaManifest, copyTo output: FileHandle?) throws -> Bool {
        try Task.checkCancellation()
        guard let handle = try openRegularFile(file) else { return false }
        defer { try? handle.close() }
        guard try handle.seekToEnd() == UInt64(manifest.fileSize) else { return false }
        try handle.seek(toOffset: 0)
        var hasher = SHA256()
        var remaining = manifest.fileSize
        while remaining > 0 {
            try Task.checkCancellation()
            guard let bytes = try handle.read(upToCount: Int(min(Int64(readBuffer), remaining))), !bytes.isEmpty else {
                return false
            }
            hasher.update(data: bytes)
            try output?.write(contentsOf: bytes)
            remaining -= Int64(bytes.count)
        }
        let extra = try handle.read(upToCount: 1)
        return extra?.isEmpty != false && Data(hasher.finalize()) == manifest.rawFileHash
    }

    private static func openRegularFile(_ file: URL) throws -> FileHandle? {
        guard file.isFileURL, FileManager.default.fileExists(atPath: file.path) else { return nil }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        do {
            return try FileHandle(forReadingFrom: file)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private static func read(_ range: ClosedRange<Int64>, handle: FileHandle) throws -> Data? {
        let length = Int(range.upperBound - range.lowerBound + 1)
        try handle.seek(toOffset: UInt64(range.lowerBound))
        guard let result = try handle.read(upToCount: length) else { return nil }
        if result.count == length { return result }
        var bytes = result
        while bytes.count < length {
            try Task.checkCancellation()
            guard let next = try handle.read(upToCount: length - bytes.count), !next.isEmpty else { return nil }
            bytes.append(next)
        }
        return bytes
    }
}
