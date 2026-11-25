import CryptoKit
import Foundation
import Security

/// A local build may pin a development certificate for one HTTPS origin.
struct DevelopmentServerTLS: Sendable {
    let host: String
    let port: Int
    private let leafSHA256: String

    init?(origin: String, leafSHA256: String) {
        guard let url = URLComponents(string: origin), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else { return nil }
        let port = url.port ?? 443
        let fingerprint = leafSHA256.lowercased()
        guard (1...65_535).contains(port), fingerprint.utf8.count == 64,
              fingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        self.host = host.lowercased()
        self.port = port
        self.leafSHA256 = fingerprint
    }

    init?(bundle: Bundle) {
        guard let origin = bundle.object(forInfoDictionaryKey: "MizonDevelopmentTLSOrigin") as? String,
              let digest = bundle.object(forInfoDictionaryKey: "MizonDevelopmentTLSLeafSHA256") as? String else { return nil }
        self.init(origin: origin, leafSHA256: digest)
    }

    func makeSession() -> URLSession {
        URLSession(configuration: .default, delegate: DevelopmentServerTrustDelegate(pin: self), delegateQueue: nil)
    }

    func matches(host: String, port: Int) -> Bool {
        self.host == host.lowercased() && self.port == port
    }

    func matches(certificateDER: Data) -> Bool {
        let digest = SHA256.hash(data: certificateDER).map { String(format: "%02x", $0) }.joined()
        return digest == leafSHA256
    }
}

private final class DevelopmentServerTrustDelegate: NSObject, URLSessionDelegate, Sendable {
    let pin: DevelopmentServerTLS

    init(pin: DevelopmentServerTLS) {
        self.pin = pin
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let protection = challenge.protectionSpace
        guard protection.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              pin.matches(host: protection.host, port: protection.port) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let trust = protection.serverTrust,
              SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
              let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first,
              pin.matches(certificateDER: SecCertificateCopyData(leaf) as Data),
              SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, pin.host as CFString)) == errSecSuccess,
              SecTrustSetAnchorCertificates(trust, [leaf] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
