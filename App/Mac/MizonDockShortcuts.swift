#if os(macOS)
import AppKit
import MizonAppleUI

@MainActor
final class MizonDockShortcuts: NSObject {
    private let shortcuts = MizonShellShortcuts.shared
    var reopenMainWindow: (() -> Void)?

    func menu() -> NSMenu? {
        let entries = shortcuts.entries
        guard !entries.isEmpty else { return nil }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(.sectionHeader(title: shortcuts.groupTitle))
        for entry in entries {
            let item = NSMenuItem(title: entry.title, action: action(for: entry.destination), keyEquivalent: "")
            item.target = self
            item.subtitle = entry.subtitle
            item.image = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil)
            if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
            menu.addItem(item)
        }
        return menu
    }

    // The Dock invokes our target's selector and need not pass back the original menu item.
    private func action(for destination: ShellShortcutDestination) -> Selector {
        switch destination {
        case .login: #selector(openLogin)
        case .register: #selector(openRegistration)
        case .music: #selector(openMusic)
        case .movies: #selector(openMovies)
        case .apps: #selector(openApps)
        case .vpn: #selector(openVPN)
        }
    }

    @objc private func openLogin() { open(.login) }
    @objc private func openRegistration() { open(.register) }
    @objc private func openMusic() { open(.music) }
    @objc private func openMovies() { open(.movies) }
    @objc private func openApps() { open(.apps) }
    @objc private func openVPN() { open(.vpn) }

    private func open(_ destination: ShellShortcutDestination) {
        shortcuts.request(destination)
        activateMainWindow()
    }

    func activateMainWindow() {
        let app = NSApplication.shared
        if app.isHidden { app.unhide(nil) }
        app.activate()
        if let window = app.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            reopenMainWindow?()
        }
    }
}
#endif
