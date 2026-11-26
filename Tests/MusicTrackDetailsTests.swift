#if os(macOS)
import Foundation
import MizonAPI
import MizonAPIClient
import MizonAppleCore
import Testing
@testable import MizonAppleUI

@MainActor
struct MusicTrackDetailsTests {
    @Test func layoutPreservesReferenceArtworkAndFitsPhoneOrientations() {
        let portrait = MusicTrackLayoutMetrics(width: 402)
        let compact = MusicTrackLayoutMetrics(width: 320)
        for landscape in [680.0, 796.0, 840.0] {
            let metrics = MusicTrackLayoutMetrics(width: landscape, height: 402)
            #expect(!metrics.wide)
            #expect(metrics.sideBySide)
            #expect(metrics.artwork <= 205)
            #expect(metrics.usesVerticalVolume)
        }
        #expect(portrait.artwork == 280 && !portrait.usesVerticalVolume)
        #expect(compact.artwork + 2 * (compact.inset + compact.outside) == 320)
        #expect(!MusicTrackLayoutMetrics(width: 1_000).wide)
        #expect(MusicTrackLayoutMetrics(width: 1_001).wide)
        #expect(MusicTrackLayoutMetrics(width: 2_200).width == 1_920)
    }

    @Test func waveformUsesWindowsBarCountHeightsAndResampling() {
        let fixture = TrackDetailProtocol.musicID
        let waveform = [
            WaveformResponse(offsetInMilliseconds: 1_000, rms: 0.8),
            WaveformResponse(offsetInMilliseconds: 0, rms: 0.4)
        ]
        let bars = TrackWaveformBar.sample(waveform, trackID: fixture)
        #expect(bars.count == 250)
        #expect(bars[0].top == 38)
        #expect(bars[124].top == 38)
        #expect(bars[125].top == 70)
        #expect(bars.last?.bottom == 35)
        let fallback = TrackWaveformBar.sample([], trackID: fixture)
        #expect(fallback == TrackWaveformBar.sample([], trackID: fixture))
        #expect(fallback.allSatisfy { (7...70).contains($0.top) && $0.bottom == $0.top / 2 })
    }

    @Test func discussionUsesTypedSortAndCursorAndPreservesLinkedRow() async throws {
        let setup = try await makeFixture()
        defer { setup.connection.invalidateAndCancel() }
        let detail = MusicTrackDetailsViewModel(id: TrackDetailProtocol.musicID, track: MusicResponse(title: "Fixture"),
                                               music: setup.home,
                                               linkedComment: MusicCommentItemResponse(publicId: TrackDetailProtocol.linked, text: "Linked"))
        await detail.loadPane()
        #expect(detail.comments.map(\.publicId) == [TrackDetailProtocol.linked, TrackDetailProtocol.first])
        #expect(detail.nextComment == TrackDetailProtocol.first)
        await detail.moreComments()
        #expect(detail.comments.map(\.publicId) == [TrackDetailProtocol.linked, TrackDetailProtocol.first, TrackDetailProtocol.second])
        #expect(detail.nextComment == nil)
        await detail.sortDiscussion(.oldest)
        #expect(detail.sort == .oldest)
        #expect(detail.comments.last?.publicId == TrackDetailProtocol.second)
        await detail.showReplies(detail.comments.last)
        #expect(detail.parentComment?.publicId == TrackDetailProtocol.second)
        #expect(detail.comments.map(\.publicId) == [TrackDetailProtocol.reply])
        #expect(detail.failures.isEmpty)
    }

    @Test func failedReactionRestoresServerCountAndSelection() async throws {
        let setup = try await makeFixture()
        defer { setup.connection.invalidateAndCancel() }
        let track = MusicTrackDetailsViewModel(id: TrackDetailProtocol.musicID, track: MusicResponse(title: "Fixture"),
                                             music: setup.home, linkedComment: nil)
        await track.load(.reactions)
        let before = try #require(track.reactions.first)
        #expect(before.count == 12 && !before.selected)
        await track.react(before)
        let after = try #require(track.reactions.first)
        #expect(after.count == 12 && !after.selected)
        #expect(track.notice == "TrackSectionFailed")
        #expect(track.busyIDs.isEmpty)
    }

    private func makeFixture() async throws -> (home: MusicHomeViewModel, connection: URLSession) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TrackDetailProtocol.self]
        let connection = URLSession(configuration: configuration)
        let api = MizonApi(session: connection)
        let session = AuthSession(accessToken: "fixture-access", refreshToken: "", sessionPublicId: UUID(),
                                  clientPublicId: UUID(), identifier: "fixture",
                                  server: try #require(URL(string: "https://track-detail-fixture.invalid/api")))
        try await api.setToken(session.accessToken)
        return (MusicHomeViewModel(session: session, service: MusicHomeService(api: api)), connection)
    }
}

private final class TrackDetailProtocol: URLProtocol, @unchecked Sendable {
    static let musicID = UUID()
    static let linked = UUID()
    static let first = UUID()
    static let second = UUID()
    static let reply = UUID()
    static let reaction = UUID()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            guard let url = request.url, url.host == "track-detail-fixture.invalid",
                  let path = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
            let query = Dictionary((path.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
            let bytes: Data
            let code: Int
            switch (request.httpMethod, path.path) {
            case ("GET", "/api/Musics/MusicComments"):
                guard query["MusicPublicId"] == Self.musicID.uuidString.lowercased(),
                      query["PageSize"] == "30", let sort = query["Sort"], ["newest", "oldest"].contains(sort) else {
                    throw URLError(.badURL)
                }
                let item: UUID
                let next: UUID?
                if query["ParentMusicCommentPublicId"] == Self.second.uuidString.lowercased() {
                    item = Self.reply; next = nil
                } else if query["After"] == Self.first.uuidString.lowercased() || sort == "oldest" {
                    item = Self.second; next = nil
                } else {
                    item = Self.first; next = Self.first
                }
                bytes = try response(MusicCommentsResponse(musicComments: [.init(publicId: item, text: "Fixture")], next: next))
                code = 200
            case ("GET", "/api/Musics/MusicReactionTypes"):
                bytes = try response(MusicReactionTypesResponse(musicReactionTypes: [.init(emoji: "🎧", publicId: Self.reaction)]))
                code = 200
            case ("GET", "/api/Musics/MusicReactions"):
                bytes = try response(MusicReactionsResponse(musicReactionItems: [
                    .init(emoji: "🎧", count: 12, reactedByMe: false, musicReactionTypePublicId: Self.reaction)
                ]))
                code = 200
            case ("POST", "/api/Musics/MusicReaction"):
                bytes = Data("{}".utf8); code = 500
            default: throw URLError(.badURL)
            }
            guard let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil,
                                                 headerFields: ["Content-Type": "application/json"]) else {
                throw URLError(.badServerResponse)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: bytes)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func response<T: IApiResponse>(_ input: T) throws -> Data {
        try MizonJSON.encoder().encode(BaseApiResponse(content: input))
    }
}
#endif
