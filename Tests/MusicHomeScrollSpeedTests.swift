#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import MizonAppleUI

@MainActor
struct MusicHomeScrollSpeedTests {
    @Test(arguments: [CGScrollEventUnit.pixel, .line])
    func increasesTheVerticalDeltaAndPreservesNativeEventMetadata(_ unit: CGScrollEventUnit) throws {
        let core = try makeWheel(unit: unit, y: -20, x: 4)
        core.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2)
        let original = try #require(NSEvent(cgEvent: core))
        let phase = original.momentumPhase
        let timestamp = original.timestamp
        let location = original.locationInWindow
        var gain = MusicVerticalScrollGain()

        let result = gain.applying(to: original)
        #expect(result.scrollingDeltaY == -27)
        #expect(result.scrollingDeltaX == 4)
        #expect(result.hasPreciseScrollingDeltas == (unit == .pixel))
        #expect(result.momentumPhase == phase)
        #expect(result.timestamp == timestamp)
        #expect(result.locationInWindow == location)
    }

    @Test func smallTrackpadDeltasAccumulateTheirFractionalGain() throws {
        var gain = MusicVerticalScrollGain()
        var distance: CGFloat = 0
        for _ in 0..<20 {
            let original = try #require(NSEvent(cgEvent: makeWheel(unit: .pixel, y: 1)))
            distance += gain.applying(to: original).scrollingDeltaY
        }
        #expect(distance == 27)
    }

    @Test func feedMarkerResolvesTheNativeViewportAndLeavesTheNestedRailAlone() throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView:
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.red.frame(height: 120)
                    ScrollView(.horizontal) { Color.blue.frame(width: 900, height: 80) }
                    Color.green.frame(height: 620)
                }
                .background { MusicHomeScrollSpeed().frame(width: 0, height: 0) }
            }
            .scrollClipDisabled()
            .scrollIndicators(.hidden)
        )
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 260, height: 360),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let marker = try #require(descendants(of: host).compactMap { $0 as? MusicHomeScrollSpeed.ViewportMarker }.first)
        let viewport = try #require(marker.enclosingScrollView)
        let rail = try #require(descendants(of: viewport).compactMap { $0 as? NSScrollView }.first)
        let railCenter = rail.convert(CGPoint(x: rail.bounds.midX, y: rail.bounds.midY), to: nil)
        let clip = viewport.contentView
        let feedPoint = clip.convert(CGPoint(x: clip.bounds.midX, y: clip.bounds.minY + 30), to: nil)

        #expect(marker.ownsEvent(at: feedPoint, in: viewport))
        #expect(!marker.ownsEvent(at: railCenter, in: viewport))
        window.contentView = nil
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func makeWheel(unit: CGScrollEventUnit, y: Int32, x: Int32 = 0) throws -> CGEvent {
        try #require(CGEvent(scrollWheelEvent2Source: nil, units: unit, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0))
    }
}
#endif
