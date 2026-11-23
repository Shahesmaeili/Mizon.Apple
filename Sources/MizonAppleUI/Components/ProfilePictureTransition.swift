#if os(macOS) || os(iOS)
import QuartzCore
import SwiftUI
#if os(macOS)
import AppKit
private typealias ProfileTransitionView = NSView
#else
import UIKit
private typealias ProfileTransitionView = UIView
#endif

@MainActor @Observable
final class ProfilePictureTransition {
    enum Anchor { case welcome, header }

    // WinUI's default service duration used by GravityConnectedAnimationConfiguration.
    private static let duration = 300
    private(set) var isInFlight = false
    @ObservationIgnored private weak var welcome: ProfileTransitionView?
    @ObservationIgnored private weak var header: ProfileTransitionView?
    @ObservationIgnored private var flight: Flight?

    private final class Flight {
        let canvas: ProfileTransitionCanvas
        let picture: ProfileTransitionView
        let sourceImage: ProfileTransitionView
        let destinationImage: ProfileTransitionView

        init(canvas: ProfileTransitionCanvas, picture: ProfileTransitionView,
             sourceImage: ProfileTransitionView, destinationImage: ProfileTransitionView) {
            self.canvas = canvas
            self.picture = picture
            self.sourceImage = sourceImage
            self.destinationImage = destinationImage
        }
    }

    func anchor(_ location: Anchor) -> some View {
        ProfilePictureTransitionAnchor(transition: self, location: location)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    fileprivate func register(_ view: ProfileTransitionView, at location: Anchor) {
        switch location {
        case .welcome: welcome = view
        case .header: header = view
        }
    }

    func prepare(avatar: CGImage?, displayName: String? = nil, reduceMotion: Bool) {
        cancel()
        guard !reduceMotion, let welcome, let window = welcome.window else { return }
        #if os(macOS)
        // The window toolbar and the SwiftUI content have different hosting views.
        guard let host = window.contentView?.superview else { return }
        let scale = window.backingScaleFactor
        #else
        let host = window
        let scale = window.traitCollection.displayScale
        #endif
        let start = welcome.convert(welcome.bounds, to: host)
        guard start.width > 0, start.height > 0, host.bounds.contains(start),
              isVisible(welcome, frame: start, in: host) else { return }

        guard let source = snapshot(WelcomeProfileBadge(avatar: avatar)
            .frame(width: start.width, height: start.height), scale: scale),
              let destination = snapshot(MusicHomeProfilePicture(avatar: avatar, displayName: displayName),
                                         scale: scale) else { return }

        let canvas = ProfileTransitionCanvas(frame: host.bounds)
        #if os(macOS)
        canvas.autoresizingMask = [.width, .height]
        host.addSubview(canvas, positioned: .above, relativeTo: nil)
        #else
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvas.isUserInteractionEnabled = false
        canvas.accessibilityElementsHidden = true
        host.addSubview(canvas)
        #endif
        let picture = ProfileTransitionView(frame: welcome.convert(welcome.bounds, to: canvas))
        let sourceImage = imageView(source, frame: picture.bounds)
        let destinationImage = imageView(destination, frame: picture.bounds)
        #if os(macOS)
        picture.wantsLayer = true
        destinationImage.alphaValue = 0
        #else
        destinationImage.alpha = 0
        #endif
        picture.addSubview(sourceImage)
        picture.addSubview(destinationImage)
        canvas.addSubview(picture)
        flight = Flight(canvas: canvas, picture: picture, sourceImage: sourceImage, destinationImage: destinationImage)
        isInFlight = true
    }

    func play() async {
        guard let flight else { return }
        defer { if self.flight === flight { cancel() } }
        let clock = ContinuousClock()
        let deadline = clock.now + .milliseconds(300)
        var previous: CGRect?
        while self.flight === flight, !Task.isCancelled, clock.now < deadline {
            if let end = destination(in: flight.canvas) {
                if previous == end {
                    animate(flight, to: end)
                    try? await clock.sleep(for: .milliseconds(Self.duration))
                    return
                }
                previous = end
            } else {
                previous = nil
            }
            do { try await clock.sleep(for: .milliseconds(16)) }
            catch { return }
        }
    }

    func cancel() {
        flight?.canvas.removeFromSuperview()
        flight = nil
        isInFlight = false
    }

    private func destination(in canvas: ProfileTransitionCanvas) -> CGRect? {
        guard let header, let window = canvas.window, header.window === window else { return nil }
        let frame = header.convert(header.bounds, to: canvas)
        guard frame.width > 0, frame.height > 0, canvas.bounds.contains(frame) else { return nil }
        #if os(macOS)
        let scale = window.backingScaleFactor
        #else
        let scale = max(1, window.traitCollection.displayScale)
        #endif
        return CGRect(x: (frame.minX * scale).rounded() / scale, y: (frame.minY * scale).rounded() / scale,
                      width: (frame.width * scale).rounded() / scale, height: (frame.height * scale).rounded() / scale)
    }

    private func snapshot(_ content: some View, scale: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: content.preferredColorScheme(.dark))
        renderer.scale = max(1, scale)
        return renderer.cgImage
    }

    private func imageView(_ image: CGImage, frame: CGRect) -> ProfileTransitionView {
        #if os(macOS)
        let view = NSImageView(frame: frame)
        view.image = NSImage(cgImage: image, size: frame.size)
        view.imageScaling = .scaleAxesIndependently
        view.autoresizingMask = [.width, .height]
        #else
        let view = UIImageView(image: UIImage(cgImage: image))
        view.frame = frame
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        #endif
        return view
    }

    private func animate(_ flight: Flight, to frame: CGRect) {
        let duration = Double(Self.duration) / 1_000
        applyGravity(to: flight, destination: frame, duration: duration)
        #if os(macOS)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.8, 0, 0.2, 1)
            flight.picture.animator().frame = frame
            flight.sourceImage.animator().alphaValue = 0
            flight.destinationImage.animator().alphaValue = 1
        }
        #else
        let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.8, y: 0),
                                             controlPoint2: CGPoint(x: 0.2, y: 1))
        let animator = UIViewPropertyAnimator(duration: duration, timingParameters: timing)
        animator.addAnimations {
            flight.picture.frame = frame
            flight.sourceImage.alpha = 0
            flight.destinationImage.alpha = 1
        }
        animator.startAnimation()
        #endif
    }

    private func applyGravity(to flight: Flight, destination: CGRect, duration: TimeInterval) {
        #if os(macOS)
        guard let layer = flight.picture.layer else { return }
        let down: CGFloat = flight.canvas.isFlipped ? 1 : -1
        #else
        let layer = flight.picture.layer
        let down: CGFloat = 1
        #endif

        // WinUI adds the dip to the normal movement in screen space, so it is independent of resizing.
        addGravityKeyframes(to: layer, keyPath: "transform.translation.y", values: [0, 80 * down, 0], duration: duration)
        addGravityKeyframes(to: layer, keyPath: "zPosition", values: [0, 32, 0], duration: duration)
        if flight.picture.frame.size == destination.size {
            addGravityKeyframes(to: layer, keyPath: "transform.scale", values: [1, 1.1, 1], duration: duration)
        }

        // Core Animation casts a directional shadow from the circular image as the WinUI elevation peaks.
        layer.shadowColor = CGColor(gray: 0, alpha: 1)
        layer.shadowOffset = CGSize(width: 0, height: 12.8 * down)
        addGravityKeyframes(to: layer, keyPath: "shadowRadius", values: [0, 28.8, 0], duration: duration)
        addGravityKeyframes(to: layer, keyPath: "shadowOpacity", values: [0, 0.22, 0], duration: duration)
    }

    private func addGravityKeyframes(to layer: CALayer, keyPath: String, values: [CGFloat], duration: TimeInterval) {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = [0, 0.66, 1]
        animation.timingFunctions = [
            CAMediaTimingFunction(controlPoints: 0.35, 0, 0.55, 1),
            CAMediaTimingFunction(controlPoints: 0.45, 0, 0.55, 1)
        ]
        animation.duration = duration
        layer.add(animation, forKey: keyPath)
    }

    private func isVisible(_ view: ProfileTransitionView, frame: CGRect, in host: ProfileTransitionView) -> Bool {
        #if os(macOS)
        view.visibleRect.contains(view.bounds)
        #else
        var ancestor = view.superview
        while let current = ancestor, current !== host {
            if current.clipsToBounds, !current.convert(current.bounds, to: host).contains(frame) { return false }
            ancestor = current.superview
        }
        return true
        #endif
    }
}

#if os(macOS)
private final class ProfileTransitionCanvas: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct ProfilePictureTransitionAnchor: NSViewRepresentable {
    let transition: ProfilePictureTransition
    let location: ProfilePictureTransition.Anchor

    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) { transition.register(view, at: location) }
}
#else
private final class ProfileTransitionCanvas: UIView {}

private struct ProfilePictureTransitionAnchor: UIViewRepresentable {
    let transition: ProfilePictureTransition
    let location: ProfilePictureTransition.Anchor

    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ view: UIView, context: Context) { transition.register(view, at: location) }
}
#endif
#endif
