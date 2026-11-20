public enum AuthIdentifierInput {
    public static func isAllowed(_ text: String, allowsEmail: Bool) -> Bool {
        text.utf8.allSatisfy { code in
            switch code {
            case 48...57, 65...90, 97...122, 46, 95:
                true
            case 64, 43, 37, 45:
                allowsEmail
            default:
                false
            }
        }
    }
}
