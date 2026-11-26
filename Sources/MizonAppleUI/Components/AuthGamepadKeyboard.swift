#if os(macOS) || os(iOS)
import MizonAppleCore
import SwiftUI

struct AuthGamepadKeyboard: View {
    let keyboard: GamepadKeyboard
    let value: String?
    let prompt: String
    let activate: (GamepadKeyboard.Key) -> Void
    private let localization = AuthLocalization()

    var body: some View {
        GeometryReader { geometry in
            let width = min(520, max(0, geometry.size.width - 24))
            let spacing: CGFloat = 3
            let cell = max(0, (width - 24 - 9 * spacing) / 10)
            ScrollView {
                VStack(spacing: 6) {
                    Text(localization["GamepadKeyboardTitle"]).font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(prompt).font(.subheadline)
                    if let value {
                        let index = value.index(value.startIndex, offsetBy: min(value.count, keyboard.caret))
                        Text(keyboard.selectsAll ? value : String(value[..<index]) + "│" + String(value[index...]))
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(5)
                            .background(.white.opacity(keyboard.selectsAll ? 0.16 : 0.05), in: .rect(cornerRadius: 5))
                            .accessibilityLabel(value)
                    } else {
                        Text(localization["GamepadKeyboardPasswordHelp"]).font(.caption)
                    }
                    VStack(spacing: spacing) {
                        ForEach(Array(keyboard.rows.enumerated()), id: \.offset) { row, keys in
                            HStack(spacing: spacing) {
                                ForEach(Array(keys.enumerated()), id: \.offset) { column, key in
                                    let focused = keyboard.row == row && keyboard.column == column
                                    Button { activate(key) } label: {
                                        label(key)
                                            .font(.system(size: key.width == 1 ? 14 : 12, weight: .semibold))
                                            .frame(width: cell * CGFloat(key.width) + spacing * CGFloat(key.width - 1))
                                            .frame(minHeight: 30)
                                            .contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                    .background(.white.opacity(0.07), in: .rect(cornerRadius: 6))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(focused ? AuthAppearance.accent : .clear, lineWidth: 2)
                                            .allowsHitTesting(false)
                                    }
                                    .disabled(!keyboard.isEnabled(key))
                                    .accessibilityLabel(name(key))
                                    .accessibilityAddTraits(focused ? .isSelected : [])
                                }
                            }
                        }
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    Text(localization[keyboard.allowsPersian ? "GamepadKeyboardHelp" : "GamepadKeyboardIdentifierKeys"])
                        .font(.caption2)
                }
                .padding(12)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: width)
            .frame(maxHeight: min(380, geometry.size.height))
            .background(MizonPalette.surface, in: .rect(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(AuthAppearance.accentTint).allowsHitTesting(false) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder private func label(_ key: GamepadKeyboard.Key) -> some View {
        switch key {
        case .character(let character): Text(String(character))
        case .language: Text(name(key))
        case .layout: Text(keyboard.symbols ? "ABC" : "!#?")
        case .shift: Image(systemName: keyboard.uppercase ? "shift.fill" : "shift")
        case .backspace: Image(systemName: "delete.backward")
        case .done: Image(systemName: "checkmark")
        case .caretPrevious: Image(systemName: "arrow.left")
        case .caretNext: Image(systemName: "arrow.right")
        case .selectAll: Image(systemName: "selection.pin.in.out")
        case .space: Image(systemName: "space")
        case .close: Image(systemName: "xmark")
        }
    }

    private func name(_ key: GamepadKeyboard.Key) -> String {
        switch key {
        case .character(let value): String(value)
        case .language: localization[keyboard.persian ? "GamepadKeyboardLanguageEnglish" : "GamepadKeyboardLanguagePersian"]
        case .layout: localization[keyboard.symbols ? "GamepadKeyboardLetters" : "GamepadKeyboardSymbols"]
        case .shift: localization[keyboard.uppercase ? "GamepadKeyboardLowercase" : "GamepadKeyboardUppercase"]
        case .backspace: localization["GamepadKeyboardBackspace"]
        case .done: localization["GamepadKeyboardDone"]
        case .caretPrevious: localization["GamepadKeyboardCaretPrevious"]
        case .caretNext: localization["GamepadKeyboardCaretNext"]
        case .selectAll: localization["GamepadKeyboardSelectAll"]
        case .space: localization["GamepadKeyboardSpace"]
        case .close: localization["GamepadKeyboardClose"]
        }
    }
}
#endif
