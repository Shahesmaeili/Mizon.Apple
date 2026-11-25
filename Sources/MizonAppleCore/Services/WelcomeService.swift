import CoreGraphics
import Foundation
import ImageIO
import MizonAPI
import MizonAPIClient

public enum WelcomeFailure: Error, Equatable {
    case sessionExpired
    case accountUnavailable
}

public struct WelcomeAccount: Sendable {
    public let displayName: String
    public let publicUsername: String?
    public let avatarID: UUID?
    public let mood: ClientMoodItemResponse?

    public init(displayName: String, avatarID: UUID?, mood: ClientMoodItemResponse? = nil, publicUsername: String? = nil) {
        self.displayName = displayName
        self.publicUsername = publicUsername
        self.avatarID = avatarID
        self.mood = mood
    }

    init(_ response: MeResponse) {
        let fullName = "\(response.firstName) \(response.lastName)"
        displayName = [response.nickName, fullName, response.username]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
        publicUsername = response.username
        avatarID = response.meProfile?.mediaPublicId
        mood = response.currentMood
    }
}

public protocol WelcomeService: Sendable {
    func account(for session: AuthSession) async throws -> WelcomeAccount
    func avatar(for mediaID: UUID, session: AuthSession) async throws -> CGImage?
    func homeAvatar(for mediaID: UUID, session: AuthSession) async throws -> CGImage?
}

public extension WelcomeService {
    func homeAvatar(for mediaID: UUID, session: AuthSession) async throws -> CGImage? {
        try await avatar(for: mediaID, session: session)
    }
}

public struct MizonWelcomeService: WelcomeService {
    private static let legacyMediaChunkSize = 81_920
    private let api: MizonApi
    private let downloader: MediaDownloader
    private let welcomeAvatarTimeout: TimeInterval
    private let homeAvatarTimeout: TimeInterval

    public init(api: MizonApi, cacheRoot: URL = URL.cachesDirectory.appending(path: "Mizon/Media")) {
        self.init(api: api, cacheRoot: cacheRoot, welcomeAvatarTimeout: 4, homeAvatarTimeout: 10)
    }

    init(api: MizonApi, cacheRoot: URL, welcomeAvatarTimeout: TimeInterval, homeAvatarTimeout: TimeInterval) {
        self.api = api
        downloader = MediaDownloader(cacheRoot: cacheRoot)
        self.welcomeAvatarTimeout = welcomeAvatarTimeout
        self.homeAvatarTimeout = homeAvatarTimeout
    }

    public func account(for session: AuthSession) async throws -> WelcomeAccount {
        let response = await api.sendRequest(MeOperation(.init(), endpoints: Endpoints(baseURL: session.server)))
        try Task.checkCancellation()
        if response.error?.code == 401 || response.error?.code == 20000 { throw WelcomeFailure.sessionExpired }
        guard response.isSuccess, let content = response.content else { throw WelcomeFailure.accountUnavailable }
        return WelcomeAccount(content)
    }

    public func avatar(for mediaID: UUID, session: AuthSession) async throws -> CGImage? {
        try await loadAvatar(for: mediaID, session: session, timeout: welcomeAvatarTimeout)
    }

    public func homeAvatar(for mediaID: UUID, session: AuthSession) async throws -> CGImage? {
        try await loadAvatar(for: mediaID, session: session, timeout: homeAvatarTimeout)
    }

    private func loadAvatar(for mediaID: UUID, session: AuthSession, timeout: TimeInterval) async throws -> CGImage? {
        guard mediaID != UUID.emptyPublicIdentifier else { return nil }
        try await checkAvatarSession(session)
        return try await withThrowingTaskGroup(of: CGImage?.self) { group in
            group.addTask {
                let endpoints = Endpoints(baseURL: session.server)
                var operation = MediaOperation(.init(mediaPublicId: mediaID), endpoints: endpoints)
                operation.apiRequest.callTimeoutDuration = timeout
                let response = await api.sendRequest(operation)
                try await checkAvatarSession(session)
                guard response.isSuccess, var media = response.content, media.mediaPublicId == mediaID,
                      media.fileSize > 0, media.fileSize <= 24 * 1024 * 1024 else { return nil }
                // Match the Windows downloader's default for older registered media.
                if media.chunkSize <= 0 { media.chunkSize = Self.legacyMediaChunkSize }
                let path = try await downloader.downloadToCache(media, api: api, endpoints: endpoints)
                try await checkAvatarSession(session)
                guard let source = CGImageSourceCreateWithURL(path as CFURL, [
                    kCGImageSourceShouldCache: false
                ] as CFDictionary) else { return nil }
                let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 240,
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary)
                try await checkAvatarSession(session)
                return image
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                return nil
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
    }

    private func checkAvatarSession(_ session: AuthSession) async throws {
        try Task.checkCancellation()
        guard !session.accessToken.isEmpty, await api.getToken() == session.accessToken else { throw CancellationError() }
        try Task.checkCancellation()
    }
}
