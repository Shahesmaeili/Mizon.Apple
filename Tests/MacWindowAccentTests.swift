#if os(macOS)
import AppKit
import Testing
@testable import MizonAppleUI

@MainActor
struct MacWindowAccentTests {
    @Test func accentIsSiblingOfAnimatedContentAndFollowsWindowSize() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 280),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let content = try #require(window.contentView)
        let frameView = try #require(content.superview)
        let attachment = MacWindowAccent.Attachment(frame: .zero)
        content.addSubview(attachment)

        #expect(attachment.outline.superview === frameView)
        #expect(attachment.outline.frame == frameView.bounds)
        #expect(attachment.outline.frame.height == window.frame.height)
        #expect(attachment.outline.hitTest(NSPoint(x: 1, y: 1)) == nil)
        #expect(!content.subviews.contains(attachment.outline))

        window.styleMask.insert(.fullSizeContentView)
        window.setContentSize(NSSize(width: 540, height: 360))
        attachment.install()
        let updatedFrameView = try #require(content.superview)
        #expect(attachment.outline.superview === updatedFrameView)
        #expect(attachment.outline.frame == updatedFrameView.bounds)
        #expect(attachment.outline.frame.size == window.frame.size)

        attachment.removeFromSuperview()
        #expect(attachment.outline.superview == nil)
    }
}
#endif
