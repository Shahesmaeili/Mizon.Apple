#if os(macOS)
import CoreGraphics
import Foundation
import Testing
@testable import MizonAppleUI

struct MacMenuBarProfileTests {
    @Test func retainsLoadedAvatarOnlyForTheSameMedia() throws {
        let context = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let oldMedia = UUID()
        let newMedia = UUID()
        var avatar = MacMenuBarProfile.Avatar(mediaID: oldMedia, image: image)

        avatar.update(.init(mediaID: oldMedia, image: nil))
        #expect(avatar.image === image)
        avatar.update(.init(mediaID: newMedia, image: nil))
        #expect(avatar.mediaID == newMedia)
        #expect(avatar.image == nil)
        avatar.update(.init(mediaID: newMedia, image: image))
        #expect(avatar.image === image)
        avatar.update(.init(mediaID: nil, image: nil))
        #expect(avatar.mediaID == nil)
        #expect(avatar.image == nil)
    }

    @Test func preservesTaskbarProportionsWithinTheSystemBar() {
        let compact = StatusArtworkMetrics(barHeight: 24)
        #expect(compact.control == 23)
        #expect(compact.itemWidth == 33)
        #expect(compact.avatar == 22)
        #expect(compact.emojiFont > 20)
        #expect(abs(compact.moodScale * MoodLottiePlayback.badgeSize.height - compact.control) < 0.0001)
        #expect(abs(compact.badge / compact.avatar - 9.0 / 32) < 0.0001)

        let external = StatusArtworkMetrics(barHeight: 22)
        #expect(external.avatar == 20)
        #expect(external.emojiFont > 19)
        #expect(external.control < 22)

        let tall = StatusArtworkMetrics(barHeight: 40)
        #expect(tall.control == 38)
        #expect(tall.avatar == 37)
        #expect(abs(tall.badge / tall.avatar - 9.0 / 32) < 0.0001)
        #expect(tall.badgeOffset + tall.badge / 2 < tall.control / 2)
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
