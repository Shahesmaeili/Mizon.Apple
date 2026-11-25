#if os(macOS) || os(iOS)
import Foundation
import MizonAPI
import MizonAPIClient
import Testing
@testable import MizonAppleCore
@testable import MizonAppleUI

struct MusicDeepLinkDestinationTests {
    @Test func keepsOperationsOnTheCorrectMusicSurface() {
        let music = UUID()
        let comment = UUID()
        #expect(MusicDestination(deepLink: .track(music, action: .details)) == .track(music))
        #expect(MusicDestination(deepLink: .track(music, action: .play)) == .track(music))
        #expect(MusicDestination(deepLink: .track(music, action: .download)) == .track(music))
        #expect(MusicDestination(deepLink: .track(music, action: .video)) == .musicVideo(music))
        #expect(MusicDestination(deepLink: .musicComment(music, comment: comment)) == .musicComment(music, comment: comment))
        #expect(MusicDestination(deepLink: .movies) == .section(.movies))
        #expect(MusicDestination(deepLink: .apps) == .section(.apps))
        #expect(MusicDestination(deepLink: .vpn) == .section(.vpn))
    }

    @Test func usesExactCommentQueryAndRejectsUnrelatedResults() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MusicLinkFixtureProtocol.self]
        let connection = URLSession(configuration: configuration)
        defer { connection.invalidateAndCancel() }
        let api = MizonApi(session: connection)
        let session = AuthSession(accessToken: "fixture-access", refreshToken: "",
                                  sessionPublicId: UUID(), clientPublicId: UUID(), identifier: "fixture",
                                  server: try #require(URL(string: "https://music-link-fixture.invalid/api")))
        try await api.setToken(session.accessToken)
        let service = MusicHomeService(api: api)
        let selected = try await service.trackComment(MusicLinkFixtureProtocol.target,
                                                      musicID: MusicLinkFixtureProtocol.music, session: session)
        #expect(selected?.publicId == MusicLinkFixtureProtocol.target)
        let absent = try await service.trackComment(MusicLinkFixtureProtocol.missing,
                                                    musicID: MusicLinkFixtureProtocol.music, session: session)
        #expect(absent == nil)
    }
}

private final class MusicLinkFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let music = UUID()
    static let target = UUID()
    static let missing = UUID()
    static let other = UUID()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            guard let url = request.url, url.host == "music-link-fixture.invalid",
                  url.path == "/api/Musics/MusicComments", request.httpMethod == "GET",
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  items.first(where: { $0.name == "MusicPublicId" })?.value == Self.music.uuidString.lowercased(),
                  let selected = items.first(where: { $0.name == "MusicCommentPublicId" })?.value,
                  selected == Self.target.uuidString.lowercased() || selected == Self.missing.uuidString.lowercased(),
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                 headerFields: ["Content-Type": "application/json"]) else {
                throw URLError(.badURL)
            }
            var comments = [MusicCommentItemResponse(publicId: Self.other, text: "Unrelated result")]
            if selected == Self.target.uuidString.lowercased() {
                comments.append(MusicCommentItemResponse(publicId: Self.target, text: "Requested comment"))
            }
            let payload = try MizonJSON.encoder().encode(BaseApiResponse(content: MusicCommentsResponse(musicComments: comments)))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: payload)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
#endif
