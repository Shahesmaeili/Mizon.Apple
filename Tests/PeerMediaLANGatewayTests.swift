#if os(macOS)
import CryptoKit
import Foundation
import MizonAPI
import MizonAPIClient
import Testing
@testable import MizonAppleCore

struct PeerMediaLANGatewayTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MIZON_PEER_LAN_TEST"] == "1"),
          .timeLimit(.minutes(1)))
    func composesTwoSparsePeersAndTheOriginOverNativeBonjourTLS() async throws {
        let directory = URL.temporaryDirectory.appending(path: "Mizon-LAN-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = AuthSession(accessToken: "local-fixture", refreshToken: "", sessionPublicId: UUID(),
                                  clientPublicId: UUID(), identifier: "fixture",
                                  server: URL(string: "https://mizon-peer-smoke.invalid")!)
        let pieces = (0..<4).map { Data(repeating: UInt8($0 + 10), count: 32_768) }
        let source = pieces.reduce(into: Data(), { $0.append($1) })
        let digest = SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined()
        let table = pieces.reduce(into: Data(), { $0.append(contentsOf: SHA256.hash(data: $1)) })
        let manifest = try #require(VerifiedMediaManifest(fileHash: digest, fileSize: Int64(source.count),
                                                         chunkSize: pieces[0].count, pieceSha256: table))
        let access = NearbyMediaAccess(api: MizonApi(), session: session, cacheRoot: directory)
        let firstParts = directory.appending(path: "seed-a")
        let secondParts = directory.appending(path: "seed-b")
        let first = NearbyDiscoveryService(partialDirectory: firstParts)
        let second = NearbyDiscoveryService(partialDirectory: secondParts)
        let receiver = NearbyDiscoveryService(partialDirectory: directory.appending(path: "receiver"))
        let firstID = UUID()
        let secondID = UUID()
        let receiverID = UUID()
        let firstEvents = await first.start(advertising: peer(firstID), mediaAccess: access)
        let secondEvents = await second.start(advertising: peer(secondID), mediaAccess: access)
        let receiverEvents = await receiver.start(advertising: peer(receiverID), mediaAccess: access)
        let listeners = [first, second, receiver]
        do {
            try await checkReady(firstEvents, peers: [secondID, receiverID])
            try await checkReady(secondEvents, peers: [firstID, receiverID])
            try await checkReady(receiverEvents, peers: [firstID, secondID])
            let mediaID = UUID()

            // The two sources fail before completing, so neither has a publishable file.
            let firstDestination = directory.appending(path: "source-a.bin")
            let secondDestination = directory.appending(path: "source-b.bin")
            try await seed(firstParts, piece: 0, manifest: manifest, pieces: pieces, destination: firstDestination)
            try await seed(secondParts, piece: 1, manifest: manifest, pieces: pieces, destination: secondDestination)
            await first.offerVerifiedMedia(manifest, mediaID: mediaID, destination: firstDestination, sessionID: session.sessionPublicId)
            await second.offerVerifiedMedia(manifest, mediaID: mediaID, destination: secondDestination, sessionID: session.sessionPublicId)
            let calls = OriginPieceCalls()
            let destination = directory.appending(path: "result.bin")
            let result = try await receiver.downloadPeerMedia(manifest, mediaID: mediaID, destination: destination,
                                                              sessionID: session.sessionPublicId, origin: PeerMediaChunkProvider { index in
                await calls.record(index)
                return pieces[index]
            })
            #expect(result == destination)
            #expect(try Data(contentsOf: result) == source)
            #expect(await calls.indices.sorted() == [2, 3])
        } catch {
            for listener in listeners { await listener.stop() }
            throw error
        }
        for listener in listeners { await listener.stop() }
    }

    private func peer(_ id: UUID) -> NearbyPresenceAdvertisement {
        .init(id: id, platform: .macOS, appVersion: "peer-fixture", deviceName: "Mizon LAN fixture")
    }

    private func seed(_ partialDirectory: URL, piece: Int, manifest: VerifiedMediaManifest,
                      pieces: [Data], destination: URL) async throws {
        let transfer = PeerMediaTransfer(partialDirectory: partialDirectory)
        do {
            _ = try await transfer.download(manifest: manifest, origin: PeerMediaChunkProvider { index in
                if index == piece { return pieces[index] }
                try await Task.sleep(for: .milliseconds(350))
                throw FixtureError.originUnavailable
            }, peers: [], destination: destination)
            throw FixtureError.unexpectedCompleteSeed
        } catch FixtureError.originUnavailable {}
        #expect(try await transfer.verifiedPieces(for: manifest) == IndexSet(integer: piece))
    }

    private func checkReady(_ stream: AsyncStream<NearbyDiscoveryEvent>, peers: Set<UUID>) async throws {
        let ready = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await event in stream {
                    if case .peers(let found) = event {
                        let mediaPeers = found.filter { $0.advertisement.mediaCertificateSHA256 != nil }
                        if peers.isSubset(of: Set(mediaPeers.map(\.id))) { return true }
                    }
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(6))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
        guard ready else { throw FixtureError.missingPeers }
    }

    private enum FixtureError: Error { case originUnavailable, unexpectedCompleteSeed, missingPeers }
}

private actor OriginPieceCalls {
    private(set) var indices: [Int] = []
    func record(_ index: Int) { indices.append(index) }
}
#endif
