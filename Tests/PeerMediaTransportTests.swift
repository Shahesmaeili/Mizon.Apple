#if os(macOS) || os(iOS)
import Foundation
import Network
import Testing
@testable import MizonAppleCore

struct PeerMediaTransportTests {
    @Test func requestMatchesNetworkByteOrder() throws {
        let hash = Data(0..<32)
        let request = PeerMediaTransportRequest(sha256: hash, chunkSize: 0x0001_0203, index: 0x0405_0607)
        let encoded = try request.encode()
        #expect(encoded == Data("MZP1".utf8) + hash + Data([0, 1, 2, 3, 4, 5, 6, 7]))
        #expect(try PeerMediaTransportRequest.decode(encoded) == request)
    }

    @Test func requestRejectsInvalidFramingAndSizes() throws {
        let hash = Data(repeating: 3, count: 32)
        let request = PeerMediaTransportRequest(sha256: hash, chunkSize: 1, index: 0)
        let encoded = try request.encode()
        #expect(throws: PeerMediaTransportError.invalidRequest) {
            try PeerMediaTransportRequest.decode(Data(encoded.dropLast()))
        }
        #expect(throws: PeerMediaTransportError.invalidRequest) {
            try PeerMediaTransportRequest.decode(Data("MZP2".utf8) + encoded.dropFirst(4))
        }
        #expect(throws: PeerMediaTransportError.invalidRequest) {
            try PeerMediaTransportRequest.decode(encoded.prefix(36) + Data([0xFF, 0xFF, 0xFF, 0xFF]) + encoded.suffix(4))
        }
        #expect(throws: PeerMediaTransportError.invalidRequest) {
            try PeerMediaTransportRequest(sha256: hash, chunkSize: 1, index: -1).encode()
        }
        #expect(throws: PeerMediaTransportError.invalidRequest) {
            try PeerMediaTransportRequest(sha256: Data(hash.dropLast()), chunkSize: 1, index: 0).encode()
        }
    }

    @Test func listenerIdentitiesHaveDistinctCanonicalCertificatePins() throws {
        let first = try PeerMediaTransportIdentity()
        let second = try PeerMediaTransportIdentity()
        #expect(first.fingerprint != second.fingerprint)
        #expect(PeerMediaTransport.parseFingerprint(first.fingerprint)?.count == 32)
        #expect(PeerMediaTransport.parseFingerprint(String(repeating: "AA", count: 32)) == nil)
        #expect(PeerMediaTransport.parseFingerprint(first.fingerprint + "0") == nil)
    }

    @Test func directHostAndInvalidBonjourPinAreRejectedBeforeConnecting() async {
        let request = PeerMediaTransportRequest(sha256: Data(repeating: 1, count: 32), chunkSize: 1, index: 0)
        await #expect(throws: PeerMediaTransportError.invalidEndpoint) {
            try await PeerMediaTransport.fetchPiece(from: .hostPort(host: "127.0.0.1", port: 4040),
                fingerprint: String(repeating: "00", count: 32), request: request, expectedLength: 1)
        }
        await #expect(throws: PeerMediaTransportError.invalidFingerprint) {
            try await PeerMediaTransport.fetchPiece(from: .service(name: "Mizon-Test", type: "_mizon-peer._tcp",
                domain: "local.", interface: nil), fingerprint: "bad-pin", request: request, expectedLength: 1)
        }
    }
}
#endif
