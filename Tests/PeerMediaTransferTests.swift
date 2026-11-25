import CryptoKit
import Foundation
import MizonAPIClient
import Testing
@testable import MizonAppleCore

@Test
func peerMediaUsesSparsePeersAndFallsBackPerPiece() async throws {
    let root = try temporaryTransferFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let data = Data(0..<13)
    let manifest = try transferManifest(data, chunkSize: 4)
    let transfer = PeerMediaTransfer(partialDirectory: root.appending(path: "parts"))
    let destination = root.appending(path: "cache/song")
    let origin = PieceRequests()
    let providers = [
        PeerMediaChunkProvider(availablePieces: IndexSet([0, 2])) { index in
            bytes(of: data, at: index, manifest: manifest)
        },
        PeerMediaChunkProvider(availablePieces: IndexSet(integer: 1)) { _ in
            Data(repeating: 255, count: 4)
        }
    ]
    let url = try await transfer.download(manifest: manifest, origin: PeerMediaChunkProvider { index in
        await origin.record(index)
        return bytes(of: data, at: index, manifest: manifest)
    }, peers: providers, destination: destination)

    #expect(url == destination.standardizedFileURL)
    #expect(try Data(contentsOf: url) == data)
    #expect(await origin.recorded() == Set([1, 3]))
    #expect(try await transfer.verifiedPiece(3, from: manifest) == Data([12]))
    try await transfer.discard(manifest)
    #expect(try await transfer.verifiedPiece(3, from: manifest, completedFile: destination) == Data([12]))
}

@Test
func peerMediaStillProbesAfterAnAbsentPieceButDropsACorruptSource() async throws {
    let root = try temporaryTransferFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let data = Data(0..<4)
    let manifest = try transferManifest(data, chunkSize: 1)
    let transfer = PeerMediaTransfer(partialDirectory: root.appending(path: "parts"), maximumConcurrentChunks: 1)
    let attempted = PieceRequests()
    let peer = PeerMediaChunkProvider { index in
        await attempted.record(index)
        return index == 0 ? nil : Data([255])
    }

    let result = try await transfer.download(manifest: manifest, origin: PeerMediaChunkProvider { index in
        bytes(of: data, at: index, manifest: manifest)
    }, peers: [peer], destination: root.appending(path: "complete"))

    #expect(await attempted.recorded() == Set([0, 1]))
    #expect(try Data(contentsOf: result) == data)
}

@Test
func peerMediaKeepsVerifiedNoncontiguousPiecesAcrossCancellation() async throws {
    let root = try temporaryTransferFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let data = Data(0..<12)
    let manifest = try transferManifest(data, chunkSize: 4)
    let directory = root.appending(path: "parts")
    let transfer = PeerMediaTransfer(partialDirectory: directory, maximumConcurrentChunks: 2)
    let destination = root.appending(path: "complete")
    let attempts = PieceRequests()
    let job = Task {
        try await transfer.download(manifest: manifest, origin: PeerMediaChunkProvider { index in
            await attempts.record(index)
            if index != 1 { try await Task.sleep(for: .seconds(60)) }
            return bytes(of: data, at: index, manifest: manifest)
        }, peers: [], destination: destination)
    }
    defer { job.cancel() }
    try await waitForPiece(2, in: attempts)

    #expect(try await transfer.verifiedPieces(for: manifest) == IndexSet(integer: 1))
    #expect(try await transfer.verifiedPiece(1, from: manifest) == Data(4..<8))
    #expect(try await transfer.verifiedPiece(0, from: manifest) == nil)
    #expect(!FileManager.default.fileExists(atPath: destination.path))

    job.cancel()
    await #expect(throws: CancellationError.self) { try await job.value }

    let reopened = PeerMediaTransfer(partialDirectory: directory)
    let resumed = PieceRequests()
    _ = try await reopened.download(manifest: manifest, origin: PeerMediaChunkProvider { index in
        await resumed.record(index)
        return bytes(of: data, at: index, manifest: manifest)
    }, peers: [], destination: destination)
    #expect(await resumed.recorded() == Set([0, 2]))
    #expect(try Data(contentsOf: destination) == data)
}

@Test
func peerMediaCanStoreAndReadASparseOffsetBeyondFiveGiB() async throws {
    let root = try temporaryTransferFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let chunkSize = VerifiedMediaManifest.maximumPieceSize
    let tail = Data(repeating: 17, count: 31)
    let stride: Int64 = 5 * 1024 * 1024 * 1024 + Int64(chunkSize)
    let last = Int(stride / Int64(chunkSize))
    var pieceDigests = Data(repeating: 0, count: last * 32)
    pieceDigests.append(contentsOf: SHA256.hash(data: tail))
    let manifest = try #require(VerifiedMediaManifest(fileHash: String(repeating: "a", count: 64),
        fileSize: stride + Int64(tail.count), chunkSize: chunkSize, pieceSha256: pieceDigests))
    let transfer = PeerMediaTransfer(partialDirectory: root.appending(path: "parts"), maximumConcurrentChunks: 1)
    let origin = PieceRequests()
    let destination = root.appending(path: "complete")
    let job = Task {
        try await transfer.download(manifest: manifest, origin: PeerMediaChunkProvider { index in
            await origin.record(index)
            try await Task.sleep(for: .seconds(60))
            return nil
        }, peers: [PeerMediaChunkProvider(availablePieces: IndexSet(integer: last)) { _ in tail }],
        destination: destination)
    }
    defer { job.cancel() }
    try await waitForPiece(0, in: origin)

    #expect(manifest.range(for: last)?.lowerBound == stride)
    #expect(try await transfer.verifiedPieces(for: manifest) == IndexSet(integer: last))
    #expect(try await transfer.verifiedPiece(last, from: manifest) == tail)
    #expect(try await transfer.verifiedPiece(last + 1, from: manifest) == nil)
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    job.cancel()
    await #expect(throws: CancellationError.self) { try await job.value }
}

@Test
func peerMediaNeverPublishesInvalidOriginPiecesOrAWholeHashMismatch() async throws {
    let root = try temporaryTransferFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let data = Data([1, 2, 3, 4])
    let wrong = Data([4, 3, 2, 1])
    let directory = root.appending(path: "parts")
    let transfer = PeerMediaTransfer(partialDirectory: directory, maximumConcurrentChunks: 1)
    let destination = root.appending(path: "existing")
    try wrong.write(to: destination)
    let manifest = try transferManifest(data, chunkSize: 4)

    await #expect(throws: PeerMediaTransferError.invalidOriginPiece(0)) {
        try await transfer.download(manifest: manifest, origin: PeerMediaChunkProvider { _ in wrong },
                                    peers: [], destination: destination)
    }
    #expect(try await transfer.verifiedPieces(for: manifest).isEmpty)
    #expect(try await transfer.verifiedPiece(0, from: manifest, completedFile: destination) == nil)
    #expect(try Data(contentsOf: destination) == wrong)

    let inconsistent = try transferManifest(data, chunkSize: 4, fileHash: String(repeating: "b", count: 64))
    await #expect(throws: PeerMediaTransferError.fileIntegrityMismatch) {
        try await transfer.download(manifest: inconsistent, origin: PeerMediaChunkProvider { _ in data },
                                    peers: [], destination: destination)
    }
    #expect(try await transfer.verifiedPieces(for: inconsistent).isEmpty)
    #expect(try Data(contentsOf: destination) == wrong)
}

@Test
func peerMediaReusesAValidatedDestinationWithoutCreatingPartialFiles() async throws {
    let root = try temporaryTransferFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appending(path: "parts")
    let data = Data([1, 2, 3, 4])
    let manifest = try transferManifest(data, chunkSize: 3)
    let destination = root.appending(path: "existing")
    try data.write(to: destination)
    let transfer = PeerMediaTransfer(partialDirectory: directory)
    let result = try await transfer.download(manifest: manifest, origin: PeerMediaChunkProvider { _ in
        Issue.record("Existing cache incorrectly triggered an origin fetch")
        return nil
    }, peers: [], destination: destination)
    #expect(result == destination.standardizedFileURL)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
    #expect(try await transfer.verifiedPiece(1, from: manifest, completedFile: destination) == Data([4]))
}

@Test
func peerMediaServesAndReusesOnlyVerifiedLegacyPrefixPieces() async throws {
    let root = try temporaryTransferFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let data = Data(0..<15)
    let manifest = try transferManifest(data, chunkSize: 4)
    let directory = root.appending(path: "parts")
    let destination = root.appending(path: "existing")
    let legacyFile = destination.appendingPathExtension("part")
    var legacyData = Data(data.prefix(4))
    legacyData.append(Data(repeating: 255, count: 4))
    legacyData.append(data[8..<10])
    try legacyData.write(to: legacyFile)
    try Data(repeating: 254, count: data.count).write(to: destination)

    let transfer = PeerMediaTransfer(partialDirectory: directory)
    #expect(try await transfer.verifiedPiece(0, from: manifest, completedFile: destination) == Data(0..<4))
    #expect(try await transfer.verifiedPiece(1, from: manifest, completedFile: destination) == nil)
    #expect(try await transfer.verifiedPiece(2, from: manifest, completedFile: destination) == nil)
    #expect(try await transfer.verifiedPiece(3, from: manifest, completedFile: destination) == nil)
    #expect(!FileManager.default.fileExists(atPath: directory.path))

    let peers = PieceRequests()
    let origin = PieceRequests()
    let result = try await transfer.download(manifest: manifest, origin: PeerMediaChunkProvider { index in
        await origin.record(index)
        return bytes(of: data, at: index, manifest: manifest)
    }, peers: [PeerMediaChunkProvider(availablePieces: IndexSet(integer: 1)) { index in
        await peers.record(index)
        return bytes(of: data, at: index, manifest: manifest)
    }], destination: destination)

    #expect(await peers.recorded() == Set([1]))
    #expect(await origin.recorded() == Set([2, 3]))
    #expect(try Data(contentsOf: result) == data)
    #expect(try Data(contentsOf: legacyFile) == legacyData)
}

@Test
func peerMediaDoesNotReadASymlinkedLegacyPrefix() async throws {
    let root = try temporaryTransferFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let data = Data([1, 2, 3, 4])
    let manifest = try transferManifest(data, chunkSize: 4)
    let destination = root.appending(path: "cache")
    let target = root.appending(path: "unexpected")
    try data.write(to: target)
    try FileManager.default.createSymbolicLink(at: destination.appendingPathExtension("part"), withDestinationURL: target)

    let transfer = PeerMediaTransfer(partialDirectory: root.appending(path: "parts"))
    #expect(try await transfer.verifiedPiece(0, from: manifest, completedFile: destination) == nil)

    let requests = PieceRequests()
    let result = try await transfer.download(manifest: manifest, origin: PeerMediaChunkProvider { index in
        await requests.record(index)
        return data
    }, peers: [], destination: destination)
    #expect(await requests.recorded() == Set([0]))
    #expect(try Data(contentsOf: result) == data)
    #expect(try Data(contentsOf: target) == data)
}

@Test
func peerMediaRepairsCorruptPartialBytesWithoutChangingAnExistingCompletedFile() async throws {
    let root = try temporaryTransferFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appending(path: "parts")
    let data = Data(0..<12)
    let manifest = try transferManifest(data, chunkSize: 4)
    let transfer = PeerMediaTransfer(partialDirectory: directory, maximumConcurrentChunks: 1)
    let first = root.appending(path: "first")
    _ = try await transfer.download(manifest: manifest, origin: PeerMediaChunkProvider { index in
        bytes(of: data, at: index, manifest: manifest)
    }, peers: [], destination: first)

    let payload = PeerMediaPartialStore(directory: directory).payloadURL(for: manifest)
    let writable = try FileHandle(forWritingTo: payload)
    try writable.seek(toOffset: 4)
    try writable.write(contentsOf: Data(repeating: 255, count: 8))
    try writable.close()
    #expect(try await transfer.verifiedPiece(1, from: manifest) == nil)
    #expect(try Data(contentsOf: first) == data)

    let attempts = PieceRequests()
    let second = root.appending(path: "second")
    _ = try await transfer.download(manifest: manifest, origin: PeerMediaChunkProvider { index in
        await attempts.record(index)
        return bytes(of: data, at: index, manifest: manifest)
    }, peers: [], destination: second)
    #expect(await attempts.recorded() == Set([1, 2]))
    #expect(try Data(contentsOf: second) == data)
}

@Test
func peerMediaWaitsForTransferCapacityAndCancelsQueuedRequests() async throws {
    let root = try temporaryTransferFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let transfer = PeerMediaTransfer(partialDirectory: root.appending(path: "parts"))
    let firstGate = TransferGate()
    let secondGate = TransferGate()
    let requested = PieceRequests()
    let queued = PieceRequests()

    func start(_ id: Int, waitingOn gate: TransferGate?) throws -> Task<URL, any Error> {
        let url = root.appending(path: "cache-\(id)")
        let data = Data([UInt8(id)])
        let manifest = try transferManifest(data, chunkSize: 1)
        return Task {
            await queued.record(id)
            return try await transfer.download(manifest: manifest, origin: PeerMediaChunkProvider { _ in
                await requested.record(id)
                try await gate?.wait()
                return data
            }, peers: [], destination: url)
        }
    }

    let first = try start(1, waitingOn: firstGate)
    let second = try start(2, waitingOn: secondGate)
    defer {
        first.cancel()
        second.cancel()
    }
    try await waitForPiece(1, in: requested)
    try await waitForPiece(2, in: requested)

    let third = try start(3, waitingOn: nil)
    let cancelled = try start(4, waitingOn: nil)
    defer {
        third.cancel()
        cancelled.cancel()
    }
    try await waitForPiece(3, in: queued)
    try await waitForPiece(4, in: queued)
    cancelled.cancel()
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    #expect(await requested.recorded() == Set([1, 2]))

    await firstGate.release()
    _ = try await first.value
    let thirdFile = try await third.value
    #expect(try Data(contentsOf: thirdFile) == Data([3]))
    #expect(await requested.recorded() == Set([1, 2, 3]))
    await secondGate.release()
    _ = try await second.value
}

@Test
func peerMediaJoinsAnIdenticalDownloadAndKeepsCancellationIndependent() async throws {
    let root = try temporaryTransferFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let manifest = try transferManifest(Data([1]), chunkSize: 1)
    let transfer = PeerMediaTransfer(partialDirectory: root.appending(path: "parts"))
    let destination = root.appending(path: "complete")
    let requested = PieceRequests()
    let gate = TransferGate()
    let primary = Task {
        try await transfer.download(manifest: manifest, origin: PeerMediaChunkProvider { _ in
            await requested.record(0)
            try await gate.wait()
            return Data([1])
        }, peers: [], destination: destination)
    }
    defer { primary.cancel() }
    try await waitForPiece(0, in: requested)
    let unexpected = PeerMediaChunkProvider { _ in
        Issue.record("A follower must not start a second fetch")
        return nil
    }
    let follower = Task {
        try await transfer.download(manifest: manifest, origin: unexpected, peers: [], destination: destination)
    }
    let cancelled = Task {
        try await transfer.download(manifest: manifest, origin: unexpected, peers: [], destination: destination)
    }
    defer {
        follower.cancel()
        cancelled.cancel()
    }
    cancelled.cancel()
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    await gate.release()
    #expect(try await primary.value == destination.standardizedFileURL)
    #expect(try await follower.value == destination.standardizedFileURL)
}

private actor PieceRequests {
    private var requests = Set<Int>()

    func record(_ piece: Int) { requests.insert(piece) }
    func recorded() -> Set<Int> { requests }
}

private actor TransferGate {
    private var open = false

    func wait() async throws {
        while !open { try await Task.sleep(for: .milliseconds(10)) }
        try Task.checkCancellation()
    }

    func release() { open = true }
}

private func waitForPiece(_ piece: Int, in requests: PieceRequests) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while await !requests.recorded().contains(piece) && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(await requests.recorded().contains(piece))
}

private func transferManifest(_ data: Data, chunkSize: Int, fileHash: String? = nil) throws -> VerifiedMediaManifest {
    let hash = fileHash ?? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let pieces = Data(stride(from: 0, to: data.count, by: chunkSize).flatMap { offset in
        SHA256.hash(data: data[offset..<min(offset + chunkSize, data.count)])
    })
    return try #require(VerifiedMediaManifest(fileHash: hash, fileSize: Int64(data.count),
                                              chunkSize: chunkSize, pieceSha256: pieces))
}

private func bytes(of data: Data, at index: Int, manifest: VerifiedMediaManifest) -> Data? {
    guard let range = manifest.range(for: index) else { return nil }
    return Data(data[Int(range.lowerBound)...Int(range.upperBound)])
}

private func temporaryTransferFolder() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "mizon-peer-transfer-\(UUID())",
                                                                 directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
