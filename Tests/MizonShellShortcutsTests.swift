#if os(macOS) || os(iOS)
import Testing
@testable import MizonAppleUI

struct MizonShellShortcutsTests {
    @MainActor @Test func publishesTheWindowsOrderForEachAccountAndLanguage() {
        let shortcuts = MizonShellShortcuts()
        #expect(shortcuts.entries.isEmpty)

        shortcuts.configure(signedIn: false, language: "en")
        #expect(shortcuts.groupTitle == "Mizon account")
        #expect(shortcuts.entries.map(\.destination) == [.login, .register])
        #expect(shortcuts.entries.map(\.title) == ["Sign in", "Create an account"])

        shortcuts.configure(signedIn: true, language: "fa")
        #expect(shortcuts.groupTitle == "بخش‌های میزون")
        #expect(shortcuts.entries.map(\.destination) == [.music, .movies, .apps, .vpn])
        #expect(shortcuts.entries.map(\.title) == ["موسیقی", "فیلم و سریال", "برنامه‌ها", "VPN"])
        #expect(shortcuts.entries.allSatisfy { !$0.subtitle.isEmpty && !$0.symbol.isEmpty })

        shortcuts.configure(signedIn: true, language: "en")
        #expect(shortcuts.entries.map(\.title) == ["Music", "Movies and TV", "Apps", "VPN"])
    }

    @Test func waitsForAnAuthenticatedDestinationAndRespectsAuthenticationInProgress() {
        #expect(ShellShortcutContext.restoring.action(for: .music) == .wait)
        #expect(ShellShortcutContext.preparingHome.action(for: .vpn) == .wait)
        #expect(ShellShortcutContext.signedOut.action(for: .apps) == .showSignIn)
        #expect(ShellShortcutContext.home.action(for: .movies) == .section)
        #expect(ShellShortcutContext.home.action(for: .login) == .account)
        #expect(ShellShortcutContext.signedOut.action(for: .register) == .account)
        #expect(ShellShortcutContext.busy.action(for: .register) == .wait)
        #expect(ShellShortcutContext.signingOut.action(for: .music) == .discard)
    }

    @MainActor @Test func completingAnOldRequestKeepsTheNewestShortcutPending() throws {
        let shortcuts = MizonShellShortcuts()
        shortcuts.request(.music)
        let old = try #require(shortcuts.pending)

        shortcuts.request(.register)
        let latest = try #require(shortcuts.pending)
        shortcuts.complete(old)
        #expect(shortcuts.pending == latest)
        #expect(latest.destination == .register)

        shortcuts.complete(latest)
        #expect(shortcuts.pending == nil)
    }
}
#endif
