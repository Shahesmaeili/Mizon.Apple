import Foundation

/// Navigation destinations shared with the Windows protocol. Welcome is internal.
public enum MizonDeepLink: Hashable, Sendable {
    public enum MusicAction: String, Hashable, Sendable {
        case details, play, download, video
    }

    public enum SettingsSection: String, CaseIterable, Hashable, Sendable {
        case account, security, language, appearance, notifications, storage, updates, platforms
        case aiConnections = "ai-connections"
    }

    case home, login, register, music, movies, apps, vpn, playlists, activities
    case track(UUID, action: MusicAction)
    case musicComment(UUID, comment: UUID)
    case playlist(UUID), client(UUID), person(UUID), story(UUID)
    case settings(SettingsSection?)
    case search(String)

    public static let maximumURILength = 2_048

    private static let schemePrefix = "mizon://"
    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    static let emptyID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    public init?(url: URL) {
        self.init(rawValue: url.absoluteString)
    }

    public init?(rawValue: String) {
        let length = rawValue.utf16.count
        guard ((Self.schemePrefix.count + 1)...Self.maximumURILength).contains(length),
              rawValue.prefix(Self.schemePrefix.count).lowercased() == Self.schemePrefix,
              Self.hasNoControlCharacters(rawValue),
              !rawValue.contains("\\"), !rawValue.contains("#") else { return nil }

        // Split the original URI before Foundation can remove dot segments or encode the authority.
        let components = rawValue.dropFirst(Self.schemePrefix.count)
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var path = components[0]
        if path.last == "/" { path = path.dropLast() }
        guard !path.isEmpty, !path.contains("%") else { return nil }

        var parts = path.split(separator: "/", omittingEmptySubsequences: false)[...]
        guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        if parts.first?.lowercased() == "localhost" {
            parts = parts.dropFirst()
        } else if let authority = parts.first, Self.isLegacySID(authority),
                  parts.dropFirst().first?.lowercased() == "localhost" {
            parts = parts.dropFirst(2)
        }
        guard let head = parts.first else { return nil }
        let destination = head.lowercased()
        let arguments = Array(parts.dropFirst())
        let query = components.count == 2 ? components[1] : nil

        if arguments.isEmpty {
            if destination == "search" {
                guard let query, query.utf16.count < 1_500,
                      let rawQuery = Self.queryValue(query, name: "query"),
                      let decoded = Self.decodeSearch(rawQuery) else { return nil }
                self = .search(decoded)
            } else {
                guard query == nil, let route = Self.page(destination) else { return nil }
                self = route
            }
            return
        }

        if destination == "settings", arguments.count == 1, query == nil {
            guard let section = SettingsSection(rawValue: arguments[0].lowercased()) else { return nil }
            self = .settings(section)
            return
        }

        guard let id = Self.publicID(arguments[0]) else { return nil }
        if destination == "music", query == nil, arguments.count == 3,
           arguments[1].lowercased() == "comments", let comment = Self.publicID(arguments[2]) {
            self = .musicComment(id, comment: comment)
            return
        }

        guard arguments.count == 1 else { return nil }
        switch destination {
        case "music":
            guard let query else {
                self = .track(id, action: .details)
                return
            }
            guard let rawAction = Self.queryValue(query, name: "action"),
                  let action = MusicAction(rawValue: rawAction.lowercased()) else { return nil }
            self = .track(id, action: action)
        case "playlist" where query == nil: self = .playlist(id)
        case "client" where query == nil: self = .client(id)
        case "person" where query == nil: self = .person(id)
        case "story" where query == nil: self = .story(id)
        default: return nil
        }
    }

    public init?(routeKey: String, publicID: UUID? = nil, commentPublicID: UUID? = nil,
                 searchQuery: String? = nil, settingsSection: SettingsSection? = nil) {
        let key = routeKey.lowercased()
        guard publicID != Self.emptyID, commentPublicID != Self.emptyID,
              (key == "search") == (searchQuery != nil), (key == "music-comment") == (commentPublicID != nil),
              key == "settings" || settingsSection == nil else { return nil }

        if let publicID {
            switch key {
            case "music-details": self = .track(publicID, action: .details)
            case "music-play": self = .track(publicID, action: .play)
            case "music-download": self = .track(publicID, action: .download)
            case "music-video": self = .track(publicID, action: .video)
            case "music-comment":
                guard let commentPublicID else { return nil }
                self = .musicComment(publicID, comment: commentPublicID)
            case "playlist": self = .playlist(publicID)
            case "client": self = .client(publicID)
            case "person": self = .person(publicID)
            case "story": self = .story(publicID)
            default: return nil
            }
        } else if let searchQuery {
            guard Self.hasNoControlCharacters(searchQuery) else { return nil }
            let query = Self.trimWhitespace(searchQuery)
            guard (1...120).contains(query.utf16.count) else { return nil }
            self = .search(query)
        } else if key == "settings" {
            self = .settings(settingsSection)
        } else {
            guard commentPublicID == nil, let route = Self.page(key) else { return nil }
            self = route
        }
    }

    public var routeKey: String {
        switch self {
        case .home: "home"
        case .login: "login"
        case .register: "register"
        case .music: "music"
        case .movies: "movies"
        case .apps: "apps"
        case .vpn: "vpn"
        case .playlists: "playlists"
        case .activities: "activities"
        case .track(_, let action): "music-\(action.rawValue)"
        case .musicComment: "music-comment"
        case .playlist: "playlist"
        case .client: "client"
        case .person: "person"
        case .story: "story"
        case .settings: "settings"
        case .search: "search"
        }
    }

    public var canonicalURI: String {
        let suffix: String
        switch self {
        case .track(let id, let action):
            let query = action == .details ? "" : "?action=\(action.rawValue)"
            suffix = "music/\(id.uuidString.lowercased())\(query)"
        case .musicComment(let id, let comment):
            suffix = "music/\(id.uuidString.lowercased())/comments/\(comment.uuidString.lowercased())"
        case .playlist(let id), .client(let id), .person(let id), .story(let id):
            suffix = "\(routeKey)/\(id.uuidString.lowercased())"
        case .settings(let section):
            suffix = section.map { "settings/\($0.rawValue)" } ?? "settings"
        case .search(let query):
            suffix = "search?query=" + (Self.trimWhitespace(query).addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? "")
        default:
            suffix = routeKey
        }
        return Self.schemePrefix + suffix
    }

    public var requiresAuthentication: Bool { self != .login && self != .register }

    public var responseTimeout: Duration {
        if case .track(_, action: .download) = self { return .seconds(300) }
        return .seconds(50)
    }

    public var publicID: UUID? {
        switch self {
        case .track(let id, _), .musicComment(let id, _), .playlist(let id), .client(let id), .person(let id), .story(let id): id
        default: nil
        }
    }

    public var commentPublicID: UUID? {
        if case .musicComment(_, let id) = self { return id }
        return nil
    }

    public var settingsSection: SettingsSection? {
        if case .settings(let section) = self { return section }
        return nil
    }

    private static func page(_ key: String) -> Self? {
        switch key {
        case "home": .home
        case "login": .login
        case "register": .register
        case "music": .music
        case "movies": .movies
        case "apps": .apps
        case "vpn": .vpn
        case "playlists": .playlists
        case "activities": .activities
        case "settings": .settings(nil)
        default: nil
        }
    }

    private static func publicID(_ value: Substring) -> UUID? {
        let bytes = Array(value.utf8)
        let canonical: String
        switch bytes.count {
        case 36:
            canonical = String(value)
        case 32:
            canonical = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32]
                .map { String(decoding: bytes[$0], as: UTF8.self) }.joined(separator: "-")
        default: return nil
        }
        guard let id = UUID(uuidString: canonical), id != emptyID else { return nil }
        return id
    }

    private static func isLegacySID(_ authority: Substring) -> Bool {
        guard authority.utf16.count <= 184, authority.prefix(4).lowercased() == "s-1-" else { return false }
        let parts = authority.split(separator: "-", omittingEmptySubsequences: false)
        return parts.count >= 4 && parts.dropFirst(2).allSatisfy {
            !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } && UInt64($0) != nil
        }
    }

    private static func queryValue(_ query: Substring, name: String) -> Substring? {
        guard let equals = query.firstIndex(of: "="), !query.contains("&"),
              query[..<equals].lowercased() == name else { return nil }
        return query[query.index(after: equals)...]
    }

    private static func decodeSearch(_ value: Substring) -> String? {
        let bytes = Array(value.utf8)
        var decoded: [UInt8] = []
        decoded.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            switch bytes[index] {
            case 37: // %
                guard index + 2 < bytes.count,
                      let high = hexDigit(bytes[index + 1]), let low = hexDigit(bytes[index + 2]) else { return nil }
                decoded.append(high * 16 + low)
                index += 3
            case 43: // +
                decoded.append(32)
                index += 1
            default:
                decoded.append(bytes[index])
                index += 1
            }
        }
        guard let text = String(bytes: decoded, encoding: .utf8) else { return nil }
        let query = trimWhitespace(text)
        guard (1...120).contains(query.utf16.count), hasNoControlCharacters(query) else { return nil }
        return query
    }

    private static func hexDigit(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: byte - 48
        case 65...70: byte - 55
        case 97...102: byte - 87
        default: nil
        }
    }

    static func hasNoControlCharacters(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { $0.properties.generalCategory != .control }
    }

    static func trimWhitespace(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
