import QuartzCore
import SwiftUI

struct FlipSelection {
    private(set) var showsBack = false
    private(set) var motion: FlipMotion?

    func angle(at now: ContinuousClock.Instant) -> Double {
        motion?.angle(at: now) ?? restingAngle
    }

    mutating func toggle(at now: ContinuousClock.Instant, animated: Bool) {
        let startingAngle = angle(at: now)
        showsBack.toggle()
        motion = animated && abs(startingAngle - restingAngle) > FlipMotion.angleTolerance
            ? FlipMotion(startedAt: now, from: startingAngle, to: restingAngle)
            : nil
    }

    mutating func settle() { motion = nil }

    private var restingAngle: Double { showsBack ? 180 : 0 }
}

struct FlipMotion {
    private static let period = 0.2
    private static let dampingRatio = 0.5
    private static let frequency = 2 * Double.pi / period
    private static let sineWeight = dampingRatio / sqrt(1 - dampingRatio * dampingRatio)
    private static let decay = frequency * sineWeight

    // WinUI's completion threshold is internal. Bound the remaining travel and speed.
    static let angleTolerance = 0.1
    private static let velocityTolerance = 2.0

    let startedAt: ContinuousClock.Instant
    let from: Double
    let to: Double
    let end: ContinuousClock.Instant

    init(startedAt: ContinuousClock.Instant, from: Double, to: Double) {
        self.startedAt = startedAt
        self.from = from
        self.to = to
        let amplitude = abs(from - to) * hypot(1, Self.sineWeight)
        let speed = amplitude * hypot(Self.frequency, Self.decay)
        let decayRatio = max(1, amplitude / Self.angleTolerance, speed / Self.velocityTolerance)
        end = startedAt.advanced(by: .seconds(log(decayRatio) / Self.decay))
    }

    func angle(at now: ContinuousClock.Instant) -> Double {
        guard now < end else { return to }
        let elapsed = startedAt.duration(to: now).components
        let seconds = max(0, Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        let phase = seconds * Self.frequency
        // Composition describes Period as a complete oscillation. The sine term starts the
        // spring from rest at the current angle, including when a turn is interrupted.
        let remaining = exp(-Self.decay * seconds) * (cos(phase) + Self.sineWeight * sin(phase))
        return to + (from - to) * remaining
    }
}

struct FlipSide<Front: View, Back: View>: View {
    @Binding var selection: FlipSelection
    @ViewBuilder var side1: () -> Front
    @ViewBuilder var side2: () -> Back
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frontSize = CGSize.zero
    @State private var backSize = CGSize.zero

    var body: some View {
        let clock = ContinuousClock()
        let motion = selection.motion
        let showsBack = selection.showsBack
        let turning = motion != nil && !reduceMotion
        let depth = max(frontSize.width, frontSize.height, backSize.width, backSize.height, 1)
        let front = side1().onGeometryChange(for: CGSize.self, of: \.size) { frontSize = $0 }
        let back = side2().onGeometryChange(for: CGSize.self, of: \.size) { backSize = $0 }

        TimelineView(.animation(paused: !turning)) { _ in
            let angle = turning ? selection.angle(at: clock.now) : (showsBack ? 180.0 : 0)
            FaceLayout(showsBack: showsBack, reservesBothFaces: turning) {
                front.geometryGroup()
                    .modifier(FlipProjection(angle: angle, depth: depth))
                    .opacity(angle <= 90 ? 1 : 0)
                    .allowsHitTesting(!showsBack && angle <= 90)
                    .accessibilityHidden(showsBack)
                    .disabled(showsBack && !turning)
                back.geometryGroup()
                    .modifier(FlipProjection(angle: angle - 180, depth: depth))
                    .opacity(angle > 90 ? 1 : 0)
                    .allowsHitTesting(showsBack && angle > 90)
                    .accessibilityHidden(!showsBack)
                    .disabled(!showsBack && !turning)
            }
        }
        .task(id: motion?.startedAt) {
            guard let motion else { return }
            do { try await clock.sleep(until: motion.end) }
            catch { return }
            // An interrupted turn owns a different deadline.
            if !Task.isCancelled && selection.motion?.startedAt == motion.startedAt {
                selection.settle()
            }
        }
        .onChange(of: reduceMotion) {
            if reduceMotion { selection.settle() }
        }
    }
}

struct FaceLayout: Layout {
    let showsBack: Bool
    let reservesBothFaces: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let faceProposal = ProposedViewSize(width: proposal.width, height: nil)
        let active = subviews[showsBack ? 1 : 0].sizeThatFits(faceProposal)
        guard reservesBothFaces else { return active }
        let outgoing = subviews[showsBack ? 0 : 1].sizeThatFits(faceProposal)
        return CGSize(width: max(active.width, outgoing.width), height: max(active.height, outgoing.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for face in subviews {
            face.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                       proposal: .init(width: bounds.width, height: nil))
        }
    }
}

private nonisolated struct FlipProjection: GeometryEffect {
    let angle: Double
    let depth: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard angle != 0 else { return ProjectionTransform() }
        let x = size.width / 2
        let y = size.height / 2
        let rotation = CATransform3DMakeRotation(angle * .pi / 180, 0, 1, 0)
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / (6 * depth)
        let centered = CATransform3DConcat(CATransform3DMakeTranslation(-x, -y, 0), rotation)
        let projected = CATransform3DConcat(centered, perspective)
        return ProjectionTransform(CATransform3DConcat(projected, CATransform3DMakeTranslation(x, y, 0)))
    }
}
