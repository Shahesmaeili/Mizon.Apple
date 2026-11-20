import Foundation
import MizonAPI

@MainActor
public enum ApplicationServices {
    public static func makeLoginViewModel() -> LoginViewModel {
        let defaults = UserDefaults.standard
        let key = "mizon.installationID"
        let identifier = defaults.string(forKey: key) ?? UUID().uuidString.lowercased()
        defaults.set(identifier, forKey: key)
        let api = MizonApi(languageProvider: {
            switch UserDefaults.standard.string(forKey: "mizon.authLanguage") {
            case "fa": "fa-IR"
            case "en": "en-US"
            default: Locale.preferredLanguages.first
            }
        })
        return LoginViewModel(authentication: MizonAuthenticationService(api: api, installationID: identifier),
            welcomeService: MizonWelcomeService(api: api),
            serverAddress: defaults.string(forKey: "mizon.serverAddress") ?? BackendConfiguration.defaultAddress)
    }
}
