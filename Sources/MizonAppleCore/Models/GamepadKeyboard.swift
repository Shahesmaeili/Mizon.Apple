public struct GamepadKeyboard: Sendable {
    public enum Key: Sendable, Equatable {
        case character(Character)
        case language, layout, shift, backspace, done
        case caretPrevious, caretNext, selectAll, space, close

        public var width: Int {
            switch self {
            case .character, .caretPrevious, .caretNext: 1
            case .space: 4
            default: 2
            }
        }
    }

    private static let english = ["0123456789", "qwertyuiop", "asdfghjkl@", "zxcvbnm._-", ",?!'/\\:;+="]
    private static let persian = ["0123456789", "ضصثقفغعهخح", "جچشسیبلاتن", "مکگظطزرذدپ", "وئژؤآء؟@._"]
    private static let symbols = ["0123456789", "!@#$%^&*()", "-_=+[]{}\\|", ";:'\",.<>/?", "\u{60}~€£¥₹©®°×"]

    public let allowsPersian: Bool
    public let masksValue: Bool
    public var persian: Bool
    public var symbols = false
    public var uppercase = false
    public private(set) var row = 0
    public private(set) var column = 0
    public private(set) var caret: Int
    public private(set) var selectsAll = false

    public init(allowsPersian: Bool, masksValue: Bool, persian: Bool, length: Int) {
        self.allowsPersian = allowsPersian
        self.masksValue = masksValue
        self.persian = allowsPersian && persian
        self.caret = length
    }

    public var rows: [[Key]] {
        let letters = symbols ? Self.symbols : persian ? Self.persian : Self.english
        return letters.map { row in
            (uppercase && !symbols && !persian ? row.uppercased() : row).map(Key.character)
        } + [
            [.language, .layout, .shift, .backspace, .done],
            [.caretPrevious, .caretNext, .selectAll, .space, .close]
        ]
    }

    public var selectedKey: Key { rows[row][column] }

    public func isEnabled(_ key: Key) -> Bool {
        switch key {
        case .language: allowsPersian
        case .shift: !persian && !symbols
        case .caretPrevious, .caretNext, .selectAll: !masksValue
        default: true
        }
    }

    public mutating func move(_ direction: GamepadInputReducer.Direction) {
        let rows = self.rows
        func center(_ row: Int, _ column: Int) -> Double {
            Double(rows[row].prefix(column).reduce(0) { $0 + $1.width }) + Double(rows[row][column].width) / 2
        }
        switch direction {
        case .left, .right:
            let step = direction == .left ? -1 : 1
            var next = column + step
            while rows[row].indices.contains(next) {
                if isEnabled(rows[row][next]) { column = next; return }
                next += step
            }
        case .up, .down:
            let next = row + (direction == .up ? -1 : 1)
            guard rows.indices.contains(next) else { return }
            let current = center(row, column)
            guard let closest = rows[next].indices.filter({ isEnabled(rows[next][$0]) }).min(by: {
                abs(center(next, $0) - current) < abs(center(next, $1) - current)
            }) else { return }
            row = next
            column = closest
        }
    }

    public mutating func resetFocus() { row = 0; column = 0 }

    public mutating func key(for action: GamepadInputReducer.Action) -> Key? {
        switch action {
        case .accept: return selectedKey
        case .back: return .close
        case .submit: return .done
        case .clear: return .backspace
        case .reveal: return .shift
        case .help: return .language
        case .previousField: return .caretPrevious
        case .nextField: return .caretNext
        case .previousSection: return symbols ? .layout : nil
        case .nextSection: return symbols ? nil : .layout
        case .move(let direction): move(direction)
        case .primary, .reset: resetFocus()
        case .scroll: break
        }
        return nil
    }

    public mutating func edit(_ key: Key, value: String, accepts: (String) -> Bool) -> String? {
        guard isEnabled(key) else { return nil }
        let length = value.count
        let offset = masksValue ? length : min(caret, length)
        switch key {
        case .language: persian.toggle()
        case .layout: symbols.toggle()
        case .shift: uppercase.toggle()
        case .selectAll: selectsAll = true
        case .caretPrevious, .caretNext:
            if selectsAll {
                caret = key == .caretPrevious ? 0 : length
            } else {
                caret = min(length, max(0, offset + (key == .caretPrevious ? -1 : 1)))
            }
            selectsAll = false
        case .done, .close: break
        case .character, .space, .backspace:
            let insertion: String
            if case .character(let character) = key { insertion = String(character) }
            else { insertion = key == .space ? " " : "" }
            let left = selectsAll ? 0 : key == .backspace ? max(0, offset - 1) : offset
            let right = selectsAll ? length : offset
            let start = value.index(value.startIndex, offsetBy: left)
            let end = value.index(value.startIndex, offsetBy: right)
            var updated = value
            updated.replaceSubrange(start..<end, with: insertion)
            guard accepts(updated) else { return nil }
            caret = left + insertion.count
            selectsAll = false
            return updated
        }
        if !isEnabled(selectedKey) { resetFocus() }
        return nil
    }
}
