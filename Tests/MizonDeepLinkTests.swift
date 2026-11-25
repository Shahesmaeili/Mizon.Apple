import Foundation
import Testing
@testable import MizonAppleCore

struct MizonDeepLinkTests {
    private let id = UUID(uuidString: "0195dd3c-9a3e-7c4a-8c6f-2e9c0f6b1a72")!
    private let comment = UUID(uuidString: "0195dd3c-9a3e-7c4a-8c6f-2e9c0f6b1a73")!

    @Test func windowsCatalogRoundTripsWithLegacyAuthorities() throws {
        let routes: [MizonDeepLink] = [
            .home, .login, .register, .music, .movies, .apps, .vpn, .playlists, .playlist(id),
            .track(id, action: .details), .track(id, action: .play), .track(id, action: .download),
            .track(id, action: .video), .musicComment(id, comment: comment), .client(id), .person(id),
            .story(id), .activities, .settings(.appearance), .search("معین & Mizon + 🎵")
        ]
        #expect(Set(routes.map(\.routeKey)) == Set([
            "home", "login", "register", "music", "movies", "apps", "vpn", "playlists", "playlist",
            "music-details", "music-play", "music-download", "music-video", "music-comment",
            "client", "person", "story", "activities", "settings", "search"
        ]))

        for route in routes {
            let uri = route.canonicalURI
            #expect(MizonDeepLink(rawValue: uri) == route)
            #expect(MizonDeepLink(url: try #require(URL(string: uri))) == route)
            let suffix = uri.dropFirst("mizon://".count)
            #expect(MizonDeepLink(rawValue: "mizon://localhost/" + suffix) == route)
            #expect(MizonDeepLink(rawValue: "mizon://S-1-5-21-123-1001/localhost/" + suffix) == route)
            #expect(route.requiresAuthentication == (route != .login && route != .register))
        }

        for section in MizonDeepLink.SettingsSection.allCases {
            #expect(MizonDeepLink(rawValue: "MIZON://SETTINGS/" + section.rawValue.uppercased() + "/") == .settings(section))
        }
        #expect(MizonDeepLink(rawValue: "mizon://settings") == .settings(nil))
        let compact = id.uuidString.replacingOccurrences(of: "-", with: "")
        #expect(MizonDeepLink(rawValue: "mizon://music/\(compact)?ACTION=DETAILS")?.canonicalURI ==
                "mizon://music/\(id.uuidString.lowercased())")
        #expect(MizonDeepLink.track(id, action: .details).responseTimeout == .seconds(50))
        #expect(MizonDeepLink.track(id, action: .download).responseTimeout == .seconds(300))
    }

    @Test func searchPreservesUnicodeAndDecodesExactlyOnce() {
        for query in ["100%", "%FF", "%2F", "test@example.com", "a=b?c#d", "نیم‌فاصله", "a+b & c?x=1/#% 🎵",
                      String(repeating: "ا", count: 120)] {
            let route = MizonDeepLink.search(query)
            #expect(MizonDeepLink(rawValue: route.canonicalURI) == route)
        }
        #expect(MizonDeepLink(rawValue: "mizon://search?query=%20test%2B+two%20") == .search("test+ two"))
        #expect(MizonDeepLink(rawValue: "mizon://search?query=%252F") == .search("%2F"))
        #expect(MizonDeepLink(routeKey: "SEARCH", searchQuery: "  موسیقی  ") == .search("موسیقی"))
        #expect(MizonDeepLink(routeKey: "search", searchQuery: "x\ny") == nil)
        #expect(MizonDeepLink(routeKey: "music-comment", publicID: id, commentPublicID: comment) == .musicComment(id, comment: comment))
        #expect(MizonDeepLink(routeKey: "music-comment", publicID: id) == nil)
        #expect(MizonDeepLink(routeKey: "home", publicID: id) == nil)
    }

    @Test func rejectsMalformedOrAmbiguousProtocolInput() {
        let rawID = id.uuidString
        let invalid = [
            "", "mizon:", "mizon:/music", "mizon:///music", "mizon://", "mizon://localhost/", "mizon://unknown",
            "mizon://welcome", "mizon://localhost/WELCOME/", "mizon://S-1-5-21-123-1001/localhost/welcome",
            "mizon://settings/arbitrary", "mizon://settings/account?theme=dark", "mizon://settings/../login",
            "mizon://settings/%2E%2E/login", "mizon://settings/%61ccount", "mizon://settings//account", "mizon://home//",
            "mizon://music/../login", "mizon://localhost/../music", "mizon://music/./", "mizon://music\\..\\login",
            "mizon://localhost//music", "mizon://user:password@settings/appearance", "mizon://settings:42/appearance",
            "mizon://settings/appearance#", "mizon://home?", "mizon://activities?filter=music", "mizon://story/not-a-guid",
            "mizon://S-1-invalid/localhost/music", "mizon://S-1-18446744073709551616-5/localhost/music",
            "mizon://music/ \(rawID)", "mizon://music/\(rawID) ", "mizon://music/{\(rawID)}",
            "mizon://music/\(rawID)?action=play&action=video", "mizon://music/\(rawID)?action=%70lay",
            "mizon://music/\(rawID)/comments/00000000-0000-0000-0000-000000000000",
            "mizon://story/\(rawID)?action=delete", " mizon://home", "mizon://home\r\n",
            "mizon://search?query=a%00b", "mizon://search?query=a%0Ab",
            "mizon://search?query=%", "mizon://search?query=%0", "mizon://search?query=%GG", "mizon://search?query=%FF",
            "mizon://search?query=%C0%AF", "mizon://search?query=%ED%A0%80", "mizon://search?query=%E2%82",
            "mizon://search?query=%F4%90%80%80", "mizon://search?query=hello&query=world",
            "mizon://search?query=" + String(repeating: "🎵", count: 61),
            "mizon://search?query=" + String(repeating: "a", count: MizonDeepLink.maximumURILength),
            "mizon://search?query=hello&redirect=mizon://login", "https://music/" + rawID,
            "file:///private/path", "mizon://S-1-5-21-123-1001/attacker/home"
        ]
        for value in invalid {
            #expect(MizonDeepLink(rawValue: value) == nil, Comment(rawValue: "Accepted invalid URI: " + value))
        }
    }

    @Test func emitsWindowsResponseMembersAndChecksTheRequestID() throws {
        let response = MizonDeepLinkResult.success(requestID: id, route: .musicComment(id, comment: comment), stage: .opened)
        let encoded = try response.encoded()
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let payload = try #require(object["data"] as? [String: Any])
        #expect(object["version"] as? Int == 1)
        #expect(object["requestId"] as? String == id.uuidString.lowercased())
        #expect(object["code"] as? String == "opened")
        #expect(object["success"] as? Bool == true)
        #expect(payload["destination"] as? String == "music-comment")
        #expect(payload["publicId"] as? String == id.uuidString.lowercased())
        #expect(payload["commentPublicId"] as? String == comment.uuidString.lowercased())
        #expect(payload["completionStage"] as? String == "opened")
        #expect(payload["settingsSection"] == nil)
        #expect(MizonDeepLinkResult(data: encoded, expectedRequestID: id) == response)
        #expect(MizonDeepLinkResult(data: encoded, expectedRequestID: comment) == nil)

        let blocked = MizonDeepLinkResult.failure(requestID: id, code: "requires_sign_in", message: "Sign in first.")
        #expect(MizonDeepLinkResult(data: try blocked.encoded(), expectedRequestID: id) == blocked)
        let invalid = MizonDeepLinkResult.failure(requestID: id, code: "Unknown Code", message: "private\nerror")
        #expect(invalid.code == "invalid_result")
        #expect(!invalid.message.contains("private"))
    }

    @Test func rejectsUnknownDuplicateOversizeOrInconsistentResultFields() throws {
        let correlation = id.uuidString.lowercased()
        let prefix = #"{"version":1,"requestId":""# + correlation + #"","success":false,"code":"invalid_uri","message":"Bad link""#
        let valid = Data((prefix + "}").utf8)
        #expect(MizonDeepLinkResult(data: valid, expectedRequestID: id)?.code == "invalid_uri")
        let extraMembers = [#","requestId":"wrong"}"#, #","\u0063ode":"wrong"}"#,
                            #","unknown":{"a":1}}"#, #","metadata":[]}"#]
        for tail in extraMembers {
            #expect(MizonDeepLinkResult(data: Data((prefix + tail).utf8), expectedRequestID: id) == nil)
        }
        let versionTwo = Data(String(decoding: valid, as: UTF8.self).replacingOccurrences(of: #""version":1"#, with: #""version":2"#).utf8)
        #expect(MizonDeepLinkResult(data: versionTwo, expectedRequestID: id) == nil)
        let oversized = valid + Data(repeating: 32, count: MizonDeepLinkResult.maximumJSONBytes)
        #expect(MizonDeepLinkResult(data: oversized, expectedRequestID: id) == nil)
        let alternateEncoding = try #require((prefix + "}").data(using: .utf16))
        #expect(MizonDeepLinkResult(data: alternateEncoding, expectedRequestID: id) == nil)

        let opened = try MizonDeepLinkResult.success(requestID: id, route: .settings(.language), stage: .completed).encoded()
        let mismatched = Data(String(decoding: opened, as: UTF8.self)
            .replacingOccurrences(of: #""settingsSection":"language""#, with: #""settingsSection":"appearance""#).utf8)
        #expect(MizonDeepLinkResult(data: mismatched, expectedRequestID: id) == nil)
    }
}
