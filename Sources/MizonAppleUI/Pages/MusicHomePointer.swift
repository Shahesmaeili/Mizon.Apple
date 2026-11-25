#if os(macOS) || os(iOS)
import SwiftUI

@MainActor @Observable
final class MusicHomePointer {
    static let coordinateSpace = "MusicHomePointer"
    var location: CGPoint?

    #if os(macOS)
    private(set) var scrollStartedAt: Date?
    private(set) var timeSpentScrolling: TimeInterval = 0

    func setScrolling(_ isScrolling: Bool) {
        if isScrolling {
            if scrollStartedAt == nil { scrollStartedAt = .now }
        } else if let scrollStartedAt {
            timeSpentScrolling += max(0, Date.now.timeIntervalSince(scrollStartedAt))
            self.scrollStartedAt = nil
        }
    }
    #endif
}

struct MusicPointerSample: Equatable {
    static let inactive = Self(nil, in: .zero)

    let point: CGPoint?
    let size: CGSize
    let opacity: Double

    init(_ location: CGPoint?, in frame: CGRect) {
        if let location, frame.width > 0, frame.height > 0 {
            let local = CGPoint(x: location.x - frame.minX, y: location.y - frame.minY)
            let dx = local.x - min(max(0, local.x), frame.width)
            let dy = local.y - min(max(0, local.y), frame.height)
            let distance = hypot(dx, dy)
            if distance < 76 {
                let strength = 1 - distance / 76
                point = local
                size = frame.size
                opacity = strength * strength * (3 - 2 * strength)
                return
            }
        }
        point = nil
        size = .zero
        opacity = 0
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
            let location = enabled && isVisible && contrast != .increased ? pointer.location : nil
            let sample = location.map {
                MusicPointerSample($0, in: geometry.frame(in: .named(MusicHomePointer.coordinateSpace)))
            } ?? .inactive
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
