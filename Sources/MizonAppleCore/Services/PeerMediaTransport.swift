#if os(macOS) || os(iOS) || os(watchOS)
import CryptoKit
import Foundation
import Network
import Security
import Synchronization

enum PeerMediaTransportError: Error, Equatable {
    case busy
    case identityUnavailable
    case invalidEndpoint
    case invalidFingerprint
    case invalidRequest
    case invalidResponse
    case timedOut
}

struct PeerMediaTransportRequest: Equatable, Sendable {
    let sha256: Data
    let chunkSize: Int
    let index: Int

    static let maximumChunkSize = 4 * 1024 * 1024
    static let wireLength = 44
    private static let magic = Data("MZP1".utf8)

    func encode() throws -> Data {
        guard sha256.count == SHA256.byteCount, (1...Self.maximumChunkSize).contains(chunkSize),
              let wireIndex = UInt32(exactly: index) else { throw PeerMediaTransportError.invalidRequest }
        return Self.magic + sha256 + PeerMediaTransport.wireInteger(UInt32(chunkSize)) +
            PeerMediaTransport.wireInteger(wireIndex)
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count == wireLength, data.prefix(magic.count) == magic else {
            throw PeerMediaTransportError.invalidRequest
        }
        let size = Int(PeerMediaTransport.readWireInteger(data, at: 36))
        guard (1...maximumChunkSize).contains(size) else { throw PeerMediaTransportError.invalidRequest }
        return Self(sha256: Data(data.dropFirst(4).prefix(SHA256.byteCount)), chunkSize: size,
                    index: Int(PeerMediaTransport.readWireInteger(data, at: 40)))
    }
}

enum PeerMediaTransport {
    private static let queue = DispatchQueue(label: "app.mizon.peer-media", qos: .utility)
    private static let outgoingCount = Mutex(0)
    private static let maximumOutgoing = 8

    static func fetchPiece(from endpoint: NWEndpoint, fingerprint: String, request: PeerMediaTransportRequest,
                           expectedLength: Int) async throws -> Data? {
        guard case .service(let name, let type, let domain, _) = endpoint,
              !name.isEmpty,
              type == NearbyAdvertisementCodec.serviceType || type == NearbyAdvertisementCodec.serviceType + ".",
              domain.lowercased() == NearbyAdvertisementCodec.domain else {
            throw PeerMediaTransportError.invalidEndpoint
        }
        return try await fetch(from: endpoint, fingerprint: fingerprint, request: request,
                               expectedLength: expectedLength, timeout: .seconds(8))
    }

    private static func fetch(from endpoint: NWEndpoint, fingerprint: String, request: PeerMediaTransportRequest,
                              expectedLength: Int, timeout: Duration) async throws -> Data? {
        let requestData = try request.encode()
        guard (1...request.chunkSize).contains(expectedLength) else { throw PeerMediaTransportError.invalidRequest }
        guard let pin = parseFingerprint(fingerprint) else { throw PeerMediaTransportError.invalidFingerprint }
        try Task.checkCancellation()
        let admitted = outgoingCount.withLock { count in
            guard count < maximumOutgoing else { return false }
            count += 1
            return true
        }
        guard admitted else { throw PeerMediaTransportError.busy }
        defer { outgoingCount.withLock { $0 -= 1 } }

        let tls = tlsOptions()
        sec_protocol_options_set_peer_authentication_required(tls.securityProtocolOptions, true)
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, wrappedTrust, completion in
            let trust = sec_trust_copy_ref(wrappedTrust).takeRetainedValue()
            guard SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
                  let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
                  let leaf = chain.first else {
                completion(false)
                return
            }
            let digest = SHA256.hash(data: SecCertificateCopyData(leaf) as Data)
            completion(digest.elementsEqual(pin))
        }, queue)
        let connection = NWConnection(to: endpoint, using: parameters(for: tls))
        return try await run(connection, timeout: timeout) {
            try await send(requestData, to: connection)
            let header = try await receive(4, from: connection)
            let length = Int(readWireInteger(header, at: 0))
            if length == 0 { return nil }
            guard length == expectedLength else { throw PeerMediaTransportError.invalidResponse }
            return try await receive(length, from: connection)
        }
    }

    static func tlsOptions() -> NWProtocolTLS.Options {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        // A new handshake must prove possession of the pinned leaf key on every connection.
        sec_protocol_options_set_tls_resumption_enabled(tls.securityProtocolOptions, false)
        sec_protocol_options_set_tls_tickets_enabled(tls.securityProtocolOptions, false)
        return tls
    }

    static func parameters(for tls: NWProtocolTLS.Options) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        return NWParameters(tls: tls, tcp: tcp)
    }

    static func wireInteger(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    static func readWireInteger(_ data: Data, at offset: Int) -> UInt32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian }
    }

    static func parseFingerprint(_ string: String) -> [UInt8]? {
        let digits = Array(string.utf8.prefix(65))
        guard digits.count == SHA256.byteCount * 2 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(SHA256.byteCount)
        for offset in stride(from: 0, to: digits.count, by: 2) {
            guard let high = hexadecimal(digits[offset]), let low = hexadecimal(digits[offset + 1]) else { return nil }
            bytes.append(high << 4 | low)
        }
        return bytes
    }

    private static func hexadecimal(_ digit: UInt8) -> UInt8? {
        switch digit {
        case 48...57: digit - 48
        case 97...102: digit - 87
        default: nil
        }
    }

    fileprivate static func run<Value: Sendable>(_ connection: NWConnection, timeout: Duration,
                                                 exchange: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            defer { connection.cancel() }
            return try await withThrowingTaskGroup(of: Value.self) { group in
                group.addTask {
                    try await open(connection)
                    try Task.checkCancellation()
                    return try await exchange()
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw PeerMediaTransportError.timedOut
                }
                defer { group.cancelAll() }
                do {
                    guard let value = try await group.next() else { throw CancellationError() }
                    try Task.checkCancellation()
                    return value
                } catch {
                    connection.forceCancel()
                    throw error
                }
            }
        } onCancel: {
            connection.forceCancel()
        }
    }

    private static func open(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let pending = Mutex(Optional(continuation))
            connection.stateUpdateHandler = { state in
                let error: (any Error)?
                switch state {
                case .ready: error = nil
                case .waiting(let failure), .failed(let failure): error = failure
                case .cancelled: error = CancellationError()
                default: return
                }
                let result = pending.withLock { continuation in
                    defer { continuation = nil }
                    return continuation
                }
                guard let result else { return }
                connection.stateUpdateHandler = nil
                if let error { result.resume(throwing: error) }
                else { result.resume() }
            }
            if case .cancelled = connection.state {
                connection.stateUpdateHandler?(.cancelled)
            } else {
                connection.start(queue: queue)
            }
        }
    }

    fileprivate static func send(_ data: Data, to connection: NWConnection, final: Bool = false) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: data, contentContext: final ? .finalMessage : .defaultMessage,
                            isComplete: true, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    fileprivate static func receive(_ count: Int, from connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, data.count == count { continuation.resume(returning: data) }
                else { continuation.resume(throwing: PeerMediaTransportError.invalidResponse) }
            }
        }
    }
}

final class PeerMediaTransportServer: Sendable {
    typealias ReadPiece = @Sendable (PeerMediaTransportRequest) async -> Data?
    private let readPiece: ReadPiece
    private let state = Mutex(State())
    private static let maximumIncoming = 8

    private struct State {
        var closed = false
        var requests: [UUID: Request] = [:]
    }

    private struct Request: Sendable {
        let connection: NWConnection
        let task: Task<Void, Never>
    }

    init(readPiece: @escaping ReadPiece) { self.readPiece = readPiece }

    deinit { close() }

    func accept(_ connection: NWConnection) {
        let admitted = state.withLock { state in
            guard !state.closed, state.requests.count < Self.maximumIncoming else { return false }
            let id = UUID()
            let readPiece = self.readPiece
            let task = Task.detached(priority: .utility) { [weak self] in
                defer {
                    _ = self?.state.withLock { $0.requests.removeValue(forKey: id) }
                }
                do {
                    try await PeerMediaTransport.run(connection, timeout: .seconds(8)) {
                        let data = try await PeerMediaTransport.receive(PeerMediaTransportRequest.wireLength, from: connection)
                        let request = try PeerMediaTransportRequest.decode(data)
                        let piece = await readPiece(request)
                        try Task.checkCancellation()
                        guard let piece, (1...request.chunkSize).contains(piece.count) else {
                            try await PeerMediaTransport.send(PeerMediaTransport.wireInteger(0), to: connection, final: true)
                            return
                        }
                        try await PeerMediaTransport.send(PeerMediaTransport.wireInteger(UInt32(piece.count)), to: connection)
                        try await PeerMediaTransport.send(piece, to: connection, final: true)
                    }
                } catch {
                    // A failed transfer closes this connection; the client's authoritative source may retry.
                }
            }
            state.requests[id] = Request(connection: connection, task: task)
            return true
        }
        if !admitted { connection.forceCancel() }
    }

    func close() {
        let active = state.withLock { state in
            state.closed = true
            defer { state.requests.removeAll() }
            return Array(state.requests.values)
        }
        for request in active {
            request.connection.forceCancel()
            request.task.cancel()
        }
    }
}
#endif
