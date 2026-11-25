#if os(macOS)
import Testing
@testable import MizonAppleUI

struct MusicHomeFocusTests {
    @MainActor @Test func showsTheOutlineOnlyForFocusedKeyboardOrControllerNavigation() {
        let input = MusicHomeFocus()
        let focused = MusicHomeFocusOutline(isFocused: true, cornerRadius: 8, input: input)
        let unfocused = MusicHomeFocusOutline(isFocused: false, cornerRadius: 8, input: input)
        #expect(!focused.isVisible)

        input.updateForNavigation(true)
        #expect(focused.isVisible)
        #expect(!unfocused.isVisible)

        input.updateForNavigation(false)
        #expect(!focused.isVisible)
    }
}
#endif
