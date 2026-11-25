#if os(macOS) || os(iOS)
import AppIntents
import Foundation
import MizonAppleCore
import MizonAppleUI

struct OpenMizonLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Mizon Link"
    static let description = IntentDescription("Opens a Mizon link and returns its versioned JSON result.")
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Mizon Link")
    var link: String

    @Parameter(title: "Request ID")
    var requestID: String?

    @Parameter(title: "Response Version")
    var responseVersion: Int?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let response: MizonDeepLinkResult
        let version = responseVersion ?? MizonDeepLinkResult.protocolVersion
        if let requestID {
            if let id = UUID(uuidString: requestID), id.uuidString != "00000000-0000-0000-0000-000000000000" {
                response = await MizonDeepLinkRouter.shared.result(for: link, requestID: id, version: version)
            } else {
                response = .failure(requestID: UUID(), code: "invalid_request", message: "The request ID must be a nonzero UUID.")
            }
        } else {
            response = await MizonDeepLinkRouter.shared.result(for: link, version: version)
        }
        return .result(value: String(decoding: try response.encoded(), as: UTF8.self))
    }
}
#endif
