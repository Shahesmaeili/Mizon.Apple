#if !os(watchOS)
import SwiftUI

struct WelcomeProfileBadge: View {
    let avatar: CGImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Circle().fill(AuthAppearance.cardFill)
                Circle().fill(.linearGradient(
                    colors: [AuthAppearance.accent.opacity(34.0 / 255), AuthAppearance.purple.opacity(8.0 / 255)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                if let avatar {
                    Image(decorative: avatar, scale: 1).resizable().scaledToFill()
                } else {
                    FluentIcon(symbol: .headphones, size: geometry.size.width * 0.45, usesColor: true)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(.circle)
            .overlay { Circle().strokeBorder(AuthAppearance.accentTint) }
        }
        .accessibilityHidden(true)
    }
}

struct WelcomeOrbit: View {
    let size: CGFloat
    let moves: Bool
    @State private var anchor: Date?
    @State private var elapsed: TimeInterval = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !moves)) { clock in
            let time = elapsed + (anchor.map { max(0, clock.date.timeIntervalSince($0)) } ?? 0)
            ZStack {
                ForEach([260.0, 204.0, 144.0], id: \.self) { diameter in
                    Circle().fill(AuthAppearance.accent.opacity(7.0 / 255))
                        .frame(width: diameter, height: diameter)
                }
                ZStack {
                    Circle().strokeBorder(AuthAppearance.accentWash).frame(width: 330, height: 330)
                    dot(8, x: 200, y: 35, color: AuthAppearance.accent)
                    dot(5, x: 49.5, y: 275.5, color: AuthAppearance.accentBorder)
                    dot(4, x: 341, y: 279, color: AuthAppearance.purple.opacity(90.0 / 255))
                }
                .frame(width: 400, height: 400)
                .rotationEffect(.degrees(time * 360 / 42))

                ZStack {
                    Circle().strokeBorder(AuthAppearance.purple.opacity(50.0 / 255),
                                          style: StrokeStyle(lineWidth: 1, dash: [1, 7]))
                        .frame(width: 264, height: 264)
                    dot(12, x: 331, y: 197, color: AuthAppearance.purple.opacity(22.0 / 255))
                    dot(6, x: 331, y: 197, color: AuthAppearance.purple)
                    dot(5, x: 88.5, y: 272.5, color: AuthAppearance.accent.opacity(180.0 / 255))
                }
                .frame(width: 400, height: 400)
                .rotationEffect(.degrees(-time * 360 / 62))

                ZStack {
                    Circle().strokeBorder(AuthAppearance.accentTint, lineWidth: 1.5)
                        .frame(width: 194, height: 194)
                    FluentIcon(symbol: .musicNote1, size: 12)
                        .foregroundStyle(AuthAppearance.accent)
                        .frame(width: 22, height: 22)
                        .background(AuthAppearance.accentWash, in: .rect(cornerRadius: 7))
                        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(AuthAppearance.accentBorder) }
                        .offset(x: -70, y: -70)
                    dot(5, x: 282.5, y: 241.5, color: AuthAppearance.accent.opacity(180.0 / 255))
                }
                .frame(width: 400, height: 400)
                .rotationEffect(.degrees(time * 360 / 88))

                Circle().strokeBorder(AuthAppearance.accentTint).frame(width: 114, height: 114)
            }
            .frame(width: 400, height: 400)
            .scaleEffect(size / 400)
            .frame(width: size, height: size)
        }
        .onChange(of: moves, initial: true) {
            if moves {
                anchor = .now
            } else if let anchor {
                elapsed += max(0, Date.now.timeIntervalSince(anchor))
                self.anchor = nil
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func dot(_ diameter: CGFloat, x: CGFloat, y: CGFloat, color: Color) -> some View {
        Circle().fill(color).frame(width: diameter, height: diameter).offset(x: x - 200, y: y - 200)
    }
}
#endif
