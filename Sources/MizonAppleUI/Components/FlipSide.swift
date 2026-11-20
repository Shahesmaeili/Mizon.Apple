import SwiftUI
import QuartzCore

struct FlipSide<Front: View, Back: View>: View {
    var isFlipped: Bool
    @ViewBuilder var side1: () -> Front
    @ViewBuilder var side2: () -> Back
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle = 0.0
    @State private var isTurning = false
    @State private var transitionID = 0
    @State private var surfaceSize = CGSize.zero

    var body: some View {
        FaceLayout(showBack: isFlipped, showBoth: isTurning) {
            side1().modifier(FlipFace(angle: angle, back: false, surfaceSize: surfaceSize))
                .allowsHitTesting(!isFlipped).accessibilityHidden(isFlipped)
                .disabled(isFlipped)
            side2().modifier(FlipFace(angle: angle, back: true, surfaceSize: surfaceSize))
                .allowsHitTesting(isFlipped).accessibilityHidden(!isFlipped)
                .disabled(!isFlipped)
        }
        .onGeometryChange(for: CGSize.self, of: \.size) { surfaceSize = $0 }
        .onAppear { angle = isFlipped ? 180 : 0 }
        .onChange(of: isFlipped) { turn(to: isFlipped ? 180 : 0) }
        .onChange(of: reduceMotion) {
            if reduceMotion { turn(to: isFlipped ? 180 : 0) }
        }
    }

    private func turn(to target: Double) {
        transitionID += 1
        guard !reduceMotion else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { angle = target }
            isTurning = false
            return
        }
        isTurning = true
        let turnID = transitionID
        // Match the WinUI spring's 200 ms natural period and damping ratio of 0.5.
        withAnimation(.interpolatingSpring(mass: 1, stiffness: 986.96044, damping: 31.41593),
                      completionCriteria: .removed) {
            angle = target
        } completion: {
            if transitionID == turnID { isTurning = false }
        }
    }
}

private struct FaceLayout: Layout {
    var showBack: Bool
    var showBoth: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.init(width: proposal.width, height: nil)) }
        let active = sizes[showBack ? 1 : 0]
        guard showBoth else { return active }
        return CGSize(width: max(sizes[0].width, sizes[1].width), height: max(sizes[0].height, sizes[1].height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for face in subviews {
            face.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                       proposal: .init(width: bounds.width, height: nil))
        }
    }
}

private nonisolated struct FlipFace: AnimatableModifier {
    var angle: Double
    let back: Bool
    let surfaceSize: CGSize
    var animatableData: Double { get { angle } set { angle = newValue } }

    func body(content: Content) -> some View {
        content
            .opacity((angle > 90) == back ? 1 : 0)
            .modifier(FlipProjection(angle: angle + (back ? 180 : 0), surfaceSize: surfaceSize))
    }
}

private nonisolated struct FlipProjection: GeometryEffect {
    let angle: Double
    let surfaceSize: CGSize

    func effectValue(size: CGSize) -> ProjectionTransform {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let depth = max(surfaceSize.width, surfaceSize.height, size.width, size.height, 1)
        let rotation = CATransform3DMakeRotation(angle * .pi / 180, 0, 1, 0)
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / (6 * depth)
        let centered = CATransform3DConcat(CATransform3DMakeTranslation(-center.x, -center.y, 0), rotation)
        let projected = CATransform3DConcat(centered, perspective)
        return ProjectionTransform(CATransform3DConcat(projected, CATransform3DMakeTranslation(center.x, center.y, 0)))
    }
}
