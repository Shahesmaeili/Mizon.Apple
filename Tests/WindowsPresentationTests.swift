import Testing
import CoreText
@testable import MizonAppleUI

struct WindowsPresentationTests {
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
        for symbol in [FluentSymbol.personAccounts, .inPrivateAccount, .webAsset, .xboxController, .dismiss, .networkCheck, .checkmarkCircle] {
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
