#if os(macOS)
import Foundation
import MizonAPI
import MizonAPIClient
import Testing
@testable import MizonAppleCore

@MainActor
struct MusicPlaylistPlaybackTests {
    @Test func playsAcrossPagesAndReportsAnEmptyPlaylist() async throws {
        let cache = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlaylistPlaybackProtocol.self]
        let http = URLSession(configuration: configuration)
        let api = MizonApi(session: http)
        let session = AuthSession(accessToken: "playlist-fixture", refreshToken: "", sessionPublicId: UUID(),
                                  clientPublicId: UUID(), identifier: "fixture", server: PlaylistPlaybackProtocol.server)
        let service = MusicHomeService(api: api)
        let artwork = MusicArtworkStore(service: service, session: session, cacheRoot: cache)
        let model = MusicHomeViewModel(session: session, service: service, artwork: artwork)
        defer {
            model.stop()
            http.invalidateAndCancel()
            try? FileManager.default.removeItem(at: cache)
        }
        try await api.setToken(session.accessToken)
        let cached = try await MediaDownloader(cacheRoot: cache).getCachedFilePath(
            .init(mediaPublicId: PlaylistPlaybackProtocol.media, fileName: "fixture.wav")
        )
        try PlaylistPlaybackProtocol.wav.write(to: cached)

        var tracks: [UUID] = []
        var previousTracks: [UUID?] = []
        model.playPlaylist(PlaylistPlaybackProtocol.playlist, title: { $0.title }) { track, previous in
            tracks.append(track)
            previousTracks.append(previous)
        }
        #expect(model.playlistPlaybackStatus == .preparing)
        try await waitUntil { tracks.count == 2 && !model.isPlaying }
        #expect(tracks == [PlaylistPlaybackProtocol.firstTrack, PlaylistPlaybackProtocol.secondTrack])
        #expect(previousTracks == [nil, PlaylistPlaybackProtocol.firstTrack])
        #expect(model.playlistPlaybackStatus == nil)

        model.playPlaylist(PlaylistPlaybackProtocol.emptyPlaylist, title: { $0.title }) { _, _ in
            Issue.record("An empty playlist must not start playback")
        }
        try await waitUntil { model.playlistPlaybackStatus == .unavailable }
        #expect(model.playingTrack == PlaylistPlaybackProtocol.secondTrack)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(12)
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(30)) }
        try #require(predicate())
    }
}

private final class PlaylistPlaybackProtocol: URLProtocol, @unchecked Sendable {
    static let server = URL(string: "https://playlist.fixture.invalid/api")!
    static let playlist = UUID()
    static let emptyPlaylist = UUID()
    static let firstTrack = UUID()
    static let secondTrack = UUID()
    static let media = UUID()

    // One second of mono PCM silence. The real AVPlayer emits the completion event.
    static let wav: Data = {
        let sampleBytes = 88_200
        var data = Data()
        func bytes<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        bytes(UInt32(36 + sampleBytes))
        data.append(contentsOf: "WAVEfmt ".utf8)
        bytes(UInt32(16))
        bytes(UInt16(1))
        bytes(UInt16(1))
        bytes(UInt32(44_100))
        bytes(UInt32(88_200))
        bytes(UInt16(2))
        bytes(UInt16(16))
        data.append(contentsOf: "data".utf8)
        bytes(UInt32(sampleBytes))
        data.append(Data(repeating: 0, count: sampleBytes))
        return data
    }()

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == server.host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            let url = try #require(request.url)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer playlist-fixture")
            let encoder = MizonJSON.encoder()
            let data: Data
            switch url.path {
            case "/api/Musics/MusicPlaylistDetails":
                let payload: Data
                if let body = request.httpBody {
                    payload = body
                } else {
                    let stream = try #require(request.httpBodyStream)
                    stream.open()
                    defer { stream.close() }
                    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
                    defer { buffer.deallocate() }
                    let count = stream.read(buffer, maxLength: 1024)
                    guard count >= 0 else { throw URLError(.cannotDecodeRawData) }
                    payload = Data(bytes: buffer, count: count)
                }
                func matching(_ id: UUID, cursor: String? = nil) throws -> Bool {
                    let expected = MusicPlaylistDetailsRequest(musicPlaylistPublicId: id, cursor: cursor)
                    return payload == (try CompressionMethod.gzip.compress(encoder.encode(BaseApiRequest(content: expected))))
                }
                let page: MusicPlaylistDetailsResponse
                if try matching(Self.emptyPlaylist) {
                    page = .init(publicId: Self.emptyPlaylist)
                } else if try matching(Self.playlist) {
                    page = .init(publicId: Self.playlist, musicsCount: 2,
                                 musics: [.init(publicId: Self.firstTrack, title: "First track")], nextCursor: "second")
                } else {
                    let isNextPage = try matching(Self.playlist, cursor: "second")
                    try #require(isNextPage)
                    page = .init(publicId: Self.playlist, musicsCount: 2,
                                 musics: [.init(publicId: Self.secondTrack, title: "Second track")])
                }
                data = try encoder.encode(BaseApiResponse(content: page))
            case "/api/Musics/MusicFile":
                let file = MusicFileResponse(mediaPublicId: Self.media, fileName: "fixture.wav", fileSize: Int64(Self.wav.count))
                data = try encoder.encode(BaseApiResponse(content: file))
            case "/api/Musics/MusicPlay":
                data = try encoder.encode(BaseApiResponse(content: MusicPlayResponse()))
            default:
                throw URLError(.badURL)
            }
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                        headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
#endif
