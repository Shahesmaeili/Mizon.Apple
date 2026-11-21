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
    #endif
    var body: some Scene {
        #if os(macOS)
        Window("Mizon", id: "main") {
            MizonRootView(model: model)
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
        }
        #endif
    }
}
#if os(macOS)
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

final class MizonApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#endif
