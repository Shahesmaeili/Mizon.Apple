import SwiftUI

struct FlipSide<Front: View, Back: View>: View {
    var isFlipped: Bool
    @ViewBuilder var side1: () -> Front
    @ViewBuilder var side2: () -> Back
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation = 0.0
    @State private var layoutProgress = 0.0
    @State private var isTurning = false
    @State private var transitionID = 0
    @State private var frontSize = CGSize.zero
    @State private var backSize = CGSize.zero

    var body: some View {
        let depth = max(frontSize.width, frontSize.height, backSize.width, backSize.height, 1)
        let turning = !reduceMotion && (isTurning || rotation != (isFlipped ? 1 : 0))
        FaceLayout(progress: layoutProgress) {
            side1()
                .onGeometryChange(for: CGSize.self, of: \.size) { frontSize = $0 }
                .geometryGroup()
                .modifier(FlipFace(rotation: rotation, back: false, depth: depth))
                .allowsHitTesting(!isFlipped).accessibilityHidden(isFlipped)
                .disabled(isFlipped && !turning)
            side2()
                .onGeometryChange(for: CGSize.self, of: \.size) { backSize = $0 }
                .geometryGroup()
                .modifier(FlipFace(rotation: rotation, back: true, depth: depth))
                .allowsHitTesting(isFlipped).accessibilityHidden(!isFlipped)
                .disabled(!isFlipped && !turning)
        }
        .onAppear { settle(at: isFlipped ? 1 : 0) }
        .onChange(of: isFlipped) { turn(to: isFlipped ? 1 : 0) }
        .onChange(of: reduceMotion) {
            if reduceMotion { settle(at: isFlipped ? 1 : 0) }
        }
    }

    private func turn(to target: Double) {
        guard !reduceMotion else {
            settle(at: target)
            return
        }
        transitionID += 1
        isTurning = true
        let turnID = transitionID

        // Let the scroll content follow the card without jumping at the spring endpoints.
        withAnimation(.smooth(duration: 0.28)) { layoutProgress = target }
        // Match the WinUI spring's 200 ms natural period and damping ratio of 0.5.
        withAnimation(.interpolatingSpring(mass: 1, stiffness: 986.96044, damping: 31.41593),
                      completionCriteria: .removed) {
            rotation = target
        } completion: {
            if transitionID == turnID { isTurning = false }
        }
    }

    private func settle(at target: Double) {
        transitionID += 1
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            rotation = target
            layoutProgress = target
            isTurning = false
        }
    }
}

struct FaceLayout: Layout {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.init(width: proposal.width, height: nil)) }
        let front = sizes[0]
        let back = sizes[1]
        let amount = min(1, max(0, progress))
        return CGSize(width: max(front.width, back.width), height: front.height + (back.height - front.height) * amount)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for face in subviews {
            face.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                       proposal: .init(width: bounds.width, height: nil))
        }
    }
}

private nonisolated struct FlipFace: AnimatableModifier {
    var rotation: Double
    let back: Bool
    let depth: CGFloat
    var animatableData: Double {
        get { rotation }
        set { rotation = newValue }
    }

    func body(content: Content) -> some View {
        let visible = (rotation > 0.5) == back
        let angle = Angle.degrees(180 * (rotation + (back ? 1 : 0)))
        return content.visualEffect { effect, geometry in
            effect
                .rotation3DEffect(angle, axis: (0, 1, 0), perspective: geometry.size.width / (6 * depth))
                .opacity(visible ? 1 : 0)
        }
    }
}
