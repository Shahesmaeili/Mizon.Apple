import SwiftUI
#if os(macOS)
import AppKit
#endif

struct WindowGlass: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    #if os(iOS)
    var tintOpacity = 0.86
    #endif

    var body: some View {
        #if os(macOS)
        if reduceTransparency {
            MizonPalette.surface
        } else {
            WindowBackdrop()
                .overlay(MizonPalette.surface.opacity(0.73))
        }
        #elseif os(iOS)
        if reduceTransparency {
            MizonPalette.surface
        } else {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(MizonPalette.surface.opacity(tintOpacity))
        }
        #else
        MizonPalette.surface
        #endif
    }
}

#if os(macOS)
private struct WindowBackdrop: NSViewRepresentable {
    final class Backdrop: NSVisualEffectView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.isOpaque = false
            window?.backgroundColor = .clear
            window?.titlebarAppearsTransparent = true
        }
    }
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = Backdrop()
        view.material = .sidebar
        view.appearance = NSAppearance(named: .darkAqua)
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
#endif
