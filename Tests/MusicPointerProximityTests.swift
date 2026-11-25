#if os(macOS) || os(iOS)
import CoreGraphics
import Testing
@testable import MizonAppleUI

struct MusicPointerProximityTests {
    @Test func revealsBeforeEntryAndFollowsAnExteriorPointer() {
        let card = CGRect(x: 120, y: 180, width: 280, height: 190)
        let approach = MusicPointerSample(CGPoint(x: 82, y: 220), in: card)
        #expect(approach.point == CGPoint(x: -38, y: 40))
        #expect(approach.opacity == 0.5)

        let edge = MusicPointerSample(CGPoint(x: 120, y: 220), in: card)
        let entered = MusicPointerSample(CGPoint(x: 161, y: 247), in: card)
        #expect(edge.opacity == 1)
        #expect(entered.opacity == 1)
        #expect(entered.point == CGPoint(x: 41, y: 67))
        #expect(MusicPointerSample(CGPoint(x: 44, y: 220), in: card).opacity == 0)
    }

    @Test func stationaryPointerUpdatesWithScrollAndClearsOnExit() {
        let position = CGPoint(x: 180, y: 100)
        let card = CGRect(x: 120, y: 180, width: 280, height: 190)
        #expect(MusicPointerSample(position, in: card).opacity == 0)
        #expect(MusicPointerSample(position, in: card.offsetBy(dx: 0, dy: -42)).opacity == 0.5)
        #expect(MusicPointerSample(position, in: card.offsetBy(dx: 0, dy: -90)).opacity == 1)
        #expect(MusicPointerSample(nil, in: card).opacity == 0)
        #expect(MusicPointerSample(position, in: .zero).opacity == 0)
    }

    @Test func offscreenMotionKeepsAnInactiveSampleStable() {
        let location = CGPoint(x: 180, y: 100)
        let card = CGRect(x: 120, y: 220, width: 280, height: 190)
        #expect(MusicPointerSample(location, in: card) == .inactive)
        #expect(MusicPointerSample(location, in: card.offsetBy(dx: 0, dy: -44)) == .inactive)
        #expect(MusicPointerSample(location, in: card.offsetBy(dx: 0, dy: -45)) != .inactive)
    }
}
#endif
