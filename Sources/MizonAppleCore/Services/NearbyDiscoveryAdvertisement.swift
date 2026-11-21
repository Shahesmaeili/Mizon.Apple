import Foundation

public enum NearbyPeerPlatform: String, CaseIterable, Sendable {
    case windows
    case macOS = "macos"
    case iOS = "ios"
    case android
    case watchOS = "watchos"
    case wearOS = "wearos"
}

public struct NearbyPresenceAdvertisement: Equatable, Sendable {
    public let id: UUID
    public let platform: NearbyPeerPlatform
    public let appVersion: String
    public let deviceName: String
    public let account: String?
    public let displayName: String?

    public init(id: UUID, platform: NearbyPeerPlatform, appVersion: String, deviceName: String,
                account: String? = nil, displayName: String? = nil) {
        self.id = id
        self.platform = platform
        self.appVersion = appVersion
        self.deviceName = deviceName
        self.account = account
        self.displayName = displayName
    }

    public static func local(id: UUID, platform: NearbyPeerPlatform, appVersion: String, deviceName: String,
                             account: String? = nil, displayName: String? = nil) -> Self {
        let platformName = switch platform {
        case .windows: "Windows PC"
        case .macOS: "Mac"
        case .iOS: "iPhone"
        case .android: "Android device"
        case .watchOS: "Apple Watch"
        case .wearOS: "Wear OS watch"
        }
        return Self(id: id, platform: platform,
            appVersion: NearbyAdvertisementCodec.localText(appVersion, maxBytes: NearbyAdvertisementCodec.maximumAppVersionBytes) ?? "1.0",
            deviceName: NearbyAdvertisementCodec.localText(deviceName, maxBytes: NearbyAdvertisementCodec.maximumDeviceNameBytes) ?? platformName,
            account: NearbyAdvertisementCodec.localText(account, maxBytes: NearbyAdvertisementCodec.maximumAccountBytes),
            displayName: NearbyAdvertisementCodec.localText(displayName, maxBytes: NearbyAdvertisementCodec.maximumDisplayNameBytes))
    }
}

public struct NearbyDiscoveredPeer: Identifiable, Equatable, Sendable {
    public let advertisement: NearbyPresenceAdvertisement
    public var id: UUID { advertisement.id }
    public var platform: NearbyPeerPlatform { advertisement.platform }
    public var appVersion: String { advertisement.appVersion }
    public var deviceName: String { advertisement.deviceName }
    public var account: String? { advertisement.account }
    public var displayName: String? { advertisement.displayName }

    public init(advertisement: NearbyPresenceAdvertisement) {
        self.advertisement = advertisement
    }
}

enum NearbyAdvertisementCodec {
    static let serviceType = "_mizon-peer._tcp"
    static let domain = "local."
    static let maximumAppVersionBytes = 32
    static let maximumDeviceNameBytes = 96
    static let maximumAccountBytes = 64
    static let maximumDisplayNameBytes = 96
    private static let maximumRecordBytes = 400
    private static let emptyID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func serviceName(for id: UUID) -> String {
        "Mizon-\(id.uuidString.lowercased())"
    }

    static func encode(_ advertisement: NearbyPresenceAdvertisement) -> Data? {
        guard isValid(advertisement) else { return nil }
        var fields = [
            ("v", "1"), ("id", advertisement.id.uuidString.lowercased()),
            ("platform", advertisement.platform.rawValue),
            ("app", advertisement.appVersion), ("device", advertisement.deviceName)
        ]
        if let account = advertisement.account { fields.append(("account", account)) }
        if let displayName = advertisement.displayName { fields.append(("display", displayName)) }

        var record = Data()
        for (key, value) in fields {
            let entry = "\(key)=\(value)".utf8
            record.append(UInt8(entry.count))
            record.append(contentsOf: entry)
        }
        return record
    }

    static func decode(_ record: Data, serviceName: String) -> NearbyPresenceAdvertisement? {
        guard !record.isEmpty, record.count <= maximumRecordBytes else { return nil }
        let bytes = Array(record)
        var fields: [String: String] = [:]
        var start = 0
        while start < bytes.count {
            let width = Int(bytes[start])
            let next = start + width + 1
            guard width > 0, next <= bytes.count,
                  let entry = String(bytes: bytes[(start + 1)..<next], encoding: .utf8),
                  let equal = entry.firstIndex(of: "=") else { return nil }
            let key = String(entry[..<equal]).lowercased()
            switch key {
            case "v", "id", "platform", "app", "device", "account", "display": break
            default: return nil
            }
            guard fields[key] == nil else { return nil }
            fields[key] = String(entry[entry.index(after: equal)...])
            start = next
        }

        guard fields["v"] == "1", let idText = fields["id"],
              let id = UUID(uuidString: idText), idText == id.uuidString.lowercased(),
              serviceName.lowercased() == Self.serviceName(for: id).lowercased(),
              let platform = fields["platform"].flatMap(NearbyPeerPlatform.init(rawValue:)),
              let appVersion = fields["app"], let deviceName = fields["device"] else { return nil }
        let advertisement = NearbyPresenceAdvertisement(id: id, platform: platform, appVersion: appVersion,
            deviceName: deviceName, account: fields["account"], displayName: fields["display"])
        return isValid(advertisement) ? advertisement : nil
    }

    private static func isValid(_ advertisement: NearbyPresenceAdvertisement) -> Bool {
        advertisement.id != emptyID &&
        isValidText(advertisement.appVersion, maxBytes: maximumAppVersionBytes) &&
        isValidText(advertisement.deviceName, maxBytes: maximumDeviceNameBytes) &&
        (advertisement.account.map { isValidText($0, maxBytes: maximumAccountBytes) } ?? true) &&
        (advertisement.displayName.map { isValidText($0, maxBytes: maximumDisplayNameBytes) } ?? true)
    }

    static func localText(_ value: String?, maxBytes: Int) -> String? {
        guard let value else { return nil }
        let scalars = String.UnicodeScalarView(value.unicodeScalars.filter(isSafeScalar))
        let normalized = String(scalars).precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        var remaining = maxBytes
        var fitted = ""
        for character in normalized {
            let width = String(character).utf8.count
            guard width <= remaining else { break }
            remaining -= width
            fitted.append(character)
        }
        fitted = fitted.trimmingCharacters(in: .whitespacesAndNewlines)
        return fitted.isEmpty ? nil : fitted
    }

    private static func isValidText(_ value: String, maxBytes: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= maxBytes &&
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        value.unicodeScalars.allSatisfy(isSafeScalar)
    }

    private static func isSafeScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator: return false
        default: break
        }
        switch scalar.value {
        case 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069: return false
        default: return true
        }
    }
}
