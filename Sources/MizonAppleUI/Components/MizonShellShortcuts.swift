#if os(macOS) || os(iOS)
import SwiftUI

public enum ShellShortcutDestination: String, Sendable {
    case login, register, music, movies, apps, vpn

    var isAccount: Bool { self == .login || self == .register }

    var resourceKey: String {
        switch self {
        case .login: "Login"
        case .register: "Register"
        case .music: "Music"
        case .movies: "Movies"
        case .apps: "Apps"
        case .vpn: "Vpn"
        }
    }

    var symbol: String {
        switch self {
        case .login: "person.crop.circle"
        case .register: "person.badge.plus"
        case .music: "headphones"
        case .movies: "film"
        case .apps: "square.grid.2x2"
        case .vpn: "shield"
        }
    }
}

public struct ShellShortcutEntry: Equatable, Sendable {
    public let destination: ShellShortcutDestination
    public let title: String
    public let subtitle: String
    public let symbol: String
}

struct ShellShortcutRequest: Equatable, Identifiable {
    let id: UUID
    let destination: ShellShortcutDestination

    init(id: UUID = UUID(), destination: ShellShortcutDestination) {
        self.id = id
        self.destination = destination
    }
}

enum ShellShortcutContext: Equatable {
    case restoring, signedOut, preparingHome, home, busy, signingOut

    enum Action: Equatable { case wait, discard, showSignIn, account, section }

    func action(for destination: ShellShortcutDestination) -> Action {
        switch self {
        case .signingOut: return .discard
        case .busy: return .wait
        case _ where destination.isAccount: return .account
        case .signedOut: return .showSignIn
        case .home: return .section
        case .restoring, .preparingHome: return .wait
        }
    }
}

@MainActor
public final class MizonShellShortcuts: ObservableObject {
    public static let shared = MizonShellShortcuts()
    @Published public private(set) var entries: [ShellShortcutEntry] = []
    @Published private(set) var pending: ShellShortcutRequest?
    public private(set) var groupTitle = ""

    public func request(_ destination: ShellShortcutDestination) {
        pending = ShellShortcutRequest(destination: destination)
    }

    func complete(_ request: ShellShortcutRequest) {
        if pending == request { pending = nil }
    }

    func configure(signedIn: Bool, language: String) {
        let destinations: [ShellShortcutDestination] = signedIn ? [.music, .movies, .apps, .vpn] : [.login, .register]
        groupTitle = AuthLocalization.string(signedIn ? "MainGroup" : "AccountGroup", table: "ShellShortcuts", language: language)
        let localized = destinations.map { destination in
            ShellShortcutEntry(
                destination: destination,
                title: AuthLocalization.string(destination.resourceKey + "Title", table: "ShellShortcuts", language: language),
                subtitle: AuthLocalization.string(destination.resourceKey + "Description", table: "ShellShortcuts", language: language),
                symbol: destination.symbol
            )
        }
        if entries != localized { entries = localized }
    }
}
#endif
