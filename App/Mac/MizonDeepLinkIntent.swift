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
        let metadata = MizonDeepLinkResult.RequestMetadata(rawID: requestID, version: version)
        if let error = metadata.errorCode {
            response = .failure(requestID: metadata.requestID, code: error,
                                message: "The deep-link request metadata is invalid or its response version is unsupported.")
        } else {
            response = await MizonDeepLinkRouter.shared.result(for: link, requestID: metadata.requestID, version: version)
        }
        return .result(value: String(decoding: try response.encoded(), as: UTF8.self))
    }
}
#endif
