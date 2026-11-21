#if os(macOS) || os(iOS)
import CoreGraphics
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct MusicHeroPalette: Equatable, Sendable {
    fileprivate let base: RGB
    fileprivate let accent: RGB
    fileprivate let highlight: RGB

    @concurrent
    static func extract(from image: CGImage) async -> MusicHeroPalette? {
        guard !Task.isCancelled, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn, !Task.isCancelled else { return nil }
        var buckets = [Bucket](repeating: Bucket(), count: 512)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[offset + 3])
            guard alpha >= 128 else { continue }
            let red = min(255, (Int(pixels[offset]) * 255 + alpha / 2) / alpha)
            let green = min(255, (Int(pixels[offset + 1]) * 255 + alpha / 2) / alpha)
            let blue = min(255, (Int(pixels[offset + 2]) * 255 + alpha / 2) / alpha)
            let index = ((red >> 5) << 6) | ((green >> 5) << 3) | (blue >> 5)
            buckets[index].count += 1
            buckets[index].red += red
            buckets[index].green += green
            buckets[index].blue += blue
        }
        guard let base = pick(buckets) else { return nil }
        let accent = pick(buckets, excluding: base)
        let highlight = pick(buckets, excluding: base, and: accent)
        return MusicHeroPalette(base: base.lifted(to: 125), accent: (accent ?? base).lifted(to: 175),
                                highlight: (highlight ?? accent ?? base).lifted(to: 225))
    }

    private static func pick(_ buckets: [Bucket], excluding first: RGB? = nil, and second: RGB? = nil) -> RGB? {
        var best: RGB?
        var bestScore = 0.0
        for bucket in buckets where bucket.count > 0 {
            let color = bucket.average
            if let first, color.distanceSquared(to: first) < 52 * 52 { continue }
            if let second, color.distanceSquared(to: second) < 52 * 52 { continue }
            let score = sqrt(Double(bucket.count)) * (0.16 + 0.35 * color.peak / 255
                                                      + 1.25 * (color.peak - color.floor) / 255)
            guard score > bestScore else { continue }
            bestScore = score
            best = color
        }
        return best
    }

    fileprivate func blended(toward target: Self, amount: Double) -> Self {
        Self(base: base.blended(toward: target.base, amount: amount),
             accent: accent.blended(toward: target.accent, amount: amount),
             highlight: highlight.blended(toward: target.highlight, amount: amount))
    }

    private struct Bucket {
        var count = 0
        var red = 0
        var green = 0
        var blue = 0

        var average: RGB {
            RGB(red: Double(red / count), green: Double(green / count), blue: Double(blue / count))
        }
    }

    fileprivate struct RGB: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double

        var peak: Double { max(red, green, blue) }
        var floor: Double { min(red, green, blue) }

        func distanceSquared(to other: Self) -> Double {
            let dr = red - other.red
            let dg = green - other.green
            let db = blue - other.blue
            return dr * dr + dg * dg + db * db
        }

        func lifted(to minimumPeak: Double) -> Self {
            guard peak < minimumPeak else { return self }
            let ratio = (minimumPeak - peak) / (255 - peak)
            return RGB(red: (red + (255 - red) * ratio).rounded(.toNearestOrEven),
                       green: (green + (255 - green) * ratio).rounded(.toNearestOrEven),
                       blue: (blue + (255 - blue) * ratio).rounded(.toNearestOrEven))
        }

        func blended(toward target: Self, amount: Double) -> Self {
            RGB(red: red + (target.red - red) * amount,
                green: green + (target.green - green) * amount,
                blue: blue + (target.blue - blue) * amount)
        }

        func color(opacity: Double = 1) -> Color {
            Color(.sRGB, red: red / 255, green: green / 255, blue: blue / 255, opacity: opacity)
        }
    }
}

struct MusicHeroLighting: ViewModifier {
    let active: Bool
    let palette: MusicHeroPalette?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var spot: Spot = .rest
    @State private var spotReturn: SpotReturn?
    @State private var ripple: Ripple?
    @State private var edge = Edge()
    @State private var paletteBlend: PaletteBlend?
    @State private var settledThrough = Date.distantPast
    #if os(iOS)
    @State private var inputSize = CGSize.zero
    #endif

    private static let haloPadding: CGFloat = 20
    private static let corner: CGFloat = 12
    private static let stroke: CGFloat = 0.75
    private static let proximityRadius: CGFloat = 76
    nonisolated private static let restCurve = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.3, y: 0.7), endControlPoint: UnitPoint(x: 0.9, y: 0.5)
    )

    private var motion: Bool { active && !reduceMotion }
    private var showSpectrum: Bool { active && palette != nil && contrast != .increased }

    func body(content: Content) -> some View {
        let end = max(spotReturn?.motion.end ?? .distantPast, ripple?.motion.end ?? .distantPast,
                      edge.motion.end, paletteBlend?.motion.end ?? .distantPast)
        return inputSurface(content)
            .overlay {
                if active {
                    TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !motion || end <= settledThrough)) { timeline in
                        let time = max(timeline.date, settledThrough)
                        ZStack {
                            if motion {
                                Canvas { canvas, size in renderSpotlights(canvas, size: size, at: time) }
                                    .blendMode(.overlay)
                            }
                            if showSpectrum {
                                Canvas { canvas, size in renderSpectrum(canvas, size: size, at: time) }
                            }
                        }
                    }
                    .padding(-Self.haloPadding)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .task(id: end) {
                let remaining = end.timeIntervalSinceNow
                if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
                guard !Task.isCancelled else { return }
                settledThrough = end
            }
            .onChange(of: active) { _, value in
                guard !value else { return }
                clearLights()
            }
            .onChange(of: reduceMotion) { _, value in
                guard value else { return }
                spot = .rest
                spotReturn = nil
                ripple = nil
                paletteBlend = nil
                edge.snap()
            }
            .onChange(of: palette) { previous, current in
                let now = Date()
                if motion, current != nil, showSpectrum, edge.opacity(at: now) > 0, let previous {
                    paletteBlend = PaletteBlend(source: paletteBlend?.value(toward: previous, at: now) ?? previous,
                                                motion: Timing(start: now, duration: 0.380))
                } else {
                    paletteBlend = nil
                }
            }
    }

    @ViewBuilder
    private func inputSurface(_ content: Content) -> some View {
        #if os(macOS)
        content.background {
            if active {
                HeroMouseObserver(proximity: Self.proximityRadius, onMove: movePointer, onPress: press)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        #else
        content
            .onGeometryChange(for: CGSize.self, of: \.size) { inputSize = $0 }
            .gesture(HeroTouchObserver(isEnabled: motion, onPress: { point in
                guard CGRect(origin: .zero, size: inputSize).contains(point) else { return }
                press(point)
                follow(point, height: 15)
            }, onMove: { point in
                if CGRect(origin: .zero, size: inputSize).contains(point) {
                    follow(point, height: 15)
                } else {
                    restSpot()
                }
            }, onEnd: restSpot, onCancel: {
                restSpot()
                ripple = nil
            }))
        #endif
    }

    private func movePointer(_ point: CGPoint?, in size: CGSize) {
        guard active else { return }
        let bounds = CGRect(origin: .zero, size: size)
        if let point, bounds.contains(point) {
            follow(point, height: 100)
        } else {
            restSpot()
        }

        var opacity = 0.0
        if let point {
            let dx = point.x - min(max(0, point.x), size.width)
            let dy = point.y - min(max(0, point.y), size.height)
            let strength = max(0, 1 - hypot(dx, dy) / Self.proximityRadius)
            opacity = strength * strength * (3 - 2 * strength)
            if opacity > 0, edge.center != point { edge.center = point }
        }
        guard opacity != edge.target, !(opacity > 0 && opacity < 1 && abs(opacity - edge.target) < 0.02) else { return }
        let now = Date()
        edge = Edge(center: edge.center, from: edge.opacity(at: now), target: opacity,
                    motion: Timing(start: now, duration: motion ? 0.125 : 0))
    }

    private func follow(_ point: CGPoint, height: CGFloat) {
        guard motion else { return }
        let current = Spot(center: point, height: height)
        guard spot != current else { return }
        spotReturn = nil
        spot = current
    }

    private func restSpot() {
        guard motion, spot != .rest else { return }
        spotReturn = SpotReturn(origin: spot, motion: Timing(start: Date(), duration: 0.5))
        spot = .rest
    }

    private func press(_ point: CGPoint) {
        guard motion else { return }
        ripple = Ripple(center: point, motion: Timing(start: Date(), duration: 1.2))
    }

    private func clearLights() {
        spot = .rest
        spotReturn = nil
        ripple = nil
        edge = Edge()
        paletteBlend = nil
    }

    private func renderSpotlights(_ context: GraphicsContext, size: CGSize, at time: Date) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: Self.haloPadding, dy: Self.haloPadding)
        guard bounds.width > 0, bounds.height > 0 else { return }
        var surface = context
        surface.clip(to: Path(roundedRect: bounds, cornerRadius: Self.corner))
        surface.blendMode = .screen
        let light = spotReturn?.value(at: time) ?? spot
        let distance = light.height / 100
        let attenuation = 1 / (1 + 0.253 * distance + 0.58 * distance * distance)
        spotGradient(in: surface, bounds: bounds, center: light.center, height: light.height,
                     angles: (20, 50), color: Color(red: 1, green: 250.0 / 255, blue: 240.0 / 255),
                     intensity: attenuation)
        if let ripple, time < ripple.motion.end {
            let progress = ripple.motion.progress(at: time)
            let final = min(max(max(bounds.width, bounds.height) * 2, 240), 1400)
            let height = 16 + (final - 16) * progress
            let fade = min(progress / 0.09, (1 - progress) / 0.91)
            spotGradient(in: surface, bounds: bounds, center: ripple.center, height: height,
                         angles: (44, 68), color: Color(red: 143.0 / 255, green: 135.0 / 255, blue: 124.0 / 255),
                         intensity: fade / (1 + 0.006 * height / 100))
        }
    }

    private func renderSpectrum(_ context: GraphicsContext, size: CGSize, at time: Date) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: Self.haloPadding, dy: Self.haloPadding)
        let opacity = edge.opacity(at: time)
        if bounds.width > 0, bounds.height > 0, opacity > 0, let palette {
            let color = paletteBlend?.value(toward: palette, at: time) ?? palette
            let strokeBounds = bounds.insetBy(dx: Self.stroke / 2, dy: Self.stroke / 2)
            let stroke = Path(roundedRect: strokeBounds, cornerRadius: Self.corner - Self.stroke / 2)
            let radius = min(max(min(strokeBounds.width, strokeBounds.height) * 0.8, 130), 250)
            let gradient = GraphicsContext.Shading.radialGradient(Gradient(stops: [
                .init(color: color.highlight.color(opacity: opacity), location: 0),
                .init(color: color.accent.color(opacity: opacity * 230 / 255), location: 0.30),
                .init(color: color.base.color(opacity: opacity * 150 / 255), location: 0.67),
                .init(color: color.base.color(opacity: 0), location: 1)
            ]), center: center(edge.center, in: bounds), startRadius: 0, endRadius: radius)

            var halo = context
            var exterior = Path(CGRect(origin: .zero, size: size))
            exterior.addPath(Path(roundedRect: bounds, cornerRadius: Self.corner))
            halo.clip(to: exterior, style: FillStyle(eoFill: true))
            halo.drawLayer { layer in
                layer.addFilter(.blur(radius: 5.5))
                // A threefold stroke width preserves the reference blur's threefold gain.
                layer.stroke(stroke, with: gradient, lineWidth: Self.stroke * 3)
            }
            context.stroke(stroke, with: gradient, lineWidth: Self.stroke)
        }
    }

    private func spotGradient(in context: GraphicsContext, bounds: CGRect, center point: CGPoint,
                              height: CGFloat, angles: (inner: Double, outer: Double),
                              color: Color, intensity: Double) {
        let inner = tan(angles.inner * .pi / 180)
        let outer = tan(angles.outer * .pi / 180)
        let gradient = Gradient(stops: [
            .init(color: color.opacity(intensity), location: 0),
            .init(color: color.opacity(intensity), location: inner / outer),
            .init(color: color.opacity(0), location: 1)
        ])
        context.fill(Path(bounds), with: .radialGradient(gradient, center: center(point, in: bounds),
                                                      startRadius: 0, endRadius: height * outer))
    }

    private func center(_ point: CGPoint, in bounds: CGRect) -> CGPoint {
        CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y)
    }

    private struct Spot: Equatable {
        static let rest = Spot(center: CGPoint(x: 200, y: 200), height: 400)
        let center: CGPoint
        let height: CGFloat
    }

    private struct Timing {
        var start = Date.distantPast
        var duration: TimeInterval = 0

        var end: Date { start.addingTimeInterval(duration) }

        func progress(at time: Date) -> Double {
            guard duration > 0 else { return 1 }
            return min(max(time.timeIntervalSince(start) / duration, 0), 1)
        }
    }

    private struct SpotReturn {
        let origin: Spot
        let motion: Timing

        func value(at now: Date) -> Spot {
            let amount = MusicHeroLighting.restCurve.value(at: motion.progress(at: now))
            let rest = Spot.rest
            return Spot(center: CGPoint(x: origin.center.x + (rest.center.x - origin.center.x) * amount,
                                       y: origin.center.y + (rest.center.y - origin.center.y) * amount),
                        height: origin.height + (rest.height - origin.height) * amount)
        }
    }

    private struct Ripple {
        let center: CGPoint
        let motion: Timing
    }

    private struct Edge {
        var center = CGPoint.zero
        var from = 0.0
        var target = 0.0
        var motion = Timing()

        func opacity(at time: Date) -> Double {
            from + (target - from) * UnitCurve.easeInOut.value(at: motion.progress(at: time))
        }

        mutating func snap() {
            from = target
            motion = Timing()
        }
    }

    private struct PaletteBlend {
        let source: MusicHeroPalette
        let motion: Timing

        func value(toward target: MusicHeroPalette, at time: Date) -> MusicHeroPalette {
            source.blended(toward: target, amount: UnitCurve.easeInOut.value(at: motion.progress(at: time)))
        }
    }
}

#if os(macOS)
private struct HeroMouseObserver: NSViewRepresentable {
    let proximity: CGFloat
    let onMove: (CGPoint?, CGSize) -> Void
    let onPress: (CGPoint) -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView() }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.proximity = proximity
        view.onMove = onMove
        view.onPress = onPress
    }

    static func dismantleNSView(_ view: ObserverView, coordinator: ()) {
        view.removeMonitor()
    }

    final class ObserverView: NSView {
        var proximity: CGFloat = 0
        var onMove: ((CGPoint?, CGSize) -> Void)?
        var onPress: ((CGPoint) -> Void)?
        private var monitor: Any?
        private var tracking: NSTrackingArea?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            guard window != nil else { return }
            let tracking = NSTrackingArea(rect: .zero,
                                          options: [.inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow],
                                          owner: self)
            addTrackingArea(tracking)
            self.tracking = tracking
        }

        override func mouseEntered(with event: NSEvent) { observe(event) }
        override func mouseMoved(with event: NSEvent) { observe(event) }
        override func mouseExited(with event: NSEvent) { observe(event) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .mouseMoved, .scrollWheel]) {
                [weak self] event in
                if NSEvent.EventType.scrollWheel == event.type {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, let window, window.isKeyWindow else { return }
                        updateLocation(window.mouseLocationOutsideOfEventStream)
                    }
                } else {
                    self?.observe(event)
                }
                return event
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func observe(_ event: NSEvent) {
            guard let window, event.window == window, window.isKeyWindow else {
                onMove?(nil, bounds.size)
                return
            }
            updateLocation(event.locationInWindow)
            let point = convert(event.locationInWindow, from: nil)
            if event.type == .leftMouseDown, visibleRect.contains(point) { onPress?(point) }
        }

        private func updateLocation(_ windowPoint: CGPoint) {
            let point = convert(windowPoint, from: nil)
            let nearby = !visibleRect.isEmpty && visibleRect.insetBy(dx: -proximity, dy: -proximity).contains(point)
            onMove?(nearby ? point : nil, bounds.size)
        }
    }
}
#else
private struct HeroTouchObserver: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let onPress: (CGPoint) -> Void
    let onMove: (CGPoint) -> Void
    let onEnd: () -> Void
    let onCancel: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> TouchRecognizer {
        let touch = TouchRecognizer()
        touch.cancelsTouchesInView = false
        touch.delaysTouchesBegan = false
        touch.delaysTouchesEnded = false
        touch.delegate = context.coordinator
        return touch
    }

    func updateUIGestureRecognizer(_ touch: TouchRecognizer, context: Context) {
        touch.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ touch: TouchRecognizer, context: Context) {
        switch touch.state {
        case .began: onPress(context.converter.localLocation)
        case .changed: onMove(context.converter.localLocation)
        case .ended: onEnd()
        case .cancelled: onCancel()
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }

    final class TouchRecognizer: UIGestureRecognizer {
        private var primary: UITouch?

        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let finger = touches.first, state == .possible else { return }
            primary = finger
            state = .began
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            if let primary, touches.contains(primary) { state = .changed }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            if let primary, touches.contains(primary) { state = .ended }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            if let primary, touches.contains(primary) { state = .cancelled }
        }

        override func location(in view: UIView?) -> CGPoint {
            primary?.location(in: view) ?? super.location(in: view)
        }

        override func reset() {
            super.reset()
            primary = nil
        }
    }
}
#endif
#endif
