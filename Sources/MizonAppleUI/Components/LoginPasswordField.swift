#if os(iOS)
import SwiftUI
import UIKit

/// Keeps the same first responder while the login password is revealed or hidden.
struct LoginPasswordField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled
    let dismissesFocus: Bool
    let isSecure: Bool
    let label: String
    let help: String
    let identifier: String
    let font: UIFont
    let textColor: UIColor
    let submit: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        field.textContentType = .password
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.borderStyle = .none
        field.textAlignment = .left
        field.semanticContentAttribute = .forceLeftToRight
        field.accessibilityIdentifier = identifier
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if field.isEnabled != isEnabled { field.isEnabled = isEnabled }
        if field.font != font { field.font = font }
        if field.textColor != textColor { field.textColor = textColor }
        field.accessibilityLabel = label
        field.accessibilityHint = help
        if field.isSecureTextEntry != isSecure {
            let selection = field.selectedTextRange
            field.isSecureTextEntry = isSecure
            field.text = text
            field.selectedTextRange = selection
        } else if field.text != text {
            field.text = text
        }

        // Let the next input take focus directly. Resign only when the form dismisses focus.
        if (isFocused && !field.isFirstResponder) || (dismissesFocus && field.isFirstResponder) {
            Task { @MainActor [weak field, weak coordinator] in
                guard let field, let coordinator, field.window != nil else { return }
                if coordinator.parent.isFocused && field.isEnabled {
                    field.becomeFirstResponder()
                } else if coordinator.parent.dismissesFocus && field.isFirstResponder {
                    field.resignFirstResponder()
                }
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: LoginPasswordField

        init(_ parent: LoginPasswordField) { self.parent = parent }

        @objc func editingChanged(_ field: UITextField) { parent.text = field.text ?? "" }

        func textFieldDidBeginEditing(_ textField: UITextField) { parent.isFocused = true }

        func textFieldDidEndEditing(_ textField: UITextField) { parent.isFocused = false }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.submit()
            return false
        }
    }
}
#endif
