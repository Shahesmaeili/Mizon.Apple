import SwiftUI

struct AuthLocalization: DynamicProperty {
    @AppStorage("mizon.authLanguage") var language = ""
    @Environment(\.locale) private var locale

    private static let bundles: [String: Bundle] = {
        var bundles: [String: Bundle] = [:]
        for language in ["en", "fa"] {
            if let url = Bundle.module.url(forResource: language, withExtension: "lproj"),
               let bundle = Bundle(url: url) {
                bundles[language] = bundle
            }
        }
        return bundles
    }()

    var isPersian: Bool {
        (language.isEmpty ? locale.language.languageCode?.identifier : language) == "fa"
    }

    subscript(key: String) -> String { string(key, table: "Auth") }

    func string(_ key: String, table: String) -> String {
        Self.string(key, table: table, language: isPersian ? "fa" : "en")
    }

    static func string(_ key: String, table: String, language: String) -> String {
        let value = bundles[language]?.localizedString(forKey: key, value: key, table: table)
        if let value, value != key { return value }
        return bundles["en"]?.localizedString(forKey: key, value: key, table: table) ?? key
    }

    func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        isPersian ? WindowsTypography.iranSans(size).weight(weight) : Self.englishFont(size, weight: weight)
    }

    static func englishFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        WindowsTypography.segoeAvailable ? .custom("Segoe UI Variable", size: size).weight(weight)
            : .system(size: size, weight: weight)
    }
}

#if !os(watchOS)
struct AuthLanguagePicker: View {
    var localization = AuthLocalization()

    var body: some View {
        Menu {
            Button(localization["GamepadKeyboardLanguageEnglish"]) { selectLanguage("en") }
            Button(localization["GamepadKeyboardLanguagePersian"]) { selectLanguage("fa") }
        } label: {
            FluentIcon(symbol: .globe, size: 17)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .authHandPointer(enabled: true)
        .fixedSize()
        .help(localization["LanguagePickerName"])
        .accessibilityIdentifier("auth.language")
        .accessibilityLabel(localization["LanguagePickerName"])
        .accessibilityHint(localization["LanguagePickerHelp"])
    }

    private func selectLanguage(_ language: String) {
        localization.language = language
        AccessibilityNotification.Announcement(
            AuthLocalization.string("LanguageChangedAnnouncement", table: "Auth", language: language)
        ).post()
    }
}
#endif
