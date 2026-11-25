#if os(macOS) || os(iOS)
import AVFoundation
import Foundation
import MizonAPI
import MizonAPIClient
import Testing
@testable import MizonAppleCore
@testable import MizonAppleUI

@Suite(.serialized)
struct MusicFeatureVideoTests {
    @Test func downloadsRegisteredVideoBeforeReturningAndReplacesOnlyTheFailedEntryOnRetry() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        FeatureVideoProtocol.configure()
        let path = try await fixture.artwork.featuredVideo(fixture.id, session: fixture.session) { _ in }
        #expect(path.isFileURL)
        #expect(try Data(contentsOf: path) == FeatureVideoProtocol.video)
        let contentRequests = FeatureVideoProtocol.contentRequests
        #expect(contentRequests.map { $0.value(forHTTPHeaderField: "Range") } == ["bytes=0-81919", "bytes=81920-102399"])
        #expect(contentRequests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer feature-fixture" })

        try Data(repeating: 0, count: FeatureVideoProtocol.video.count).write(to: path)
        let unrelated = fixture.cacheRoot.appending(path: "another-entry")
        try Data([0x77]).write(to: unrelated)
        let replacement = try await fixture.artwork.featuredVideo(fixture.id, session: fixture.session, replacing: path) { _ in }
        #expect(replacement == path)
        #expect(try Data(contentsOf: replacement) == FeatureVideoProtocol.video)
        #expect(try Data(contentsOf: unrelated) == Data([0x77]))
        #expect(FeatureVideoProtocol.contentRequests.count == 4)
    }

    @Test func aStalledRequestTimesOutAndTheSameVideoCanBeRetried() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        FeatureVideoProtocol.configure(stallFirst: true)
        await #expect(throws: URLError(.timedOut)) {
            try await fixture.artwork.featuredVideo(fixture.id, session: fixture.session, timeout: .seconds(1)) { _ in }
        }
        #expect(FeatureVideoProtocol.contentRequests.count == 1)
        let path = try await fixture.artwork.featuredVideo(fixture.id, session: fixture.session, timeout: .seconds(3)) { _ in }
        #expect(try Data(contentsOf: path) == FeatureVideoProtocol.video)
    }

    @Test func downloadsAnHTTPSOriginWithNoRangeSupportAndKeepsBearerOnTheAPI() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        FeatureVideoProtocol.configure(direct: true)
        let path = try await fixture.artwork.featuredVideo(fixture.id, session: fixture.session) { _ in }
        #expect(path.isFileURL)
        #expect(try Data(contentsOf: path) == FeatureVideoProtocol.video)
        let contentRequests = FeatureVideoProtocol.contentRequests
        #expect(contentRequests.count == 1)
        #expect(contentRequests.first?.url?.host == "feature-storage.fixture.invalid")
        #expect(contentRequests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @MainActor @Test func aPlayerItemThatStaysUnknownTimesOutAndReleasesTheObserver() async throws {
        let item = AVPlayerItem(asset: AVMutableComposition())
        #expect(item.status == .unknown)
        await #expect(throws: URLError(.timedOut)) {
            try await MusicFeatureVideoReadiness.observe(item, timeout: .milliseconds(100)) {
                Issue.record("An unattached empty composition cannot become ready")
            }
        }
        let cancelled = Task {
            try await MusicFeatureVideoReadiness.observe(item) { Issue.record("An unattached item cannot become ready") }
        }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
    }

    private struct Fixture {
        let id = FeatureVideoProtocol.mediaID
        let cacheRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let http: URLSession
        let artwork: MusicArtworkStore
        let session: AuthSession

        init() async throws {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [FeatureVideoProtocol.self]
            http = URLSession(configuration: configuration)
            let api = MizonApi(session: http)
            session = AuthSession(accessToken: "feature-fixture", refreshToken: "", sessionPublicId: UUID(),
                                  clientPublicId: UUID(), identifier: "fixture",
                                  server: try #require(URL(string: "https://features.fixture.invalid/api")))
            artwork = MusicArtworkStore(service: MusicHomeService(api: api), session: session, cacheRoot: cacheRoot,
                                        peerNetwork: nil, downloadSession: http)
            try await api.setToken(session.accessToken)
        }

        func close() {
            http.invalidateAndCancel()
            try? FileManager.default.removeItem(at: cacheRoot)
        }
    }
}

private final class FeatureVideoProtocol: URLProtocol, @unchecked Sendable {
    static let mediaID = UUID()
    static let video = Data(repeating: 0x7A, count: 102_400)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var media = MediaResponse()
    nonisolated(unsafe) private static var shouldStallFirst = false
    nonisolated(unsafe) private static var content: [URLRequest] = []

    static var contentRequests: [URLRequest] { lock.withLock { content } }

    static func configure(stallFirst: Bool = false, direct: Bool = false) {
        lock.withLock {
            media = MediaResponse(mediaPublicId: mediaID, fileName: "fixture.mp4", fileSize: Int64(video.count),
                                  storagePath: direct ? "https://feature-storage.fixture.invalid/preview.mp4" : "file:///C:/Mizon/fixture.mp4")
            shouldStallFirst = stallFirst
            content = []
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            let url = try #require(request.url)
            if url.path == "/api/Medias/Media" {
                let media = Self.lock.withLock { Self.media }
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer feature-fixture")
                let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
                #expect(query.map(\.name) == ["MediaPublicId"])
                #expect(query.first?.value.flatMap(UUID.init(uuidString:)) == media.mediaPublicId)
                respond(200, body: try MizonJSON.encoder().encode(BaseApiResponse(content: media)), url: url)
                return
            }
            let stall = Self.lock.withLock {
                Self.content.append(request)
                return Self.shouldStallFirst && Self.content.count == 1
            }
            if stall { return }
            if url.host == "feature-storage.fixture.invalid", url.path == "/preview.mp4" {
                respond(200, body: Self.video, url: url)
            } else if url.path == "/api/Medias/MediaContent" {
                switch request.value(forHTTPHeaderField: "Range") {
                case "bytes=0-81919":
                    respond(206, body: Self.video.prefix(81_920), url: url, contentRange: "bytes 0-81919/102400")
                case "bytes=81920-102399":
                    respond(206, body: Self.video.suffix(20_480), url: url, contentRange: "bytes 81920-102399/102400")
                default: throw URLError(.badServerResponse)
                }
            } else {
                throw URLError(.unsupportedURL)
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func respond(_ status: Int, body: Data, url: URL, contentRange: String? = nil) {
        var headers = ["Content-Length": String(body.count)]
        headers["Content-Range"] = contentRange
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
#endif
