import Foundation

public struct Registration: Equatable, Sendable {
    public var firstName = ""
    public var lastName = ""
    public var username = ""
    public var emailAddress = ""
    public var password = ""

    public init() {}

    var trimmed: Self {
        var result = self
        result.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        result.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        result.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        result.emailAddress = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    public func validationError(confirmation: String) -> String? {
        let value = trimmed
        for name in [value.firstName, value.lastName] {
            if !(1...60).contains(name.utf16.count) || name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
                return "AuthInvalidNameError"
            }
        }
        if !AuthIdentifierInput.isAllowed(username, allowsEmail: false) || value.username.range(of: #"^[A-Za-z0-9._]{3,32}$"#, options: .regularExpression) == nil {
            return "AuthInvalidUsernameError"
        }
        if !AuthIdentifierInput.isAllowed(emailAddress, allowsEmail: true) || value.emailAddress.utf16.count > 128 || !MizonAuthenticationService.isEmail(value.emailAddress)
            || value.emailAddress.contains("..") || value.emailAddress.hasPrefix(".")
            || value.emailAddress.contains(".@") {
            return "AuthInvalidEmailError"
        }
        if !(8...128).contains(value.password.utf16.count) { return "AuthInvalidPasswordError" }
        if !value.password.utf8.elementsEqual(confirmation.utf8) { return "AuthPasswordMismatchError" }
        return nil
    }
}
