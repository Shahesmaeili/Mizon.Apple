import CoreGraphics
import Foundation
import ImageIO
import MizonAPI
import MizonAPIClient
import Testing
import UniformTypeIdentifiers
@testable import MizonAppleCore

@Suite(.serialized)
struct NearbyProfileArtworkServiceTests {
    @Test func normalizesOnlyRegisteredUsernames() {
        #expect(NearbyProfileArtworkService.normalizedUsername("  Ｍｉｚｏｎ.User_1\n") == "mizon.user_1")
        for username in [nil, "ab", "Other User", "mizon@fixture.test", "user-name", "کاربر", "me\u{202E}",
                         String(repeating: "a", count: 33)] {
            #expect(NearbyProfileArtworkService.normalizedUsername(username) == nil)
        }
    }

    @Test func requiresExactClientUsernameAndCachesOnlyThePublicProfileAvatar() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        NearbyArtworkProtocol.install(fixture.reply)
        try await fixture.api.setToken(fixture.session.accessToken)

        let first = try #require(await fixture.service.image(for: "  TARGET.User ", session: fixture.session, artwork: fixture.artwork))
        let second = try #require(await fixture.service.image(for: "target.user", session: fixture.session, artwork: fixture.artwork))
        #expect(first.width == 128)
        #expect(first.height < 128)
        #expect(first === second)

        let requests = NearbyArtworkProtocol.requests
        #expect(requests.map { $0.url?.path } == [
            "/api/Search/Global", "/api/Clients/ClientProfile", "/api/Medias/Media", "/api/Medias/MediaContent",
            "/api/Search/Global", "/api/Clients/ClientProfile"
        ])
        #expect(requests.allSatisfy { $0.url?.host == "mizon.example" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access" })
        #expect(requests[0].query("Query") == "target.user")
        #expect(requests[1].query("ClientPublicId")?.lowercased() == fixture.exactClientID.uuidString.lowercased())
        #expect(requests[2].query("MediaPublicId")?.lowercased() == fixture.avatarID.uuidString.lowercased())
        #expect(requests[3].query("MediaPublicId")?.lowercased() == fixture.avatarID.uuidString.lowercased())
        #expect(requests[3].value(forHTTPHeaderField: "Range") == "bytes=0-\(fixture.imageData.count - 1)")
    }

    @Test func signedInAvatarUsesAuthenticatedContentForServerLocalFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        NearbyArtworkProtocol.install(fixture.reply)
        let service = MizonWelcomeService(api: fixture.api, cacheRoot: fixture.cacheRoot)
        try await fixture.api.setToken(fixture.session.accessToken)

        let account = try await service.account(for: fixture.session)
        let mediaID = try #require(account.avatarID)
        #expect(mediaID == fixture.avatarID)
        let image = try #require(await service.avatar(for: mediaID, session: fixture.session))
        #expect(image.width == 240)
        #expect(image.height == 144)

        let requests = NearbyArtworkProtocol.requests
        #expect(requests.map { $0.url?.path } == ["/api/Clients/Me", "/api/Medias/Media", "/api/Medias/MediaContent"])
        #expect(requests.allSatisfy { $0.url?.host == "mizon.example" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access" })
        #expect(requests.last?.query("MediaPublicId").flatMap(UUID.init(uuidString:)) == mediaID)

        await fixture.api.clearToken()
        await #expect(throws: CancellationError.self) { try await service.avatar(for: mediaID, session: fixture.session) }
        #expect(NearbyArtworkProtocol.requests.count == requests.count)
    }

    @Test func homeCanLoadAProfilePhotoAfterWelcomeTimesOut() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        NearbyArtworkProtocol.install { request in
            if request.url?.path == "/api/Medias/Media" {
                let media = MediaResponse(mediaPublicId: fixture.avatarID, totalChunks: 1, chunkSize: 0,
                    fileName: "fixture.png", fileSize: Int64(fixture.imageData.count),
                    storagePath: "file:///C:/Mizon/fixture.png")
                return .init(body: try MizonJSON.encoder().encode(BaseApiResponse(content: media)))
            }
            var reply = try fixture.reply(request)
            if request.url?.path == "/api/Medias/MediaContent" { reply.delay = 0.5 }
            return reply
        }
        let service: any WelcomeService = MizonWelcomeService(api: fixture.api, cacheRoot: fixture.cacheRoot,
                                                               welcomeAvatarTimeout: 0.25, homeAvatarTimeout: 2)
        try await fixture.api.setToken(fixture.session.accessToken)
        #expect(try await service.avatar(for: fixture.avatarID, session: fixture.session) == nil)
        let image = try #require(await service.homeAvatar(for: fixture.avatarID, session: fixture.session))
        #expect(image.width == 240)
        #expect(image.height == 144)
        let downloads = NearbyArtworkProtocol.requests.filter { $0.url?.path == "/api/Medias/MediaContent" }
        #expect(downloads.count == 2)
        #expect(downloads.allSatisfy { $0.value(forHTTPHeaderField: "Range") == "bytes=0-\(fixture.imageData.count - 1)" })
    }

    @Test func sharesTheAuthenticatedGLBDownloadBetweenArtistPreviews() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let id = UUID()
        let bytes = Data([0x67, 0x6C, 0x54, 0x46, 2, 0, 0, 0, 24, 0, 0, 0,
                          4, 0, 0, 0, 0x4A, 0x53, 0x4F, 0x4E, 0x7B, 0x7D, 0x20, 0x20])
        NearbyArtworkProtocol.install { request in
            #expect(request.query("MediaPublicId").flatMap(UUID.init(uuidString:)) == id)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access")
            switch request.url?.path {
            case "/api/Medias/Media":
                let media = MediaResponse(mediaPublicId: id, totalChunks: 1, chunkSize: bytes.count,
                    fileName: "artist.glb", fileSize: Int64(bytes.count), storagePath: "file:///C:/Models/artist.glb")
                return .init(body: try MizonJSON.encoder().encode(BaseApiResponse(content: media)))
            case "/api/Medias/MediaContent":
                #expect(request.value(forHTTPHeaderField: "Range") == "bytes=0-23")
                return .init(status: 206, body: bytes, headers: [
                    "Content-Type": "model/gltf-binary", "Content-Range": "bytes 0-23/24"
                ])
            default:
                Issue.record("Unexpected artist model fixture URL path")
                return .init(status: 404, body: Data())
            }
        }
        try await fixture.api.setToken(fixture.session.accessToken)

        async let spotlight = fixture.artwork.artistModelFile(id, session: fixture.session)
        async let profile = fixture.artwork.artistModelFile(id, session: fixture.session)
        let (spotlightFile, profileFile) = try await (spotlight, profile)

        #expect(spotlightFile == profileFile)
        #expect(try Data(contentsOf: profileFile) == bytes)
        #expect(NearbyArtworkProtocol.requests.filter { $0.url?.path == "/api/Medias/MediaContent" }.count == 1)
    }

    @Test func invalidIdentityAndStaleSessionsDoNotContactTheServer() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        NearbyArtworkProtocol.install(fixture.reply)
        #expect(try await fixture.service.image(for: "private@example.test", session: fixture.session, artwork: fixture.artwork) == nil)
        await #expect(throws: CancellationError.self) {
            try await fixture.service.image(for: "target.user", session: fixture.session, artwork: fixture.artwork)
        }
        #expect(NearbyArtworkProtocol.requests.isEmpty)
        #expect(await fixture.api.getToken() == nil)
    }

    @Test func rejectsProfilesWhoseUsernameChangedAfterSearch() async throws {
        let fixture = try Fixture(profileUsername: "different.user")
        defer { fixture.close() }
        NearbyArtworkProtocol.install(fixture.reply)
        try await fixture.api.setToken(fixture.session.accessToken)
        #expect(try await fixture.service.image(for: "target.user", session: fixture.session, artwork: fixture.artwork) == nil)
        #expect(NearbyArtworkProtocol.requests.map { $0.url?.path } == ["/api/Search/Global", "/api/Clients/ClientProfile"])
    }

    @Test func cancellingAvatarDownloadDoesNotCancelOtherArtwork() async throws {
        let fixture = try Fixture(stallAvatar: true)
        defer { fixture.close() }
        NearbyArtworkProtocol.install(fixture.reply)
        try await fixture.api.setToken(fixture.session.accessToken)

        let avatar = Task { try await fixture.service.image(for: "target.user", session: fixture.session, artwork: fixture.artwork) }
        defer { avatar.cancel() }
        try await waitFor { NearbyArtworkProtocol.requests.contains { request in
            request.url?.path == "/api/Medias/MediaContent" && UUID(uuidString: request.query("MediaPublicId") ?? "") == fixture.avatarID
        } }

        async let other = fixture.artwork.image(fixture.otherArtworkID, session: fixture.session)
        avatar.cancel()
        await #expect(throws: CancellationError.self) { try await avatar.value }
        #expect(try await other.width == 320)
        try await waitFor { NearbyArtworkProtocol.cancelled.contains { request in
            request.url?.path == "/api/Medias/MediaContent" && UUID(uuidString: request.query("MediaPublicId") ?? "") == fixture.avatarID
        } }
    }

    private func waitFor(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = try #require(predicate(), "Expected the synthetic request or cancellation")
    }

    private struct Fixture: Sendable {
        let session = AuthSession(accessToken: "fixture-access", refreshToken: "fixture-refresh", sessionPublicId: UUID(),
            clientPublicId: UUID(), identifier: "viewer", server: URL(string: "https://mizon.example/api")!)
        let cacheRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        let exactClientID = UUID()
        let avatarID = UUID()
        let otherArtworkID = UUID()
        let searchOnlyMediaID = UUID()
        let api: MizonApi
        let service: NearbyProfileArtworkService
        let artwork: MusicArtworkStore
        let imageData: Data
        let profileUsername: String
        let stallAvatar: Bool
        private let http: URLSession

        init(profileUsername: String = "Target.User", stallAvatar: Bool = false) throws {
            self.profileUsername = profileUsername
            self.stallAvatar = stallAvatar
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [NearbyArtworkProtocol.self]
            http = URLSession(configuration: configuration)
            api = MizonApi(session: http)
            let music = MusicHomeService(api: api)
            service = music.nearbyProfileArtworkService
            artwork = MusicArtworkStore(service: music, session: session, cacheRoot: cacheRoot)
            let drawing = try #require(CGContext(data: nil, width: 320, height: 192, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            drawing.setFillColor(red: 0.6, green: 0.2, blue: 0.8, alpha: 1)
            drawing.fill(CGRect(x: 0, y: 0, width: 320, height: 192))
            let image = try #require(drawing.makeImage())
            let data = NSMutableData()
            let output = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(output, image, nil)
            try #require(CGImageDestinationFinalize(output))
            imageData = data as Data
        }

        func close() {
            http.invalidateAndCancel()
            try? FileManager.default.removeItem(at: cacheRoot)
        }

        func reply(_ request: URLRequest) throws -> NearbyArtworkProtocol.Reply {
            let encoder = MizonJSON.encoder()
            switch request.url?.path {
            case "/api/Clients/Me":
                return .init(body: try encoder.encode(BaseApiResponse(content: MeResponse(
                    username: "viewer", meProfile: .init(mediaPublicId: avatarID)
                ))))
            case "/api/Search/Global":
                let lines = [
                    GlobalSearchItemResponse(itemType: "Client", publicId: UUID(), username: "wrong.user", nickName: "target.user"),
                    GlobalSearchItemResponse(itemType: "Music", publicId: UUID(), username: "target.user", title: "target.user"),
                    GlobalSearchItemResponse(itemType: "Client", publicId: UUID(), firstName: "target.user"),
                    GlobalSearchItemResponse(itemType: "Client", publicId: exactClientID, username: "TARGET.USER",
                                             profileMediaPublicId: searchOnlyMediaID)
                ]
                var payload = Data()
                for line in lines {
                    payload.append(try encoder.encode(line))
                    payload.append(0x0A)
                }
                return .init(body: payload, headers: ["Content-Type": "application/x-ndjson"])
            case "/api/Clients/ClientProfile":
                let profile = ClientProfileResponse(clientPublicId: exactClientID, username: profileUsername, profileMediaPublicId: avatarID)
                return .init(body: try encoder.encode(BaseApiResponse(content: profile)))
            case "/api/Medias/Media":
                let id = try #require(UUID(uuidString: request.query("MediaPublicId") ?? ""))
                let media = MediaResponse(mediaPublicId: id, totalChunks: 1, chunkSize: imageData.count,
                    fileName: "fixture.png", fileSize: Int64(imageData.count), storagePath: "file:///C:/Mizon/fixture.png")
                return .init(body: try encoder.encode(BaseApiResponse(content: media)))
            case "/api/Medias/MediaContent":
                let id = UUID(uuidString: request.query("MediaPublicId") ?? "")
                return .init(status: 206, body: stallAvatar && id == avatarID ? nil : imageData,
                    headers: ["Content-Range": "bytes 0-\(imageData.count - 1)/\(imageData.count)"])
            default:
                Issue.record("Unexpected fixture URL path")
                return .init(status: 404, body: Data())
            }
        }
    }
}

private extension URLRequest {
    func query(_ name: String) -> String? {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.first { $0.name == name }?.value
    }
}

private final class NearbyArtworkProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status = 200
        let body: Data?
        var headers = ["Content-Type": "application/json"]
        var delay: TimeInterval?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) throws -> Reply)?
    nonisolated(unsafe) private static var started: [URLRequest] = []
    nonisolated(unsafe) private static var stopped: [URLRequest] = []
    private let deliveryLock = NSLock()
    private var delayedDelivery: DispatchWorkItem?

    static var requests: [URLRequest] { lock.withLock { started } }
    static var cancelled: [URLRequest] { lock.withLock { stopped } }

    static func install(_ newHandler: @escaping @Sendable (URLRequest) throws -> Reply) {
        lock.withLock {
            handler = newHandler
            started = []
            stopped = []
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.lock.withLock {
            Self.started.append(request)
            return Self.handler
        }
        do {
            guard let reply = try handler?(request), let body = reply.body, let url = request.url else { return }
            if let delay = reply.delay {
                let delivery = DispatchWorkItem { [weak self] in self?.deliver(reply, url: url, body: body) }
                deliveryLock.withLock { delayedDelivery = delivery }
                DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: delivery)
            } else {
                deliver(reply, url: url, body: body)
            }
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    override func stopLoading() {
        deliveryLock.withLock { delayedDelivery?.cancel(); delayedDelivery = nil }
        Self.lock.withLock { Self.stopped.append(request) }
    }

    private func deliver(_ reply: Reply, url: URL, body: Data) {
        guard let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                             headerFields: reply.headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
