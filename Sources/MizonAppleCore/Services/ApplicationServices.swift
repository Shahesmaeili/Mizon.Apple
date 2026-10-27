import Foundation

@MainActor
public enum ApplicationServices {
    public static func makeLoginViewModel() -> LoginViewModel {
        let defaults = UserDefaults.standard
        let key = "mizon.installationID"
        let identifier = defaults.string(forKey: key) ?? UUID().uuidString.lowercased()
        defaults.set(identifier, forKey: key)
        return LoginViewModel(authentication: MizonAuthenticationService(installationID: identifier),
            serverAddress: defaults.string(forKey: "mizon.serverAddress") ?? BackendConfiguration.defaultAddress)
    }
}
