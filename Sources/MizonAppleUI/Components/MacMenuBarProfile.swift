#if os(macOS)
import AppKit
import MizonAPIClient
import MizonAppleCore
import SwiftUI

@MainActor
public final class MacMenuBarProfile: ObservableObject {
    public static let shared = MacMenuBarProfile()
    static let preferenceKey = "mizon.menuBarProfile"

    struct Avatar: Equatable {
        let mediaID: UUID?
        let image: CGImage?

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.mediaID == rhs.mediaID && lhs.image === rhs.image
        }

        mutating func update(_ incoming: Self) {
            // A Welcome timeout says nothing about the last image for this media ID.
            guard incoming.mediaID == nil || incoming.mediaID != mediaID || incoming.image != nil else { return }
            self = incoming
        }
    }

    struct Presentation {
        struct Mood {
            let emoji: String
            let title: String
            let accessibilityTitle: String
            let loop: URL?
        }

        let displayName: String
        let avatar: CGImage?
        let profileTitle: String
        let profileStatus: String
        let isOnline: Bool
        let isOpening: Bool
        let mood: Mood?
    }

    private struct Account {
        let session: AuthSession
        let service: MusicHomeService
        var artwork: MusicArtworkStore
        let displayName: String
        var avatar: Avatar
        var mood: ClientMoodItemResponse?
    }

    public var activateMainWindow: (() -> Void)?
    public var keepsApplicationRunning: Bool { enabled && account != nil }

    private var currentMood: ClientMoodItemResponse? {
        guard let mood = account?.mood, mood.publicId != .emptyMediaID,
              !mood.emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return mood
    }

    private var enabled = UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
    private var account: Account?
    private var language = "en"
    private var openFailed = false
    private var openRequestID: UUID?
    private var openTask: Task<Void, Never>?
    private var moodLoad: Task<Void, Never>?
    private var loopFile: URL?
    private var effectFile: URL?
    private var effectRequestDeadline: ContinuousClock.Instant?
    private var presence: AccountPresenceCoordinator?
    private var presenceGeneration = UUID()
    private var appWindowActive = false
    private var accountBusy = false
    @Published private(set) var online = false
    private lazy var items = MacProfileStatusItems(
        openProfile: { [weak self] in self?.requestProfile() },
        playMood: { [weak self] in self?.playEffect() }
    )

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        if !enabled { cancelProfileRequest() }
        prepareMood()
        render()
    }

    public func setAppWindowActive(_ active: Bool) {
        guard appWindowActive != active else { return }
        appWindowActive = active
        presence?.setWindowActive(active)
    }

    func present(session: AuthSession, service: MusicHomeService, artwork: MusicArtworkStore,
                 displayName: String, avatar: Avatar, mood: ClientMoodItemResponse?, isPersian: Bool) {
        language = isPersian ? "fa" : "en"
        if account?.session.sessionPublicId == session.sessionPublicId {
            account?.artwork = artwork
            account?.avatar.update(avatar)
            updateMood(mood, sessionID: session.sessionPublicId)
            return
        }
        clear()
        account = Account(session: session, service: service, artwork: artwork,
                          displayName: displayName, avatar: avatar, mood: mood)
        configurePresence()
        prepareMood()
        render()
    }

    func retainOnlySession(_ sessionID: UUID?) {
        if let account, account.session.sessionPublicId != sessionID {
            clear()
            render()
        }
    }

    func updateAvatar(_ avatar: Avatar, sessionID: UUID) {
        guard account?.session.sessionPublicId == sessionID else { return }
        account?.avatar.update(avatar)
        render()
    }

    func updateMood(_ mood: ClientMoodItemResponse?, sessionID: UUID) {
        guard account?.session.sessionPublicId == sessionID else { return }
        let previous = account?.mood
        account?.mood = mood
        if previous?.publicId != mood?.publicId || previous?.animationMediaPublicId != mood?.animationMediaPublicId
            || previous?.effectMediaPublicIds != mood?.effectMediaPublicIds {
            prepareMood()
        }
        render()
    }

    func setAccountBusy(_ busy: Bool) { accountBusy = busy }

    func setLanguage(isPersian: Bool) {
        language = isPersian ? "fa" : "en"
        if account != nil { render() }
    }

    private func requestProfile() {
        guard enabled, !accountBusy, let account, openRequestID == nil, let activateMainWindow else { return }
        let id = UUID()
        let route: MizonDeepLink = account.session.clientPublicId == .emptyMediaID ? .music : .client(account.session.clientPublicId)
        openFailed = false
        openRequestID = id
        render()
        activateMainWindow()
        openTask = Task { [weak self] in
            let response = await MizonDeepLinkRouter.shared.result(for: route, requestID: id)
            guard let self, self.openRequestID == id, !Task.isCancelled else { return }
            self.openRequestID = nil
            self.openTask = nil
            self.openFailed = !response.success
            self.render()
        }
    }

    private func cancelProfileRequest() {
        openRequestID = nil
        openTask?.cancel()
        openTask = nil
        openFailed = false
    }

    private func clear() {
        account = nil
        cancelProfileRequest()
        configurePresence()
        prepareMood()
    }

    private func configurePresence() {
        disposePresence()
        guard let account else { return }
        let generation = presenceGeneration
        let observer = AccountPresenceCoordinator(socket: account.service.makeWindowPresenceSocket(session: account.session),
                                                  clientPublicID: account.session.clientPublicId) { [weak self] active in
            guard let self, self.presenceGeneration == generation else { return }
            self.online = active
            self.render()
        }
        presence = observer
        observer.setWindowActive(appWindowActive)
        observer.observeAccount()
    }

    private func disposePresence() {
        let previous = presence
        presence = nil
        presenceGeneration = UUID()
        if online { online = false }
        if let previous { Task { await previous.stop() } }
    }

    private func prepareMood() {
        stopEffect()
        moodLoad?.cancel()
        moodLoad = nil
        loopFile = nil
        effectFile = nil
        guard enabled, let account, let mood = currentMood else { return }
        let loopID = mood.animationMediaPublicId
        let effectID = mood.effectMediaPublicIds.filter { $0 != .emptyMediaID }.randomElement() ?? loopID
        moodLoad = Task { [weak self, artwork = account.artwork, session = account.session] in
            if loopID == effectID {
                let file = await Self.loadMoodAsset(loopID, artwork: artwork, session: session)
                guard !Task.isCancelled else { return }
                self?.didLoadLoop(file)
                self?.didLoadEffect(file)
            } else {
                async let effect = Self.loadMoodAsset(effectID, artwork: artwork, session: session)
                let loop = await Self.loadMoodAsset(loopID, artwork: artwork, session: session)
                guard !Task.isCancelled else { return }
                self?.didLoadLoop(loop)
                let file = await effect
                if !Task.isCancelled { self?.didLoadEffect(file) }
            }
        }
    }

    private static func loadMoodAsset(_ id: UUID, artwork: MusicArtworkStore, session: AuthSession) async -> URL? {
        guard id != .emptyMediaID else { return nil }
        return try? await artwork.moodAnimationURL(id, session: session)
    }

    private func didLoadLoop(_ file: URL?) {
        loopFile = file
        render()
    }

    private func didLoadEffect(_ file: URL?) {
        moodLoad = nil
        effectFile = file
        if let deadline = effectRequestDeadline, ContinuousClock.now < deadline,
           let file, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            items.showEffect(file: file)
        }
        effectRequestDeadline = nil
    }

    func playEffect() {
        guard enabled, currentMood != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        if let effectFile { items.showEffect(file: effectFile) }
        else if moodLoad != nil { effectRequestDeadline = ContinuousClock.now.advanced(by: .seconds(25)) }
    }

    private func stopEffect() {
        effectRequestDeadline = nil
        items.stopEffect()
    }

    private func render() {
        guard enabled, let account else {
            items.render(profile: nil)
            return
        }
        let status = openRequestID != nil ? "Opening" : openFailed ? "OpenFailed" : online ? "Online" : "Offline"
        let mood: Presentation.Mood? = currentMood.map { mood in
            let emoji = mood.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
            let persian = mood.persianTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let english = mood.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let localized = language == "fa" && persian?.isEmpty == false ? persian ?? english : english
            let title = localized.isEmpty ? emoji : localized
            return Presentation.Mood(emoji: emoji, title: title,
                                     accessibilityTitle: String(format: text("PlayMood"), title), loop: loopFile)
        }
        items.render(profile: Presentation(displayName: account.displayName, avatar: account.avatar.image,
                                           profileTitle: text("OpenProfile"), profileStatus: text(status),
                                           isOnline: online, isOpening: openRequestID != nil, mood: mood))
    }

    private func text(_ key: String) -> String {
        AuthLocalization.string(key, table: "MenuBarProfile", language: language)
    }
}

private extension UUID {
    static let emptyMediaID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}
#endif
