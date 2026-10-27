import SwiftUI
import MizonAppleCore
import MizonAppleUI

@main
struct MizonWatchApp: App {
    @State private var model = ApplicationServices.makeLoginViewModel()
    var body: some Scene {
        WindowGroup { MizonRootView(model: model) }
    }
}
