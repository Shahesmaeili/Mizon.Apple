#if os(macOS)
import AppKit
import QuartzCore
import SwiftUI

struct MacWindowAccent: NSViewRepresentable {
    let color: Color
    let animatesColor: Bool

    func makeNSView(context: Context) -> Attachment {
        Attachment(frame: .zero)
    }

    func updateNSView(_ view: Attachment, context: Context) {
        view.outline.setColor(NSColor(color), animated: animatesColor)
        view.install()
    }

    static func dismantleNSView(_ view: Attachment, coordinator: ()) {
        view.detach()
    }

    final class Attachment: NSView {
        let outline = Outline(frame: .zero)
        private weak var decoratedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            install()
        }

        override func layout() {
            super.layout()
            install()
        }

        func install() {
            guard let window, let content = window.contentView, let frameView = content.superview else {
                detach()
                return
            }

            if decoratedWindow !== window {
                detach()
                decoratedWindow = window
                let center = NotificationCenter.default
                for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                    center.addObserver(self, selector: #selector(fullScreenDidChange(_:)), name: name, object: window)
                }
            }

            outline.isHidden = window.styleMask.contains(.fullScreen)
            guard outline.superview !== frameView else { return }
            outline.removeFromSuperview()
            outline.frame = frameView.bounds
            // The navigation transition animates contentView. Its sibling follows the window frame.
            frameView.addSubview(outline, positioned: .above, relativeTo: content)
        }

        func detach() {
            if let decoratedWindow {
                NotificationCenter.default.removeObserver(self, name: nil, object: decoratedWindow)
            }
            decoratedWindow = nil
            outline.removeFromSuperview()
        }

        @objc private func fullScreenDidChange(_ notification: Notification) {
            install()
        }
    }

    final class Outline: NSView {
        private let stroke = CAShapeLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            autoresizingMask = [.width, .height]
            wantsLayer = true
            stroke.fillColor = nil
            stroke.lineWidth = 1
            layer?.addSublayer(stroke)
            setAccessibilityElement(false)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            needsLayout = true
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            stroke.frame = bounds
            let rect = NSRect(origin: .zero, size: bounds.size).insetBy(dx: 0.5, dy: 0.5)
            stroke.path = rect.isEmpty ? nil : CGPath(roundedRect: rect, cornerWidth: 17.5, cornerHeight: 17.5,
                                                       transform: nil)
            CATransaction.commit()
        }

        func setColor(_ color: NSColor, animated: Bool) {
            let color = color.cgColor
            guard stroke.strokeColor != color else { return }
            let previous = stroke.presentation()?.strokeColor ?? stroke.strokeColor
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            stroke.strokeColor = color
            CATransaction.commit()
            if animated, let previous, window?.isVisible == true {
                let transition = CABasicAnimation(keyPath: "strokeColor")
                transition.fromValue = previous
                transition.toValue = color
                transition.duration = 0.24
                transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
                stroke.add(transition, forKey: "strokeColor")
            } else {
                stroke.removeAnimation(forKey: "strokeColor")
            }
        }
    }
}
#endif
