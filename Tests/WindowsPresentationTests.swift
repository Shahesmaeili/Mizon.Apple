import Testing
import CoreText
import SwiftUI
#if os(macOS)
import AppKit
import Foundation
import MizonAppleCore
#endif
@testable import MizonAppleUI

struct WindowsPresentationTests {
    @Test @MainActor func flipReservesTheTallerFaceOnlyWhileTurning() {
        for (back, turning, height) in [(false, false, 100), (false, true, 220), (true, true, 220), (true, false, 220)] {
            let renderer = ImageRenderer(content: FaceLayout(showsBack: back, reservesBothFaces: turning) {
                Color.cyan.frame(width: 120, height: 100)
                Color.purple.frame(width: 120, height: 220)
            })
            renderer.scale = 1
            #expect(renderer.cgImage?.width == 120)
            #expect(renderer.cgImage?.height == height)
        }
    }

    @Test func flipCrossesAtNinetyDegreesAndPeaksHalfAnOscillationIn() {
        let start = ContinuousClock().now
        let motion = FlipMotion(startedAt: start, from: 0, to: 180)
        #expect(motion.angle(at: start) == 0)
        #expect(motion.angle(at: start.advanced(by: .milliseconds(35))) < 90)
        #expect(motion.angle(at: start.advanced(by: .milliseconds(36))) > 90)
        let peak = motion.angle(at: start.advanced(by: .milliseconds(100)))
        #expect(abs(peak - 209.346) < 0.01)
        #expect(peak > motion.angle(at: start.advanced(by: .milliseconds(99))))
        #expect(peak > motion.angle(at: start.advanced(by: .milliseconds(101))))
        #expect(abs(motion.angle(at: start.advanced(by: .milliseconds(200))) - 175.216) < 0.01)
        #expect(motion.angle(at: motion.end) == 180)
    }

    @Test func reversingTheFlipStartsAtTheCurrentAngleAndReduceMotionSettles() throws {
        let start = ContinuousClock().now
        var flip = FlipSelection()
        flip.toggle(at: start, animated: true)
        let reversedAt = start.advanced(by: .milliseconds(55))
        let interruptedAngle = flip.angle(at: reversedAt)
        flip.toggle(at: reversedAt, animated: true)
        #expect(!flip.showsBack)
        #expect(abs(flip.angle(at: reversedAt) - interruptedAngle) < 0.001)
        let reversedMotion = try #require(flip.motion)
        #expect(flip.angle(at: reversedAt.advanced(by: .milliseconds(36))) < interruptedAngle)
        #expect(flip.angle(at: reversedMotion.end) == 0)
        flip.toggle(at: reversedAt.advanced(by: .milliseconds(40)), animated: false)
        #expect(flip.showsBack)
        #expect(flip.motion == nil)
        #expect(flip.angle(at: reversedAt.advanced(by: .milliseconds(40))) == 180)
    }

    @Test func authenticationStringsLoadFromEachLanguageBundle() {
        #expect(AuthLocalization.string("AuthEmailLabel", table: "Auth", language: "en") == "Email")
        #expect(AuthLocalization.string("AuthEmailLabel", table: "Auth", language: "fa") == "ایمیل")
        #expect(AuthLocalization.string("ServerAddress", table: "Settings", language: "fa") == "آدرس سرور")
        #expect(AuthLocalization.string("SearchEmpty", table: "Search", language: "en") == "No results")
        #expect(AuthLocalization.string("AuthEmailLabel", table: "Auth", language: "de") == "Email")
    }

    #if os(macOS) || os(iOS)
    @Test(arguments: ["blue-hour", "orbit-models", "orbit-illustration", "orbit-team", "friend-amir", "friend-sara"])
    func musicArtworkDecodesFromTheResourceBundle(_ asset: String) async throws {
        let image = await MusicLocalArtwork.image(named: asset, maximumPixelSize: 256)
        let artwork = try #require(image)
        #expect(artwork.width > 0)
        #expect(artwork.height > 0)
        #expect(max(artwork.width, artwork.height) <= 256)
    }
    #endif

    #if os(macOS)
    @Test @MainActor func macFieldReportsFocusBeforeTyping() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let field = AuthTextField(frame: NSRect(x: 12, y: 12, width: 216, height: 24))
        var didFocus = false
        field.onFocus = { didFocus = true }
        window.contentView?.addSubview(field)

        #expect(window.makeFirstResponder(field))
        #expect(field.currentEditor() != nil)
        #expect(didFocus)
        #expect(field.stringValue.isEmpty)
        #expect(window.makeFirstResponder(nil))
        #expect(field.currentEditor() == nil)
    }

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
    @Test func englishPresentationRegistersTheBundledWeightsAndNativeFieldFace() throws {
        let faces: [(Font.Weight, String)] = [
            (.light, "Selawik-Light"), (.regular, "Selawik-Regular"),
            (.semibold, "Selawik-Semibold"), (.bold, "Selawik-Bold"),
        ]
        for (weight, expectedFace) in faces {
            let name = try #require(WindowsTypography.englishFontName(weight: weight))
            #expect(name == expectedFace)
            let font = CTFontCreateWithName(name as CFString, 14, nil)
            #expect(CTFontCopyPostScriptName(font) as String == expectedFace)
        }
        #expect(WindowsTypography.inputFontName(isPersian: false) == "Selawik-Regular")
        #expect(WindowsTypography.inputFontName(isPersian: true) == "IRANSans")
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
        let coloredHeadphones = Array(FluentSymbol.headphones.glyph(usesColor: true).utf16)
        var coloredGlyphs = [CGGlyph](repeating: 0, count: coloredHeadphones.count)
        #expect(CTFontGetGlyphsForCharacters(font, coloredHeadphones, &coloredGlyphs, coloredGlyphs.count))
        #expect(coloredGlyphs.contains(where: { $0 != 0 }))
        let persian = CTFontCreateWithName("IRANSans" as CFString, 18, nil)
        #expect(CTFontCopyPostScriptName(persian) as String == "IRANSans")
    }
}
