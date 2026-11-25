#if os(macOS) || os(iOS)
import AVFoundation
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
    static func extract(fromVideo file: URL) async -> MusicHeroPalette? {
        guard file.isFileURL, !Task.isCancelled else { return nil }
        let request = VideoFrameRequest(file: file)
        let frame = try? await withTaskCancellationHandler {
            try await request.frame()
        } onCancel: {
            Task { await request.cancel() }
        }
        guard let frame, !Task.isCancelled else { return nil }
        return await extract(from: frame)
    }

    private actor VideoFrameRequest {
        private let generator: AVAssetImageGenerator
        private var cancelled = false

        init(file: URL) {
            generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
        }

        func frame() async throws -> CGImage {
            guard !cancelled else { throw CancellationError() }
            return try await withCheckedThrowingContinuation { continuation in
                generator.generateCGImageAsynchronously(for: .zero) { image, _, error in
                    if let image { continuation.resume(returning: image) }
                    else { continuation.resume(throwing: error ?? CocoaError(.fileReadCorruptFile)) }
                }
            }
        }

        func cancel() {
            cancelled = true
            generator.cancelAllCGImageGeneration()
        }
    }

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
    @Environment(MusicHomePointer.self) private var pagePointer
    @State private var inputSize = CGSize.zero
    #endif

    private static let corner = MusicFeaturedArtworkShadow.cornerRadius
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
                                Canvas(colorMode: .nonLinear) { canvas, size in renderSpotlights(canvas, size: size, at: time) }
                                    .blendMode(.overlay)
                            }
                            if showSpectrum, let palette {
                                let opacity = edge.opacity(at: time)
                                if opacity > 0 {
                                    MusicHeroSpectrum(center: edge.center,
                                                      palette: paletteBlend?.value(toward: palette, at: time) ?? palette,
                                                      opacity: opacity)
                                }
                            }
                        }
                    }
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
            .background {
                GeometryReader { geometry in
                    let sample = MusicPointerSample(active ? pagePointer.location : nil,
                        in: geometry.frame(in: .named(MusicHomePointer.coordinateSpace)))
                    Color.clear.onChange(of: sample, initial: true) { _, value in
                        movePointer(value.point, in: value.size)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
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
        let bounds = CGRect(origin: .zero, size: size)
        guard bounds.width > 0, bounds.height > 0 else { return }
        var surface = context
        surface.clip(to: Path(roundedRect: bounds, cornerRadius: Self.corner, style: .circular))
        surface.blendMode = .screen
        let light = spotReturn?.value(at: time) ?? spot
        spotGradient(in: surface, bounds: bounds, center: light.center, height: light.height,
                     angles: (20, 50), color: Color(red: 1, green: 250.0 / 255, blue: 240.0 / 255),
                     intensity: 1, attenuation: (0.253, 0.58))
        if let ripple, time < ripple.motion.end {
            let progress = ripple.motion.progress(at: time)
            let final = min(max(max(bounds.width, bounds.height) * 2, 240), 1400)
            let height = 16 + (final - 16) * progress
            let fade = min(progress / 0.09, (1 - progress) / 0.91)
            spotGradient(in: surface, bounds: bounds, center: ripple.center, height: height,
                         angles: (44, 68), color: Color(red: 143.0 / 255, green: 135.0 / 255, blue: 124.0 / 255),
                         intensity: fade, attenuation: (0.006, 0))
        }
    }

    private func spotGradient(in context: GraphicsContext, bounds: CGRect, center: CGPoint,
                              height: CGFloat, angles: (inner: Double, outer: Double),
                              color: Color, intensity: Double, attenuation: (linear: Double, quadratic: Double)) {
        let inner = tan(angles.inner * .pi / 180)
        let outer = tan(angles.outer * .pi / 180)
        let innerFraction = inner / outer
        let radius = height * outer
        let samples = [0, innerFraction / 2, innerFraction, (innerFraction + 1) / 2, 1]
        let gradient = Gradient(stops: samples.map { position in
            // WinUI attenuation is based on the distance to this point on the target plane.
            let distance = hypot(height, radius * position) / 100
            let falloff = 1 / (1 + attenuation.linear * distance + attenuation.quadratic * distance * distance)
            let cone = min(1, (1 - position) / (1 - innerFraction))
            return .init(color: color.opacity(intensity * falloff * cone), location: position)
        })
        context.fill(Path(bounds), with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius))
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

struct MusicHeroSpectrum: View {
    let center: CGPoint
    let palette: MusicHeroPalette
    let opacity: Double

    private static let padding: CGFloat = 20
    private static let strokeWidth: CGFloat = 0.75
    private static let gain = premultipliedScale(3)

    private static func premultipliedScale(_ amount: Float) -> ColorMatrix {
        var matrix = ColorMatrix()
        matrix.r1 = amount
        matrix.g2 = amount
        matrix.b3 = amount
        matrix.a4 = amount
        return matrix
    }

    var body: some View {
        Canvas(colorMode: .nonLinear) { context, size in
            if opacity == 1 {
                render(context, size: size)
            } else {
                var group = context
                // Apply the pointer falloff to the completed premultiplied result.
                group.addFilter(.colorMatrix(Self.premultipliedScale(Float(opacity)), isPremultiplied: true))
                group.drawLayer { layer in render(layer, size: size) }
            }
        }
        .padding(-Self.padding)
    }

    private func render(_ context: GraphicsContext, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: Self.padding, dy: Self.padding)
        let strokeBounds = bounds.insetBy(dx: Self.strokeWidth / 2, dy: Self.strokeWidth / 2)
        let shortest = min(strokeBounds.width, strokeBounds.height)
        guard shortest > 0 else { return }
        let corner = MusicFeaturedArtworkShadow.cornerRadius
        let stroke = Path(roundedRect: strokeBounds, cornerRadius: min(corner - Self.strokeWidth / 2, shortest / 2), style: .circular)
        let gradient = GraphicsContext.Shading.radialGradient(Gradient(stops: [
            .init(color: palette.highlight.color(), location: 0),
            .init(color: palette.accent.color(opacity: 230.0 / 255), location: 0.30),
            .init(color: palette.base.color(opacity: 150.0 / 255), location: 0.67),
            .init(color: palette.base.color(opacity: 0), location: 1)
        ]), center: CGPoint(x: bounds.minX + center.x, y: bounds.minY + center.y),
            startRadius: 0, endRadius: min(max(shortest * 0.8, 130), 250))

        var halo = context
        var exterior = Path(CGRect(origin: .zero, size: size))
        let cornerRadius = min(corner, min(bounds.width, bounds.height) / 2)
        exterior.addPath(Path(roundedRect: bounds, cornerRadius: cornerRadius, style: .circular))
        halo.clip(to: exterior, style: FillStyle(eoFill: true))
        halo.drawLayer { layer in
            layer.addFilter(.colorMatrix(Self.gain, isPremultiplied: true))
            layer.drawLayer { source in
                source.addFilter(.blur(radius: 5.5))
                source.stroke(stroke, with: gradient, lineWidth: Self.strokeWidth)
            }
        }
        context.stroke(stroke, with: gradient, lineWidth: Self.strokeWidth)
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
        private var scrollUpdate: Task<Void, Never>?
        private var lastPoint: CGPoint?
        private var lastSize = CGSize.zero

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
                if event.type == .scrollWheel {
                    self?.scheduleScrollUpdate(for: event)
                } else {
                    self?.observe(event)
                }
                return event
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            scrollUpdate?.cancel()
            scrollUpdate = nil
            lastPoint = nil
            lastSize = .zero
        }

        private func scheduleScrollUpdate(for event: NSEvent) {
            guard scrollUpdate == nil, let window, event.window === window, window.isKeyWindow else { return }
            scrollUpdate = Task { @MainActor [weak self, weak window] in
                // Sample the final geometry after AppKit applies a batch of wheel events.
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard let self else { return }
                scrollUpdate = nil
                guard let window, self.window === window, window.isKeyWindow else { return }
                updateLocation(window.mouseLocationOutsideOfEventStream)
            }
        }

        private func observe(_ event: NSEvent) {
            guard let window, event.window == window, window.isKeyWindow else {
                publish(nil)
                return
            }
            let point = convert(event.locationInWindow, from: nil)
            let visible = visibleRect
            updateLocation(point, within: visible)
            if event.type == .leftMouseDown, visible.contains(point) { onPress?(point) }
        }

        private func updateLocation(_ windowPoint: CGPoint) {
            updateLocation(convert(windowPoint, from: nil), within: visibleRect)
        }

        private func updateLocation(_ point: CGPoint, within visible: CGRect) {
            let nearby = !visible.isEmpty && visible.insetBy(dx: -proximity, dy: -proximity).contains(point)
            publish(nearby ? point : nil)
        }

        private func publish(_ point: CGPoint?) {
            let size = bounds.size
            guard point != lastPoint || size != lastSize else { return }
            lastPoint = point
            lastSize = size
            onMove?(point, size)
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
