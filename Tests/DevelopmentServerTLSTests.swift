import Foundation
import Testing
@testable import MizonAppleCore

struct DevelopmentServerTLSTests {
    @Test func requiresExactOriginAndLeaf() throws {
        let hash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        let pin = try #require(DevelopmentServerTLS(origin: "https://fixture.local:5128", leafSHA256: hash))
        #expect(pin.matches(host: "FIXTURE.LOCAL", port: 5128))
        #expect(!pin.matches(host: "other.fixture.local", port: 5128))
        #expect(!pin.matches(host: "fixture.local", port: 443))
        #expect(pin.matches(certificateDER: Data("abc".utf8)))
        #expect(!pin.matches(certificateDER: Data("abd".utf8)))
    }

    @Test func absentOrMalformedConfigurationKeepsSystemTrust() {
        let hash = String(repeating: "a", count: 64)
        #expect(DevelopmentServerTLS(origin: "", leafSHA256: hash) == nil)
        #expect(DevelopmentServerTLS(origin: "http://fixture.local", leafSHA256: hash) == nil)
        #expect(DevelopmentServerTLS(origin: "https://fixture.local/path", leafSHA256: hash) == nil)
        #expect(DevelopmentServerTLS(origin: "https://fixture.local", leafSHA256: "bad-pin") == nil)
    }
}
