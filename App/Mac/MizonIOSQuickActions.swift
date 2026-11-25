#if os(iOS)
import MizonAppleUI
import UIKit

@MainActor
enum MizonIOSQuickActions {
    private static let typePrefix = "com.shahesmaeili.Mizon.Apple.shortcut."

    static func publish(_ entries: [ShellShortcutEntry]) {
        guard !entries.isEmpty else { return }
        UIApplication.shared.shortcutItems = entries.map { entry in
            UIApplicationShortcutItem(
                type: typePrefix + entry.destination.rawValue,
                localizedTitle: entry.title,
                localizedSubtitle: entry.subtitle,
                icon: UIApplicationShortcutIcon(systemImageName: entry.symbol),
                userInfo: nil
            )
        }
    }

    @discardableResult
    static func activate(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        let type = shortcutItem.type
        guard type.hasPrefix(typePrefix),
              let destination = ShellShortcutDestination(rawValue: String(type.dropFirst(typePrefix.count))) else {
            return false
        }
        MizonShellShortcuts.shared.request(destination)
        return true
    }
}

final class MizonIOSApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = MizonIOSShortcutSceneDelegate.self
        }
        return configuration
    }
}

final class MizonIOSShortcutSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let item = options.shortcutItem {
            MizonIOSQuickActions.activate(item)
        }
        openURLContexts(options.urlContexts)
    }

    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        openURLContexts(contexts)
    }

    private func openURLContexts(_ contexts: Set<UIOpenURLContext>) {
        for context in contexts { MizonDeepLinkRouter.shared.open(context.url) }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        MizonIOSQuickActions.activate(shortcutItem)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        MizonIOSQuickActions.publish(MizonShellShortcuts.shared.entries)
    }
}
#endif
