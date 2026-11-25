import SwiftUI
import MizonAppleCore
import MizonAppleUI
#if os(macOS)
import AppKit
import OSLog
#endif

@main
enum MizonEntryPoint {
    @MainActor
    static func main() {
        #if os(macOS)
        guard let lock = MizonSingleInstance.acquire() else { return }
        defer { close(lock) }
        #endif
        MizonApp.main()
    }
}

struct MizonApp: App {
    @State private var model = ApplicationServices.makeLoginViewModel()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MizonApplicationDelegate.self) private var appDelegate
    #elseif os(iOS)
    @UIApplicationDelegateAdaptor(MizonIOSApplicationDelegate.self) private var appDelegate
    #endif
    var body: some Scene {
        #if os(macOS)
        Window("Mizon", id: "main") {
            MizonMacWindowContent(model: model, shortcuts: appDelegate.dockShortcuts)
                .frame(minWidth: 340, minHeight: 350)
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1000, height: 700)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .commands { CommandGroup(replacing: .newItem) {} }
        Settings { ServerSettingsView(model: model) }
        #else
        WindowGroup("Mizon") {
            MizonRootView(model: model)
                #if os(iOS)
                .onReceive(MizonShellShortcuts.shared.$entries) { MizonIOSQuickActions.publish($0) }
                #endif
        }
        #endif
    }
}
#if os(macOS)
private struct MizonMacWindowContent: View {
    let model: LoginViewModel
    let shortcuts: MizonDockShortcuts
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MizonRootView(model: model)
            .onAppear {
                shortcuts.reopenMainWindow = { [openWindow] in openWindow(id: "main") }
                MacMenuBarProfile.shared.activateMainWindow = { [weak shortcuts] in shortcuts?.activateMainWindow() }
                MizonDeepLinkRouter.shared.activateMainWindow = { [weak shortcuts] in shortcuts?.activateMainWindow() }
                updateWindowActivity()
            }
            .onDisappear { MacMenuBarProfile.shared.mainWindowClosed() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in updateWindowActivity() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in updateWindowActivity() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in updateWindowActivity() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in updateWindowActivity() }
    }

    private func updateWindowActivity() {
        let window = NSApp.keyWindow
        let active = NSApp.isActive && window?.identifier?.rawValue == "main" && window?.isVisible == true
        MacMenuBarProfile.shared.setMainWindowActive(active)
    }
}

@MainActor
private enum MizonSingleInstance {
    private static let bundleID = "com.shahesmaeili.Mizon.Apple"
    private static let logger = Logger(subsystem: bundleID, category: "Launch")

    static func acquire() -> Int32? {
        let directory = URL.applicationSupportDirectory.appending(path: bundleID, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("Cannot create the instance lock directory: \(error.localizedDescription)")
            return nil
        }
        let path = directory.appending(path: "instance.lock").path
        let lock = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard lock >= 0 else {
            logger.error("Cannot open the instance lock (errno \(errno)).")
            return nil
        }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(lock)
            if code == EWOULDBLOCK {
                if let app = otherInstance() { activate(app) }
            } else {
                logger.error("Cannot acquire the instance lock (errno \(code)).")
            }
            return nil
        }

        // Older builds may already be open without holding the lock.
        if let app = otherInstance(finishedLaunching: true) {
            activate(app)
            close(lock)
            return nil
        }
        return lock
    }

    private static func otherInstance(finishedLaunching: Bool = false) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            guard let identifier = app.bundleIdentifier, app.processIdentifier != getpid(), !app.isTerminated,
                  !finishedLaunching || app.isFinishedLaunching else { return false }
            return identifier == bundleID || (identifier.hasPrefix(bundleID + ".") && app.bundleURL?.lastPathComponent == "Mizon.app")
        }
    }

    private static func activate(_ app: NSRunningApplication) {
        if app.isHidden { app.unhide() }
        app.activate(options: [.activateAllWindows])
    }
}

@MainActor
final class MizonApplicationDelegate: NSObject, NSApplicationDelegate {
    let dockShortcuts = MizonDockShortcuts()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? { dockShortcuts.menu() }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where MizonDeepLinkRouter.shared.open(url) {
            dockShortcuts.activateMainWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MizonDeepLinkRouter.shared.applicationWillClose()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !MacMenuBarProfile.shared.keepsApplicationRunning
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, MacMenuBarProfile.shared.keepsApplicationRunning else { return true }
        dockShortcuts.activateMainWindow()
        return false
    }
}
#endif
