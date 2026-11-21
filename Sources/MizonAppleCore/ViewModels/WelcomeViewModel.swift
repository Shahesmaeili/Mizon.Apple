import CoreGraphics
import Foundation
import Observation

@MainActor @Observable
public final class WelcomeViewModel {
    public enum Stage: String, Sendable {
        case initial, checking, profile, ready
        case connectionError = "connection_error"
    }

    public enum Destination: Sendable {
        case login
        case home(AuthSession)
    }

    public private(set) var stage: Stage = .initial
    public private(set) var isBusy = false
    public private(set) var account: WelcomeAccount?
    public private(set) var avatar: CGImage?
    @ObservationIgnored private let service: any WelcomeService

    public init(service: any WelcomeService) {
        self.service = service
    }

    public func prepare(onAccount: (AuthSession, WelcomeAccount) -> Void = { _, _ in },
                        session: () async throws -> AuthSession?) async -> Destination? {
        guard !isBusy else { return nil }
        isBusy = true
        stage = .checking
        account = nil
        avatar = nil
        defer { isBusy = false }

        do {
            guard let session = try await session() else {
                try Task.checkCancellation()
                return .login
            }
            try Task.checkCancellation()
            let account = try await service.account(for: session)
            try Task.checkCancellation()
            self.account = account
            stage = .profile
            onAccount(session, account)
            if let avatarID = account.avatarID {
                avatar = try? await service.avatar(for: avatarID, session: session)
            }
            try Task.checkCancellation()
            stage = .ready
            return .home(session)
        } catch is CancellationError {
            return nil
        } catch {
            guard !Task.isCancelled else { return nil }
            if error as? WelcomeFailure == .sessionExpired { return .login }
            stage = .connectionError
            return nil
        }
    }

    public func showConnectionError() {
        stage = .connectionError
    }
}
