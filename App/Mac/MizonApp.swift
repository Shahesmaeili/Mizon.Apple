import SwiftUI
import MizonAppleCore
import MizonAppleUI
#if os(macOS)
import AppKit
#endif

@main
struct MizonApp: App {
    @State private var model = ApplicationServices.makeLoginViewModel()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MizonApplicationDelegate.self) private var appDelegate
    #endif
    var body: some Scene {
        WindowGroup("Mizon") {
            MizonRootView(model: model)
                #if os(macOS)
                .frame(minWidth: 620, minHeight: 720)
                #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 820)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .commands { CommandGroup(replacing: .newItem) {} }
        #endif
        #if os(macOS)
        Settings { ServerSettingsView(model: model) }
        #endif
    }
}
#if os(macOS)
final class MizonApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#endif
