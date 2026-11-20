import SwiftUI

enum AuthScene: String, CaseIterable, Identifiable {
    case music, cinema, vpn

    var id: Self { self }
    var next: Self {
        switch self {
        case .music: .cinema
        case .cinema: .vpn
        case .vpn: .music
        }
    }
    var key: String {
        switch self {
        case .music: "ShowcaseMusic"
        case .cinema: "ShowcaseCinema"
        case .vpn: "ShowcaseVpn"
        }
    }
    var selectorIcon: FluentSymbol {
        switch self {
        case .music: .headphones
        case .cinema: .moviesAndTv
        case .vpn: .shieldLock
        }
    }
    var color: Color {
        switch self {
        case .music: AuthAppearance.accent
        case .cinema: AuthAppearance.purple
        case .vpn: AuthAppearance.green
        }
    }
}

struct AuthShowcaseArtwork: View {
    let scene: AuthScene
    let elapsed: TimeInterval
    let moves: Bool
    private var time: TimeInterval { moves ? elapsed : 0 }

    var body: some View {
        ZStack {
            switch scene {
            case .music: music
            case .cinema: cinema
            case .vpn: vpn
            }
        }
        .frame(width: 400, height: 400)
        .allowsHitTesting(false)
    }

    private var music: some View {
        let accent = AuthAppearance.accent
        let purple = AuthAppearance.purple
        return ZStack {
            Circle().fill(accent.opacity(0.027)).frame(width: 342, height: 342)
            Circle().fill(accent.opacity(0.027)).frame(width: 278, height: 278)
            ZStack {
                Circle().strokeBorder(accent.opacity(0.20)).frame(width: 340, height: 340)
                Circle().fill(accent).frame(width: 10, height: 10).offset(y: -170)
                Circle().fill(accent.opacity(0.35)).frame(width: 5, height: 5).offset(x: -150, y: 84)
                Circle().fill(purple).frame(width: 5, height: 5).offset(x: 140, y: 84)
            }
            .rotationEffect(.degrees(time * 10))

            Circle().strokeBorder(purple.opacity(0.20), style: StrokeStyle(lineWidth: 1, dash: [1, 8]))
                .frame(width: 270, height: 270)
            RoundedRectangle(cornerRadius: 50).strokeBorder(accent.opacity(0.086))
                .frame(width: 156, height: 156).rotationEffect(.degrees(12))
            tile(.headphones, size: 66, width: 132, height: 132, radius: 42, color: accent,
                 startOpacity: 54, end: purple.opacity(11.0 / 255), usesColor: true)
                .scaleEffect(1 + 0.025 * pulse(period: 6))
            waveBars.offset(y: 143)
            tile(.video, size: 22, width: 44, height: 44, radius: 14, color: purple, borderOpacity: 50)
                .offset(x: 121, y: -106)
        }
    }

    private var waveBars: some View {
        let heights: [CGFloat] = [8, 15, 24, 17, 30, 34, 21, 29, 16, 25, 12, 7]
        return HStack(spacing: 6) {
            ForEach(heights.indices, id: \.self) { index in
                let color = index < 7 ? AuthAppearance.accent : AuthAppearance.purple
                let period = 2.2 + Double(index % 4) * 0.25
                let scale = moves ? 0.6 + 0.4 * pulse(period: period, delay: Double(index) * 0.08) : 1
                let opacity = index == 0 || index == 11 ? 90.0 : index == 1 || index == 10 ? 180.0 : 255.0
                Capsule().fill(color.opacity(opacity / 255))
                    .frame(width: 3, height: heights[index] * scale)
            }
        }
        .frame(width: 230, height: 58)
        .background(AuthAppearance.cardFill, in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(AuthAppearance.accentTint) }
    }

    private var cinema: some View {
        let purple = AuthAppearance.purple
        let warm = AuthAppearance.warm
        return ZStack {
            Circle().fill(purple.opacity(0.027)).frame(width: 340, height: 340)
            Circle().strokeBorder(purple.opacity(0.086)).frame(width: 270, height: 270)
            panel(width: 280, height: 178, radius: 24, color: purple)
                .rotationEffect(.degrees(-9)).offset(y: -17)
            panel(width: 280, height: 178, radius: 24, color: warm)
                .rotationEffect(.degrees(7)).offset(y: -8)
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 23)
                    .fill(.linearGradient(stops: [
                        .init(color: purple.opacity(41.0 / 255), location: 0),
                        .init(color: AuthAppearance.color(0x171B35).opacity(13.0 / 255), location: 0.65),
                        .init(color: warm.opacity(34.0 / 255), location: 1)
                    ], startPoint: .topTrailing, endPoint: .bottomLeading))
                Rectangle()
                    .fill(.linearGradient(colors: [.clear, .white.opacity(24.0 / 255), .clear],
                                          startPoint: .leading, endPoint: .trailing))
                    .frame(width: 76, height: 220).rotationEffect(.degrees(-20))
                    .offset(x: moves ? -100 + time.truncatingRemainder(dividingBy: 6) * (440.0 / 6) : 0)
                tile(.play, size: 30, width: 66, height: 66, radius: 33, color: warm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                Capsule().fill(AuthAppearance.divider).frame(height: 3)
                    .overlay(alignment: .leading) { Capsule().fill(purple.opacity(0.7)).frame(width: 94) }
                    .padding(.horizontal, 22).padding(.bottom, 20)
            }
            .frame(width: 282, height: 184)
            .clipShape(.rect(cornerRadius: 23))
            .overlay { RoundedRectangle(cornerRadius: 23).strokeBorder(purple.opacity(0.35)) }
            .scaleEffect(1 + 0.018 * pulse(period: 7))
            tile(.filmstrip, size: 28, width: 52, height: 52, radius: 16, color: purple).offset(x: 135, y: -116)
            HStack(spacing: 9) {
                tile(.video, size: 17, width: 54, height: 32, radius: 10, color: purple, borderOpacity: 50)
                tile(.tv, size: 17, width: 54, height: 32, radius: 10, color: warm, borderOpacity: 50)
                tile(.moviesAndTv, size: 17, width: 54, height: 32, radius: 10, color: AuthAppearance.accent, borderOpacity: 50)
            }
            .offset(y: 126)
        }
    }

    private var vpn: some View {
        let green = AuthAppearance.green
        let accent = AuthAppearance.accent
        return ZStack {
            Circle().strokeBorder(green.opacity(0.20), lineWidth: 1.5)
                .frame(width: 290, height: 290)
                .scaleEffect(1 + 0.08 * pulse(period: 3.5))
                .opacity(moves ? 0.3 + 0.7 * pulse(period: 3.5) : 1)
            Circle().fill(green.opacity(0.027)).overlay { Circle().strokeBorder(green.opacity(0.20)) }
                .frame(width: 310, height: 310)
            Ellipse().strokeBorder(green.opacity(0.086)).frame(width: 144, height: 310)
            Ellipse().strokeBorder(green.opacity(0.086)).frame(width: 310, height: 116)
            ZStack {
                Circle().fill(green.opacity(50.0 / 255)).frame(width: 12, height: 12)
                Circle().fill(green).frame(width: 6, height: 6)
            }
            .offset(y: -155)
            .rotationEffect(.degrees(time * (360.0 / 38)))
            Path { path in
                for point in [CGPoint(x: 87, y: 101), CGPoint(x: 310, y: 112),
                              CGPoint(x: 90, y: 294), CGPoint(x: 314, y: 291)] {
                    path.move(to: point)
                    path.addLine(to: CGPoint(x: 200, y: 200))
                }
            }
            .stroke(green.opacity(0.20), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
            tile(.globe, size: 21, width: 38, height: 38, radius: 12, color: green).offset(x: -113, y: -99)
            tile(.desktop, size: 20, width: 38, height: 38, radius: 12, color: accent).offset(x: 110, y: -88)
            tile(.wifi, size: 20, width: 38, height: 38, radius: 12, color: accent).offset(x: -110, y: 94)
            tile(.globe, size: 21, width: 38, height: 38, radius: 12, color: green).offset(x: 114, y: 91)
            tile(.shieldLock, size: 72, width: 136, height: 136, radius: 43, color: green,
                 startOpacity: 50, end: accent.opacity(9.0 / 255))
        }
    }

    private func pulse(period: TimeInterval, delay: TimeInterval = 0) -> Double {
        (1 - cos(max(0, time - delay) * 2 * .pi / period)) / 2
    }

    private func panel(width: CGFloat, height: CGFloat, radius: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: radius).fill(color.opacity(0.027))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(color.opacity(0.20)) }
            .frame(width: width, height: height)
    }

    private func tile(_ symbol: FluentSymbol, size: CGFloat, width: CGFloat, height: CGFloat,
                      radius: CGFloat, color: Color, startOpacity: Double = 22, end: Color? = nil,
                      borderOpacity: Double = 90, usesColor: Bool = false) -> some View {
        let fill = color.opacity(startOpacity / 255)
        return FluentIcon(symbol: symbol, size: size, usesColor: usesColor)
            .foregroundStyle(color)
            .frame(width: width, height: height)
            .background(.linearGradient(colors: [fill, end ?? fill],
                                        startPoint: .topTrailing, endPoint: .bottomLeading),
                        in: .rect(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(color.opacity(borderOpacity / 255)) }
    }
}
