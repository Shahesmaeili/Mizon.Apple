import Foundation
import Testing
@testable import MizonAppleCore

struct MizonDeepLinkParityTests {
    private struct Contract: Decodable {
        let protocolVersion: Int
        let requestId: UUID
        let routes: [Route]
        let invalidUris: [String]
    }

    private struct Route: Decodable {
        let routeKey: String
        let canonicalUri: String
        let inputs: [String]
        let requiresAuthentication: Bool
        let completionStage: MizonDeepLinkResult.Stage
        let timeoutSeconds: Int
        let publicId: UUID?
        let commentPublicId: UUID?
        let settingsSection: String?
        let searchQuery: String?
        let typedSearchQuery: String?
    }

    @Test func matchesWindowsURIAndResponseVectors() throws {
        let fixture = try #require(Bundle.module.url(forResource: "deep-links-v1", withExtension: "json"))
        let contract = try JSONDecoder().decode(Contract.self, from: Data(contentsOf: fixture))
        #expect(contract.protocolVersion == MizonDeepLinkResult.protocolVersion)

        for row in contract.routes {
            let link = try #require(MizonDeepLink(
                routeKey: row.routeKey, publicID: row.publicId, commentPublicID: row.commentPublicId,
                searchQuery: row.typedSearchQuery ?? row.searchQuery,
                settingsSection: row.settingsSection.flatMap(MizonDeepLink.SettingsSection.init(rawValue:))))
            #expect(link.canonicalURI == row.canonicalUri)
            #expect(link.requiresAuthentication == row.requiresAuthentication)
            #expect(link.responseTimeout == .seconds(row.timeoutSeconds))
            #expect(MizonDeepLinkResult.completionStage(for: link) == row.completionStage)
            for input in row.inputs {
                #expect(MizonDeepLink(rawValue: input) == link, Comment(rawValue: input))
            }

            let receipt = MizonDeepLinkResult.success(requestID: contract.requestId, route: link, stage: row.completionStage)
            let encoded = try receipt.encoded()
            let decoded = try #require(MizonDeepLinkResult(data: encoded, expectedRequestID: contract.requestId))
            let payload = try #require(decoded.data)
            #expect(decoded.success && decoded.code == row.completionStage.rawValue)
            #expect(payload.destination == row.routeKey)
            #expect(payload.uri == row.canonicalUri)
            #expect(payload.completionStage == row.completionStage)
            #expect(payload.publicID == row.publicId)
            #expect(payload.commentPublicID == row.commentPublicId)
            #expect(payload.settingsSection == row.settingsSection)
            #expect(MizonDeepLinkResult(data: encoded, expectedRequestID: UUID()) == nil)
        }

        for input in contract.invalidUris {
            #expect(MizonDeepLink(rawValue: input) == nil, Comment(rawValue: input))
        }
    }

    @Test func matchesWindowsMetadataErrorPrecedence() throws {
        let rawID = "882e51dc-a69f-4410-98fc-d46eff3e8e11"
        let id = try #require(UUID(uuidString: rawID))
        for value in [rawID, rawID.replacingOccurrences(of: "-", with: ""), " {\(rawID)} ", "(\(rawID))"] {
            let metadata = MizonDeepLinkResult.RequestMetadata(rawID: value, version: 1)
            #expect(metadata.requestID == id && metadata.errorCode == nil)
        }
        let unsupported = MizonDeepLinkResult.RequestMetadata(rawID: rawID, version: 2)
        #expect(unsupported.requestID == id && unsupported.errorCode == "unsupported_version")
        let invalid = MizonDeepLinkResult.RequestMetadata(rawID: "00000000-0000-0000-0000-000000000000", version: 1)
        #expect(invalid.errorCode == "invalid_request")
        #expect(MizonDeepLinkResult.RequestMetadata(rawID: "invalid", version: 2).errorCode == "unsupported_version")
        #expect(MizonDeepLinkResult.RequestMetadata(rawID: nil, version: 1).errorCode == nil)
    }
}
