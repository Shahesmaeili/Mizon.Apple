import Testing
import CoreText
#if os(macOS)
import Foundation
import MizonAppleCore
#endif
@testable import MizonAppleUI

struct WindowsPresentationTests {
    @Test func authenticationStringsLoadFromEachLanguageBundle() {
        #expect(AuthLocalization.string("AuthEmailLabel", table: "Auth", language: "en") == "Email")
        #expect(AuthLocalization.string("AuthEmailLabel", table: "Auth", language: "fa") == "ایمیل")
        #expect(AuthLocalization.string("ServerAddress", table: "Settings", language: "fa") == "آدرس سرور")
        #expect(AuthLocalization.string("SearchEmpty", table: "Search", language: "en") == "No results")
        #expect(AuthLocalization.string("AuthEmailLabel", table: "Auth", language: "de") == "Email")
    }

    #if os(macOS)
    @Test func macFieldFormatterRejectsTheProposedEdit() {
        let formatter = AuthInputFormatter {
            $0.utf16.count <= 128 && AuthIdentifierInput.isAllowed($0, allowsEmail: true)
        }
        let original = "sample@example.org"
        let originalSelection = NSRange(location: 2, length: 2)
        var selection = NSRange(location: 3, length: 0)
        var replacement: NSString = "saشle@example.org"
        #expect(!formatter.isPartialStringValid(&replacement, proposedSelectedRange: &selection,
                                               originalString: original, originalSelectedRange: originalSelection,
                                               errorDescription: nil))
        #expect(replacement == "saشle@example.org")
        replacement = "satle@example.org"
        #expect(formatter.isPartialStringValid(&replacement, proposedSelectedRange: &selection,
                                              originalString: original, originalSelectedRange: originalSelection,
                                              errorDescription: nil))
        #expect(!formatter.isPartialStringValid(String(repeating: "a", count: 129), newEditingString: nil,
                                               errorDescription: nil))
    }
    #endif

    @Test func randomRegeneratesAtMostFiveTimes() {
        var actual = DevRandom(state: 42)
        _ = actual.next(0, 100, reject: { _ in true })
        var expected = DevRandom(state: 42)
        for _ in 0..<6 { _ = expected.next(0, 100) }
        #expect(actual.state == expected.state)
    }
    @Test func starsPreserveSourceRangesAndCumulativeMotion() {
        var random = DevRandom(state: 1372)
        for big in [false, true] {
            for _ in 0..<1002 {
                let star = DevStar(big: big, random: &random)
                #expect(star.diameter >= (big ? 3 : 1))
                #expect(star.diameter < (big ? 5 : 3))
                #expect(star.duration >= (big ? 10 : 40))
                #expect(star.duration < (big ? 40 : 80))
                let first = star.sample(time: 0)
                #expect(first.z == star.z)
                let second = star.sample(time: star.duration)
                #expect(abs(second.z - (star.z + star.deltaZ)) < 0.001)
                let third = star.sample(time: 2 * star.duration)
                #expect(abs(third.z - (star.z + 2 * star.deltaZ)) < 0.001)
                #expect(first.opacity == star.minOpacity)
            }
        }
    }
    @Test func compositionEasingEndpointsAndMidpoint() {
        #expect(abs(devEase(0)) < 0.00001)
        #expect(abs(devEase(0.5) - 0.5) < 0.0001)
        #expect(abs(devEase(1) - 1) < 0.00001)
    }
    @Test @MainActor func actualWindowsFontsContainAllUsedGlyphs() {
        _ = WindowsTypography.registered
        let font = CTFontCreateWithName("SeagullFluentIcons" as CFString, 20, nil)
        #expect(CTFontCopyPostScriptName(font) as String == "SeagullFluentIcons")
        for symbol in FluentSymbol.allCases {
            for rtl in [false, true] {
                var chars = Array(symbol.glyph(rightToLeft: rtl).utf16)
                var glyphs = [CGGlyph](repeating: 0, count: chars.count)
                let supported = CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count)
                #expect(supported)
                #expect(glyphs.contains(where: { $0 != 0 }))
            }
        }
        let persian = CTFontCreateWithName("IRANSans" as CFString, 18, nil)
        #expect(CTFontCopyPostScriptName(persian) as String == "IRANSans")
    }
}
