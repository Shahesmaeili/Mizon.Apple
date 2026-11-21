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
    public let avatarID: UUID?
    public let mood: ClientMoodItemResponse?

    public init(displayName: String, avatarID: UUID?, mood: ClientMoodItemResponse? = nil) {
        self.displayName = displayName
        self.avatarID = avatarID
        self.mood = mood
    }

    init(_ response: MeResponse) {
        let fullName = "\(response.firstName) \(response.lastName)"
        displayName = [response.nickName, fullName, response.username]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
        avatarID = response.meProfile?.mediaPublicId
        mood = response.currentMood
    }
}

public protocol WelcomeService: Sendable {
    func account(for session: AuthSession) async throws -> WelcomeAccount
    func avatar(for mediaID: UUID, session: AuthSession) async throws -> CGImage?
}

public struct MizonWelcomeService: WelcomeService {
    private let api: MizonApi
    private let downloader: MediaDownloader

    public init(api: MizonApi, cacheRoot: URL = URL.cachesDirectory.appending(path: "Mizon/Media")) {
        self.api = api
        downloader = MediaDownloader(cacheRoot: cacheRoot)
    }

    public func account(for session: AuthSession) async throws -> WelcomeAccount {
        let response = await api.sendRequest(MeOperation(.init(), endpoints: Endpoints(baseURL: session.server)))
        try Task.checkCancellation()
        if response.error?.code == 401 || response.error?.code == 20000 { throw WelcomeFailure.sessionExpired }
        guard response.isSuccess, let content = response.content else { throw WelcomeFailure.accountUnavailable }
        return WelcomeAccount(content)
    }

    public func avatar(for mediaID: UUID, session: AuthSession) async throws -> CGImage? {
        try await withThrowingTaskGroup(of: CGImage?.self) { group in
            group.addTask {
                var operation = MediaOperation(.init(mediaPublicId: mediaID), endpoints: Endpoints(baseURL: session.server))
                operation.apiRequest.callTimeoutDuration = 4
                let response = await api.sendRequest(operation)
                try Task.checkCancellation()
                guard response.isSuccess, let media = response.content,
                      let storage = URL(string: media.storagePath), storage.scheme?.lowercased() == "https",
                      storage.host != nil else { return nil }
                let path = try await downloader.downloadToCache(media, storageURL: storage)
                try Task.checkCancellation()
                guard let image = CGImageSourceCreateWithURL(path as CFURL, nil) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(image, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 240
                ] as CFDictionary)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(4))
                return nil
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
    }
}
