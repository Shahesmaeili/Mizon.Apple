import SwiftUI

enum AuthAppearance {
    static let accent = color(0x9CDDED)
    static let purple = color(0xC7A0F6)
    static let green = color(0x93D9C0)
    static let warm = color(0xE4BC94)
    static let brand = color(0xB9CFF0)
    static let accentWash = accent.opacity(22.0 / 255)
    static let accentTint = accent.opacity(50.0 / 255)
    static let accentBorder = accent.opacity(90.0 / 255)
    static let cardFill = Color.white.opacity(8.0 / 255)
    static let secondaryText = Color.white.opacity(197.0 / 255)
    static let stroke = Color.white.opacity(36.0 / 255)
    static let divider = Color.white.opacity(22.0 / 255)
    static let errorText = color(0xF5C6D2)
    static let errorAccent = color(0xF0A1B5)
    static let errorWash = errorAccent.opacity(22.0 / 255)
    static let errorBorder = errorAccent.opacity(64.0 / 255)
    static let errorFill = LinearGradient(
        colors: [color(0xC96787).opacity(33.0 / 255), color(0xC96787).opacity(8.0 / 255)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let windowError = color(0xEF6A7A)

    static func color(_ rgb: UInt32) -> Color {
        Color(red: Double((rgb >> 16) & 255) / 255,
              green: Double((rgb >> 8) & 255) / 255,
              blue: Double(rgb & 255) / 255)
    }

    static func inputFill(focused: Bool, hovered: Bool, disabled: Bool) -> Color {
        if disabled { return .white.opacity(8.0 / 255) }
        if focused { return accent.opacity(30.0 / 255) }
        return .white.opacity((hovered ? 22.0 : 12.0) / 255)
    }

    static func inputBorder(focused: Bool, hovered: Bool, disabled: Bool) -> Color {
        if disabled { return divider }
        if focused { return accent.opacity(185.0 / 255) }
        return .white.opacity((hovered ? 75.0 : 40.0) / 255)
    }
}

struct AuthActionStyle: ButtonStyle {
    let primary: Bool
    let reduceMotion: Bool
    var focused = false
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let over = enabled && (hovered || focused)
        let pressed = enabled && configuration.isPressed
        let radius: CGFloat = primary ? 13 : 23
        let animation = reduceMotion ? nil : Animation.timingCurve(0.2, 0.8, 1, 1, duration: 0.16)
        return configuration.label
            .foregroundStyle(primary ? AuthAppearance.color(0x142331) : .white)
            .padding(.horizontal, primary ? 14 : 22)
            .frame(minHeight: primary ? 48 : 46)
            .background {
                RoundedRectangle(cornerRadius: radius)
                    .fill(LinearGradient(stops: primary ? [
                        .init(color: AuthAppearance.color(0xB6E8EE), location: 0),
                        .init(color: AuthAppearance.color(0xA9D2ED), location: 0.55),
                        .init(color: AuthAppearance.color(0xBBBDF1), location: 1)
                    ] : [
                        .init(color: AuthAppearance.accent.opacity(37.0 / 255), location: 0),
                        .init(color: AuthAppearance.color(0xB6A6ED).opacity(21.0 / 255), location: 0.6),
                        .init(color: AuthAppearance.accent.opacity(7.0 / 255), location: 1)
                    ], startPoint: .topTrailing, endPoint: .bottomLeading))
                    .overlay {
                        RoundedRectangle(cornerRadius: radius)
                            .strokeBorder(primary ? .white.opacity(101.0 / 255) : AuthAppearance.accentBorder)
                    }
                    .overlay(alignment: .top) {
                        Rectangle().fill(.white.opacity(64.0 / 255))
                            .frame(height: 1)
                            .padding(.horizontal, 14)
                            .padding(.top, 1)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: radius)
                            .fill(.white.opacity(64.0 / 255 * (pressed ? 0.04 : over ? 0.16 : 0)))
                    }
            }
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(pressed ? 0.98 : over ? 1.012 : 1)
            .animation(animation, value: over)
            .animation(animation, value: pressed)
            .contentShape(.rect)
            .onHover { hovered = $0 }
            .authHandPointer(enabled: enabled)
    }
}

struct AuthSceneButtonStyle: ButtonStyle {
    let color: Color
    let selected: Bool
    let focused: Bool
    let reduceMotion: Bool
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let over = enabled && (hovered || focused)
        let pressed = enabled && configuration.isPressed
        let tint = enabled ? (selected ? 0.12 : 0) + (over ? 0.07 : 0) + (pressed ? 0.04 : 0) : 0.03
        let opacity = contrast == .increased ? 1 : !enabled ? 0.3 :
            colorScheme == .light ? 1 : pressed ? 0.8 : (over || selected) ? 1 : 0.64
        let moves = !reduceMotion && contrast != .increased

        return configuration.label
            .opacity(opacity)
            .background(color.opacity(tint), in: .rect(cornerRadius: 11))
            .background(.white.opacity(5.0 / 255), in: .rect(cornerRadius: 11))
            .overlay(alignment: .bottom) {
                Capsule().fill(color)
                    .frame(width: 20, height: 2)
                    .opacity(selected ? 1 : 0)
            }
            .animation(moves ? .linear(duration: 0.18) : nil, value: tint)
            .animation(moves ? .linear(duration: 0.18) : nil, value: opacity)
            .animation(moves ? .linear(duration: 0.18) : nil, value: selected)
            .scaleEffect(pressed ? 0.97 : over ? 1.025 : 1)
            .offset(y: over && !pressed ? -2 : 0)
            .animation(moves ? .timingCurve(0.2, 0.8, 1, 1, duration: 0.18) : nil, value: over)
            .animation(moves ? .timingCurve(0.2, 0.8, 1, 1, duration: 0.18) : nil, value: pressed)
            .frame(height: 44)
            .contentShape(.rect)
            .onHover { hovered = $0 }
            .authHandPointer(enabled: enabled)
    }
}

struct AuthFieldActionStyle: ButtonStyle {
    let isClear: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = enabled && configuration.isPressed
        let over = enabled && hovered
        let size: CGFloat = isClear ? 28 : 32
        let fill = isClear ? (pressed ? AuthAppearance.accentTint : over ? AuthAppearance.accentWash : AuthAppearance.cardFill)
            : AuthAppearance.accentWash
        let opacity = isClear ? (enabled ? pressed ? 0.65 : over ? 1 : 0.7 : 0.3) : (enabled ? 1 : 0.45)
        return configuration.label
            .foregroundStyle(AuthAppearance.accent)
            .opacity(opacity)
            .frame(width: size, height: size)
            .background(fill, in: .rect(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(isClear ? AuthAppearance.stroke : AuthAppearance.accentTint)
            }
            .scaleEffect(isClear ? 1 : pressed ? 0.98 : over ? 1.012 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: over)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: pressed)
            .contentShape(.rect)
            .onHover { hovered = $0 }
            .authHandPointer(enabled: enabled)
    }
}

extension View {
    @ViewBuilder
    func authHandPointer(enabled: Bool) -> some View {
        #if os(macOS)
        pointerStyle(enabled ? .link : nil)
        #else
        self
        #endif
    }
}
