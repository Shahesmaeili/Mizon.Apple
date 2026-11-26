#if os(macOS)
import AppKit
import QuartzCore
import SwiftUI

struct MacMusicPageTransition: NSViewRepresentable {
    let path: [MusicDestination]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    final class Coordinator {
        var path: [MusicDestination]

        init(path: [MusicDestination]) {
            self.path = path
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(path: path) }
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        let previous = context.coordinator.path
        context.coordinator.path = path
        guard
            !reduceMotion,
            let transition = Self.transition(from: previous, to: path, direction: layoutDirection),
            let window = view.window, window.isVisible, let content = window.contentView
        else { return }

        if !content.wantsLayer { content.wantsLayer = true }
        // Animate the window's content layer while SwiftUI applies the route update.
        content.layer?.add(transition, forKey: "mizon.music.page")
    }

    static func transition(from previous: [MusicDestination], to next: [MusicDestination],
                           direction: LayoutDirection) -> CATransition? {
        guard previous != next else { return nil }
        let goingBack = next.count < previous.count && previous.starts(with: next)
        let movesFromRight = goingBack == (direction == .rightToLeft)
        let transition = CATransition()
        transition.type = .push
        transition.duration = NSAnimationContext.current.duration
        transition.subtype = movesFromRight ? .fromRight : .fromLeft
        return transition
    }
}
#endif
