#if os(macOS)
import CoreGraphics
import Testing
@testable import MizonAppleUI

struct MacMenuBarProfileTests {
    @Test func preservesTaskbarProportionsWithinTheSystemBar() {
        let compact = StatusArtworkMetrics(barHeight: 24)
        #expect(compact.control == 20)
        #expect(compact.itemWidth == 28)
        #expect(abs(compact.badge / compact.avatar - 9.0 / 32) < 0.0001)

        let tall = StatusArtworkMetrics(barHeight: 40)
        #expect(tall.control == 36)
        #expect(tall.avatar == 32)
        #expect(tall.badge == 9)
        #expect(tall.badgeOffset == 11)
        #expect(tall.cutoutRadius == 7)
    }

    @Test func placesTheEffectBelowTheMenuBarOnTheCurrentDisplay() {
        let screen = CGRect(x: -1280, y: -100, width: 1280, height: 776)
        let centered = CGRect(x: -280, y: 676, width: 28, height: 24)
        let effect = StatusArtworkMetrics.effectFrame(anchor: centered, usableScreen: screen)
        #expect(effect.midX == centered.midX)
        #expect(effect.maxY == centered.minY - 8)
        #expect(effect.size == CGSize(width: 208, height: 208))

        let atRightEdge = CGRect(x: -44, y: 676, width: 28, height: 24)
        let clamped = StatusArtworkMetrics.effectFrame(anchor: atRightEdge, usableScreen: screen)
        #expect(clamped.maxX == screen.maxX)
        #expect(screen.contains(clamped))
    }
}
#endif
