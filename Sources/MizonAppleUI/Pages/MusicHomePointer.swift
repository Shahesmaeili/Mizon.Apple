#if os(macOS) || os(iOS)
import SwiftUI

@MainActor @Observable
final class MusicHomePointer {
    static let coordinateSpace = "MusicHomePointer"
    var location: CGPoint?
}

struct MusicPointerSample: Equatable {
    let point: CGPoint?
    let size: CGSize

    init(_ location: CGPoint?, in frame: CGRect) {
        point = location.map { CGPoint(x: $0.x - frame.minX, y: $0.y - frame.minY) }
        size = frame.size
    }

    var opacity: Double {
        guard let point, point.x.isFinite, point.y.isFinite, size.width > 0, size.height > 0 else { return 0 }
        let dx = point.x - min(max(0, point.x), size.width)
        let dy = point.y - min(max(0, point.y), size.height)
        let strength = max(0, 1 - hypot(dx, dy) / 76)
        return strength * strength * (3 - 2 * strength)
    }
}

struct MusicWidgetPointerGlow: View {
    let accent: Color
    let enabled: Bool
    @Environment(MusicHomePointer.self) private var pointer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var center = CGPoint.zero
    @State private var opacity = 0.0
    @State private var isVisible = false

    var body: some View {
        GeometryReader { geometry in
            let sample = MusicPointerSample(enabled && isVisible && contrast != .increased ? pointer.location : nil,
                in: geometry.frame(in: .named(MusicHomePointer.coordinateSpace)))
            let unitCenter = UnitPoint(x: center.x / max(1, geometry.size.width), y: center.y / max(1, geometry.size.height))
            RoundedRectangle(cornerRadius: 16, style: .circular)
                .strokeBorder(RadialGradient(stops: [
                    .init(color: accent, location: 0),
                    .init(color: accent.opacity(154.0 / 255), location: 0.55),
                    .init(color: accent.opacity(0), location: 1)
                ], center: unitCenter, startRadius: 0, endRadius: 175), lineWidth: 0.5)
                .transaction { $0.animation = nil }
                .opacity(opacity)
                .animation(reduceMotion || !enabled || !isVisible || contrast == .increased ? nil : .timingCurve(0.2, 0.75, 1, 1, duration: 0.14),
                           value: opacity)
                .onChange(of: sample, initial: true) { _, value in
                    let strength = value.opacity
                    if strength > 0, let point = value.point, point != center { center = point }
                    if strength != opacity, strength == 0 || strength == 1 || abs(strength - opacity) >= 0.02 { opacity = strength }
                }
        }
        .onScrollVisibilityChange(threshold: 0.001) { isVisible = $0 }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
