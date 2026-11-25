#if os(macOS) || os(iOS)
import SwiftUI

@MainActor @Observable
final class MusicHomeFocus {
    #if os(macOS)
    private(set) var showsNavigationFocus = false

    func updateForNavigation(_ usingNavigation: Bool) {
        if showsNavigationFocus != usingNavigation { showsNavigationFocus = usingNavigation }
    }
    #else
    let showsNavigationFocus = true
    #endif
}

struct MusicHomeFocusOutline: View {
    let isFocused: Bool
    let cornerRadius: CGFloat
    let input: MusicHomeFocus

    var isVisible: Bool { isFocused && input.showsNavigationFocus }

    var body: some View {
        if isVisible {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(MizonPalette.accent, lineWidth: 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

#if os(macOS)
import AppKit

struct MusicHomeFocusInput: NSViewRepresentable {
    let input: MusicHomeFocus

    func makeNSView(context: Context) -> InputView { InputView(input: input) }

    func updateNSView(_ view: InputView, context: Context) {}

    static func dismantleNSView(_ view: InputView, coordinator: ()) {
        view.stopMonitoring()
    }

    final class InputView: NSView {
        private let input: MusicHomeFocus
        private var monitor: Any?

        init(input: MusicHomeFocus) {
            self.input = input
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) {
                [weak self] event in
                if let self, let window, event.window === window, window.isKeyWindow {
                    input.updateForNavigation(event.type == .keyDown)
                }
                return event
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
#endif
#endif
