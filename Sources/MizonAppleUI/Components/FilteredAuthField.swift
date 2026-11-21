#if os(macOS)
import AppKit
import SwiftUI

/// AppKit consults the formatter before replacing any text in the field editor.
final class AuthInputFormatter: Formatter {
    private let accepts: @Sendable (String) -> Bool

    init(accepts: @escaping @Sendable (String) -> Bool) {
        self.accepts = accepts
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override func string(for obj: Any?) -> String? { obj as? String }

    override func getObjectValue(
        _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
        for string: String,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        guard accepts(string) else { return false }
        obj?.pointee = string as NSString
        return true
    }

    override func isPartialStringValid(
        _ partialString: String,
        newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        accepts(partialString)
    }

    override func isPartialStringValid(
        _ partialStringPtr: AutoreleasingUnsafeMutablePointer<NSString>,
        proposedSelectedRange proposedSelRangePtr: NSRangePointer?,
        originalString origString: String,
        originalSelectedRange origSelRange: NSRange,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        accepts(partialStringPtr.pointee as String)
    }
}

final class AuthTextField: NSTextField {
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        onFocus?()
        return true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { isEnabled && isEditable }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // A click can enter the shared field editor without starting a text edit.
        if currentEditor() != nil { onFocus?() }
    }
}

struct FilteredAuthField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled
    let label: String
    let help: String
    let identifier: String
    let contentType: NSTextContentType
    let font: NSFont
    let accepts: @Sendable (String) -> Bool
    let submit: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = AuthTextField()
        field.delegate = context.coordinator
        field.onFocus = { [weak coordinator = context.coordinator] in coordinator?.reportFocus() }
        field.formatter = AuthInputFormatter(accepts: accepts)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.alignment = .left
        field.baseWritingDirection = .leftToRight
        field.contentType = contentType
        field.setAccessibilityIdentifier(identifier)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let coordinator = context.coordinator
        let focusChanged = coordinator.focusRequested != isFocused
        coordinator.focusRequested = isFocused
        coordinator.parent = self
        if let editor = field.currentEditor() {
            if editor.string != text { editor.string = text }
        } else if field.stringValue != text {
            field.stringValue = text
        }
        if field.font != font { field.font = font }
        if field.isEnabled != isEnabled { field.isEnabled = isEnabled }
        field.setAccessibilityLabel(label)
        field.setAccessibilityHelp(help)
        if focusChanged || (isFocused && field.currentEditor() == nil) {
            Task { @MainActor [weak field, weak coordinator] in
                guard let field, let coordinator, let window = field.window else { return }
                if coordinator.parent.isFocused && field.isEnabled {
                    if field.currentEditor() == nil { window.makeFirstResponder(field) }
                } else if field.currentEditor() != nil {
                    window.makeFirstResponder(nil)
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FilteredAuthField
        var focusRequested = false

        init(_ parent: FilteredAuthField) { self.parent = parent }

        func reportFocus() {
            if !parent.isFocused { parent.isFocused = true }
        }

        func controlTextDidBeginEditing(_ notification: Notification) { reportFocus() }

        func controlTextDidEndEditing(_ notification: Notification) {
            if parent.isFocused { parent.isFocused = false }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let edited = field.currentEditor()?.string ?? field.stringValue
            if parent.accepts(edited), parent.text != edited { parent.text = edited }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.submit()
            return true
        }
    }
}
#endif
