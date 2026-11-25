import Foundation

/// The Windows v1 navigation receipt, independent of how each platform delivers it.
public struct MizonDeepLinkResult: Codable, Equatable, Sendable {
    public enum Stage: String, Codable, Sendable {
        case opened, completed
    }

    public struct Payload: Codable, Equatable, Sendable {
        public let destination: String
        public let uri: String
        public let completionStage: Stage
        public let publicID: UUID?
        public let commentPublicID: UUID?
        public let settingsSection: String?

        fileprivate init(route: MizonDeepLink, stage: Stage) {
            destination = route.routeKey
            uri = route.canonicalURI
            completionStage = stage
            publicID = route.publicID
            commentPublicID = route.commentPublicID
            settingsSection = route.settingsSection?.rawValue
        }

        private enum CodingKeys: String, CodingKey {
            case destination, uri, completionStage, settingsSection
            case publicID = "publicId"
            case commentPublicID = "commentPublicId"
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(destination, forKey: .destination)
            try container.encode(uri, forKey: .uri)
            try container.encode(completionStage, forKey: .completionStage)
            try container.encodeIfPresent(publicID?.uuidString.lowercased(), forKey: .publicID)
            try container.encodeIfPresent(commentPublicID?.uuidString.lowercased(), forKey: .commentPublicID)
            try container.encodeIfPresent(settingsSection, forKey: .settingsSection)
        }

        fileprivate var isValid: Bool {
            guard let route = MizonDeepLink(rawValue: uri) else { return false }
            return route.routeKey == destination && route.publicID == publicID && route.commentPublicID == commentPublicID
                && route.settingsSection?.rawValue == settingsSection
        }
    }

    public enum ValidationError: Error { case invalidResponse }

    public static let responseKey = "mizon.response"
    public static let requestIDKey = "mizon.requestId"
    public static let versionKey = "mizon.responseVersion"
    public static let protocolVersion = 1
    public static let maximumJSONBytes = 16 * 1_024

    public let version: Int
    public let requestID: UUID
    public let success: Bool
    public let code: String
    public let message: String
    public let data: Payload?

    private init(requestID: UUID, success: Bool, code: String, message: String, data: Payload? = nil) {
        version = Self.protocolVersion
        self.requestID = requestID
        self.success = success
        self.code = code
        self.message = message
        self.data = data
    }

    public static func success(requestID: UUID, route: MizonDeepLink, stage: Stage) -> Self {
        let message = switch stage {
        case .opened: "The destination was opened; its content may still be loading."
        case .completed: "The requested destination operation completed."
        }
        let result = Self(requestID: requestID, success: true, code: stage.rawValue,
                          message: message, data: .init(route: route, stage: stage))
        return result.isValid ? result : invalidResult(requestID: requestID)
    }

    public static func failure(requestID: UUID, code: String, message: String) -> Self {
        let result = Self(requestID: requestID, success: false, code: code, message: message)
        return result.isValid ? result : invalidResult(requestID: requestID)
    }

    private static func invalidResult(requestID: UUID) -> Self {
        Self(requestID: requestID, success: false, code: "invalid_result",
             message: "The destination returned an invalid response.")
    }

    public func encoded() throws -> Data {
        guard isValid else { throw ValidationError.invalidResponse }
        let encoded = try JSONEncoder().encode(self)
        guard (1...Self.maximumJSONBytes).contains(encoded.count) else { throw ValidationError.invalidResponse }
        return encoded
    }

    public init?(data: Data, expectedRequestID: UUID) {
        guard expectedRequestID != MizonDeepLink.emptyID, (1...Self.maximumJSONBytes).contains(data.count),
              !data.contains(0), String(data: data, encoding: .utf8) != nil, Self.hasKnownUniqueKeys(data),
              let result = try? JSONDecoder().decode(Self.self, from: data),
              result.requestID == expectedRequestID, result.isValid else { return nil }
        self = result
    }

    private enum CodingKeys: String, CodingKey {
        case version, success, code, message, data
        case requestID = "requestId"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(requestID.uuidString.lowercased(), forKey: .requestID)
        try container.encode(success, forKey: .success)
        try container.encode(code, forKey: .code)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(data, forKey: .data)
    }

    private var isValid: Bool {
        version == Self.protocolVersion && requestID != MizonDeepLink.emptyID
            && (1...64).contains(code.utf8.count) && code.utf8.allSatisfy(Self.isCodeByte)
            && message.utf16.count <= 512 && !MizonDeepLink.trimWhitespace(message).isEmpty
            && MizonDeepLink.hasNoControlCharacters(message)
            && data?.isValid != false && (data == nil || success)
    }

    private static func isCodeByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 45, 48...57, 95, 97...122: true
        default: false
        }
    }

    // Foundation decodes known fields but skips unknown keys and accepts duplicates.
    // Inspect member names before decoding to match the Windows v1 transport rules.
    private static func hasKnownUniqueKeys(_ data: Data) -> Bool {
        let rootKeys: Set<String> = ["version", "requestId", "success", "code", "message", "data"]
        let payloadKeys: Set<String> = ["destination", "uri", "completionStage", "publicId",
                                        "commentPublicId", "settingsSection"]
        let bytes = Array(data)
        var scopes: [Set<String>] = []
        var index = 0
        while index < bytes.count {
            switch bytes[index] {
            case 123: // {
                guard scopes.count < 2 else { return false }
                scopes.append([])
                index += 1
            case 125: // }
                guard !scopes.isEmpty else { return false }
                scopes.removeLast()
                index += 1
            case 91, 93: // [ ]
                return false
            case 34: // "
                let start = index
                index += 1
                while index < bytes.count, bytes[index] != 34 {
                    index += bytes[index] == 92 ? 2 : 1
                }
                guard index < bytes.count else { return false }
                index += 1
                let end = index
                while index < bytes.count, Self.isJSONWhitespace(bytes[index]) { index += 1 }
                if index < bytes.count, bytes[index] == 58 {
                    guard let scope = scopes.indices.last, end - start <= 128,
                          let name = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<end])),
                          (scope == 0 ? rootKeys : payloadKeys).contains(name),
                          scopes[scope].insert(name).inserted else { return false }
                }
            default:
                index += 1
            }
        }
        return scopes.isEmpty
    }

    private static func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == 32 || byte == 9 || byte == 10 || byte == 13
    }
}
