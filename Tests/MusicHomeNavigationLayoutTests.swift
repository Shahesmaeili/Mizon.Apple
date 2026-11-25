#if os(macOS) || os(iOS)
import CoreGraphics
import Testing
@testable import MizonAppleUI
#if os(macOS)
import AppKit
#endif

struct MusicHomeNavigationLayoutTests {
    private let widths: [MusicHomeNavigationSection: CGFloat] = [
        .music: 90, .movies: 125, .apps: 78, .vpn: 76
    ]

    @Test func keepsTabsInOrderAndReservesRoomForOverflow() {
        let layout = MusicHomeNavigationLayout(budget: 332, widths: widths, compactOverflow: false)

        #expect(layout.visible == [.movies])
        #expect(layout.hidden == [.apps, .vpn])
        #expect(!layout.compactMusic)
        #expect(layout.width == 255)
    }

    @Test func keepsTheSelectedTabAndOverflowAtTheTightestWidth() {
        let layout = MusicHomeNavigationLayout(budget: 68, widths: widths, compactOverflow: true)

        #expect(layout.compactMusic)
        #expect(layout.visible.isEmpty)
        #expect(layout.hidden == [.movies, .apps, .vpn])
        #expect(layout.width == 68)
    }

    @Test func waitsForExtraRoomBeforeReturningAllTabsToTheHeader() {
        let exactFit = MusicHomeNavigationLayout(budget: 369, widths: widths, compactOverflow: false)
        let stillOverflowing = MusicHomeNavigationLayout(
            budget: 373, widths: widths, compactOverflow: false, restoringAll: true
        )
        let restored = MusicHomeNavigationLayout(
            budget: 374, widths: widths, compactOverflow: false, restoringAll: true
        )

        #expect(exactFit.hidden.isEmpty)
        #expect(stillOverflowing.hidden == [.vpn])
        #expect(restored.visible == [.movies, .apps, .vpn])
        #expect(restored.hidden.isEmpty)
    }

    #if os(macOS)
    @MainActor @Test func musicHomeUsesAndRestoresTheWindowToolbarStyle() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 340, height: 350),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.toolbarStyle = .unifiedCompact
        let content = try #require(window.contentView)
        let header = MusicHomeToolbarStyle.ToolbarView()

        content.addSubview(header)
        #expect(window.toolbarStyle == .unified)

        header.removeFromSuperview()
        #expect(window.toolbarStyle == .unifiedCompact)
    }
    #endif
}
#endif
