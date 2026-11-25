#if os(macOS) || os(iOS)
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct MoodEffectPresentation: Equatable {
    let id: UUID
    let file: URL
    let playback = MoodLottieEffectPlayback()
}

private let moodEffectSize = MoodLottiePlayback.effectSize.width

private struct MoodEffectSurface: View {
    let effect: MoodEffectPresentation
    let onCompletion: (UUID) -> Void

    var body: some View {
        MoodLottieView(file: effect.file, playback: .once(effect.playback), playing: true,
                       onCompletion: { onCompletion(effect.id) })
            .frame(width: moodEffectSize, height: moodEffectSize)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#if os(macOS)
struct MoodEffectAnchor: NSViewRepresentable {
    let effect: MoodEffectPresentation
    let onCompletion: (UUID) -> Void

    func makeNSView(context: Context) -> Anchor { Anchor() }

    func updateNSView(_ view: Anchor, context: Context) {
        view.update(effect: effect, onCompletion: onCompletion)
    }

    static func dismantleNSView(_ view: Anchor, coordinator: ()) {
        view.update(effect: nil, onCompletion: { _ in })
    }

    final class Anchor: NSView {
        private var panel: NSPanel?
        private var hosting: NSHostingView<MoodEffectSurface>?
        private var effect: MoodEffectPresentation?
        private var onCompletion: ((UUID) -> Void)?
        private var displayed: MoodEffectPresentation?

        func update(effect: MoodEffectPresentation?, onCompletion: @escaping (UUID) -> Void) {
            self.effect = effect
            self.onCompletion = onCompletion
            synchronize()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            synchronize()
        }

        override func layout() {
            super.layout()
            synchronize()
        }

        private func synchronize() {
            guard let owner = window, let effect, !bounds.isEmpty else {
                removePanel()
                return
            }

            let anchor = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
            let center = owner.convertPoint(toScreen: anchor)
            let rect = NSRect(x: center.x - moodEffectSize / 2, y: center.y - moodEffectSize / 2,
                              width: moodEffectSize, height: moodEffectSize)

            let current: NSPanel
            if let panel, panel.parent === owner {
                current = panel
            } else {
                removePanel()
                current = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
                current.isOpaque = false
                current.isReleasedWhenClosed = false
                current.backgroundColor = .clear
                current.ignoresMouseEvents = true
                current.hasShadow = false
                current.animationBehavior = .none
                current.collectionBehavior = [.transient, .fullScreenAuxiliary, .ignoresCycle]
                owner.addChildWindow(current, ordered: .above)
                panel = current
            }
            if current.frame != rect { current.setFrame(rect, display: false) }

            if displayed != effect {
                let surface = MoodEffectSurface(effect: effect) { [weak self] in self?.onCompletion?($0) }
                if let hosting {
                    hosting.rootView = surface
                } else {
                    let host = NSHostingView(rootView: surface)
                    current.contentView = host
                    hosting = host
                }
                displayed = effect
            }
            if !current.isVisible { current.orderFront(nil) }
        }

        private func removePanel() {
            if let panel {
                panel.parent?.removeChildWindow(panel)
                panel.orderOut(nil)
                panel.contentView = nil
                panel.close()
            }
            panel = nil
            hosting = nil
            displayed = nil
        }
    }
}
#else
struct MoodEffectAnchor: UIViewRepresentable {
    let effect: MoodEffectPresentation
    let onCompletion: (UUID) -> Void

    func makeUIView(context: Context) -> Anchor {
        let view = Anchor()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: Anchor, context: Context) {
        view.update(effect: effect, onCompletion: onCompletion)
    }

    static func dismantleUIView(_ view: Anchor, coordinator: ()) {
        view.update(effect: nil, onCompletion: { _ in })
    }

    final class Anchor: UIView {
        private var hosting: UIHostingController<MoodEffectSurface>?
        private var effect: MoodEffectPresentation?
        private var onCompletion: ((UUID) -> Void)?
        private var displayed: MoodEffectPresentation?

        func update(effect: MoodEffectPresentation?, onCompletion: @escaping (UUID) -> Void) {
            self.effect = effect
            self.onCompletion = onCompletion
            synchronize()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            synchronize()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            synchronize()
        }

        private func synchronize() {
            guard let owner = window, let effect, !bounds.isEmpty else {
                removeOverlay()
                return
            }

            let current: UIHostingController<MoodEffectSurface>
            if let hosting, hosting.view.superview === owner {
                current = hosting
                if displayed != effect { current.rootView = makeSurface(effect) }
            } else {
                removeOverlay()
                current = UIHostingController(rootView: makeSurface(effect))
                current.view.backgroundColor = .clear
                current.view.isUserInteractionEnabled = false
                current.view.accessibilityElementsHidden = true
                let parent = owningController() ?? owner.rootViewController
                parent?.addChild(current)
                owner.addSubview(current.view)
                current.didMove(toParent: parent)
                hosting = current
            }
            displayed = effect

            let center = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: owner)
            current.view.frame = CGRect(x: center.x - moodEffectSize / 2, y: center.y - moodEffectSize / 2,
                                        width: moodEffectSize, height: moodEffectSize)
        }

        private func makeSurface(_ effect: MoodEffectPresentation) -> MoodEffectSurface {
            MoodEffectSurface(effect: effect) { [weak self] in self?.onCompletion?($0) }
        }

        private func owningController() -> UIViewController? {
            var responder = next
            while let current = responder {
                if let controller = current as? UIViewController { return controller }
                responder = current.next
            }
            return nil
        }

        private func removeOverlay() {
            if let hosting {
                hosting.willMove(toParent: nil)
                hosting.view.removeFromSuperview()
                hosting.removeFromParent()
            }
            hosting = nil
            displayed = nil
        }
    }
}
#endif
#endif
