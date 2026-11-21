#if os(macOS) || os(iOS) || os(watchOS)
import CryptoKit
import Foundation
import Network
import Security
import Synchronization

final class PeerMediaTransportIdentity: Sendable {
    private let identity: Mutex<sec_identity_t>
    let fingerprint: String

    init() throws {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            // Select the modern implementation on macOS while keeping the key in memory.
            kSecUseDataProtectionKeychain: true,
            kSecPrivateKeyAttrs: [kSecAttrIsPermanent: false],
        ]
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, nil),
              let publicKey = SecKeyCopyPublicKey(key),
              let publicPoint = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?,
              publicPoint.count == 65, publicPoint.first == 4 else {
            throw PeerMediaTransportError.identityUnavailable
        }
        let der = try Self.makeCertificate(key: key, publicPoint: publicPoint)
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData),
              let secIdentity = SecIdentityCreate(nil, certificate, key),
              let tlsIdentity = sec_identity_create(secIdentity) else {
            throw PeerMediaTransportError.identityUnavailable
        }
        identity = Mutex(tlsIdentity)
        fingerprint = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }

    func listenerParameters() -> NWParameters {
        let options = PeerMediaTransport.tlsOptions()
        identity.withLock { sec_protocol_options_set_local_identity(options.securityProtocolOptions, $0) }
        return PeerMediaTransport.parameters(for: options)
    }

    private static func makeCertificate(key: SecKey, publicPoint: Data, now: Date = Date()) throws -> Data {
        // RFC 5280 self-signed v3 leaf. Security.framework creates both the key and its signature.
        let signatureAlgorithm = DER.sequence(DER.objectID([0x2A, 0x86, 0x48, 0xCE, 0x3D, 4, 3, 2]))
        let name = DER.sequence(DER.element(0x31, DER.sequence(
            DER.objectID([0x55, 4, 3]) + DER.element(0x0C, Data("Mizon Peer Media".utf8))
        )))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        func certificateTime(_ date: Date) -> Data {
            let useUTCTime = (1950...2049).contains(formatter.calendar.component(.year, from: date))
            formatter.dateFormat = useUTCTime ? "yyMMddHHmmss'Z'" : "yyyyMMddHHmmss'Z'"
            return DER.element(useUTCTime ? 0x17 : 0x18, Data(formatter.string(from: date).utf8))
        }
        let validity = DER.sequence(
            certificateTime(now.addingTimeInterval(-300)) +
            certificateTime(now.addingTimeInterval(30 * 24 * 60 * 60))
        )

        var serial = [UInt8](repeating: 0, count: 16)
        let randomStatus = serial.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard randomStatus == errSecSuccess else { throw PeerMediaTransportError.identityUnavailable }
        serial[0] = (serial[0] & 0x3F) | 0x40

        let keyAlgorithm = DER.sequence(DER.objectID([0x2A, 0x86, 0x48, 0xCE, 0x3D, 2, 1]) +
                                        DER.objectID([0x2A, 0x86, 0x48, 0xCE, 0x3D, 3, 1, 7]))
        let publicKeyInfo = DER.sequence(keyAlgorithm + DER.element(0x03, Data([0]) + publicPoint))
        let basicConstraints = DER.extensionValue([0x55, 0x1D, 0x13], DER.sequence(Data()), critical: true)
        let keyUsage = DER.extensionValue([0x55, 0x1D, 0x0F], DER.element(0x03, Data([7, 0x80])), critical: true)
        let serverAuth = DER.extensionValue([0x55, 0x1D, 0x25],
            DER.sequence(DER.objectID([0x2B, 6, 1, 5, 5, 7, 3, 1])))
        let extensions = DER.element(0xA3, DER.sequence(basicConstraints + keyUsage + serverAuth))
        let encodedVersion = DER.element(0xA0, DER.element(0x02, Data([2])))
        let tbs = DER.sequence(encodedVersion + DER.element(0x02, Data(serial)) +
                               signatureAlgorithm + name + validity + name + publicKeyInfo + extensions)
        guard let signature = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, tbs as CFData, nil) as Data? else {
            throw PeerMediaTransportError.identityUnavailable
        }
        return DER.sequence(tbs + signatureAlgorithm + DER.element(0x03, Data([0]) + signature))
    }

    private enum DER {
        static func objectID(_ bytes: [UInt8]) -> Data { element(0x06, Data(bytes)) }
        static func sequence(_ body: Data) -> Data { element(0x30, body) }

        static func extensionValue(_ identifier: [UInt8], _ value: Data, critical: Bool = false) -> Data {
            let criticalFlag = critical ? element(0x01, Data([0xFF])) : Data()
            return sequence(objectID(identifier) + criticalFlag + element(0x04, value))
        }

        static func element(_ tag: UInt8, _ body: Data) -> Data {
            let length: Data
            if body.count < 128 {
                length = Data([UInt8(body.count)])
            } else {
                var count = body.count
                var bytes = [UInt8]()
                while count > 0 {
                    bytes.append(UInt8(truncatingIfNeeded: count))
                    count >>= 8
                }
                length = Data([0x80 | UInt8(bytes.count)] + bytes.reversed())
            }
            return Data([tag]) + length + body
        }
    }
}
#endif
