import SwiftUI

struct Starfield: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let stars: [(Double, Double, Double, Double)] = {
        var seed: UInt64 = 0x4D495A4F4E
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1
            return Double(seed >> 11) / Double(UInt64.max >> 11)
        }
        return (0..<125).map { _ in (random(), random(), random(), random()) }
    }()
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 0.35
                for (x, y, radius, phase) in Self.stars {
                    let r = 0.65 + radius * 1.25
                    let opacity = 0.2 + (sin(t + phase * 30) + 1) * 0.19
                    context.fill(Path(ellipseIn: CGRect(x: x * size.width, y: y * size.height, width: r, height: r)), with: .color(.white.opacity(opacity)))
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct LoginBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.025, green: 0.035, blue: 0.065)
                RadialGradient(colors: [Color.cyan.opacity(0.2), .clear], center: .init(x: 0.15, y: 0.38), startRadius: 1, endRadius: geometry.size.width * 0.62)
                RadialGradient(colors: [Color.indigo.opacity(0.25), .clear], center: .init(x: 0.85, y: 0.75), startRadius: 1, endRadius: geometry.size.width * 0.6)
                Starfield()
                Ellipse().stroke(.white.opacity(0.045), lineWidth: 1)
                    .frame(width: geometry.size.width * 0.92, height: geometry.size.height * 0.55)
                    .rotationEffect(.degrees(-24))
                Ellipse().stroke(.cyan.opacity(0.045), lineWidth: 1)
                    .frame(width: geometry.size.width * 1.2, height: geometry.size.height * 0.72)
                    .rotationEffect(.degrees(-24))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
