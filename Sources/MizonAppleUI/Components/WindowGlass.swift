import SwiftUI
#if os(macOS)
import AppKit
struct WindowGlass: NSViewRepresentable {
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
        view.material = .hudWindow
        view.appearance = NSAppearance(named: .darkAqua)
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
#else
struct WindowGlass: View {
    var body: some View { Rectangle().fill(.ultraThinMaterial) }
}
#endif
