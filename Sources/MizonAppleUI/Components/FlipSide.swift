import SwiftUI

/// Native translation of DevWinUI FlipSide: Y axis, 200ms spring period,
/// damping 0.5, perspective distance equal to layout width, angle-driven visibility.
struct FlipSide<Side1: View, Side2: View>: View {
    var isFlipped: Bool
    @ViewBuilder var side1: () -> Side1
    @ViewBuilder var side2: () -> Side2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            side1().modifier(FlipFace(angle: isFlipped ? 180 : 0, back: false))
                .allowsHitTesting(!isFlipped).accessibilityHidden(isFlipped)
            side2().modifier(FlipFace(angle: isFlipped ? 360 : 180, back: true))
                .allowsHitTesting(isFlipped).accessibilityHidden(!isFlipped)
        }
        .frame(width: 304, height: 500)
        .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.5), value: isFlipped)
    }
}
private nonisolated struct FlipFace: AnimatableModifier {
    var angle: Double
    var back: Bool
    var animatableData: Double { get { angle } set { angle = newValue } }
    func body(content: Content) -> some View {
        content
            .opacity(back ? (angle - 180 > 90 ? 1 : 0) : (angle > 90 ? 0 : 1))
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 1)
    }
}
