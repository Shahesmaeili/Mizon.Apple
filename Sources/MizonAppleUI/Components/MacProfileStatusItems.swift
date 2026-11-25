#if os(macOS)
import AppKit
import Observation
import SwiftUI

@MainActor
final class MacProfileStatusItems: NSObject {
    private typealias Presentation = MacMenuBarProfile.Presentation
    private let openProfile: () -> Void
    private let playMood: () -> Void
    private var profileItem: NSStatusItem?
    private var moodItem: NSStatusItem?
    private var profileHost: StatusArtworkHost?
    private var moodHost: StatusArtworkHost?
    private var presentation: Presentation?
    private var effectPanel: NSPanel?
    private var effectID: UUID?
    private var effectTimeout: Task<Void, Never>?
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    init(openProfile: @escaping () -> Void, playMood: @escaping () -> Void) {
        self.openProfile = openProfile
        self.playMood = playMood
        super.init()
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification)
        observe(.default, NSApplication.didChangeScreenParametersNotification)
    }

    isolated deinit {
        for (center, observer) in observers { center.removeObserver(observer) }
        removeItems()
    }

    func render(profile: MacMenuBarProfile.Presentation?) {
        presentation = profile
        guard let profile else {
            removeItems()
            return
        }
        let size = StatusArtworkMetrics(barHeight: NSStatusBar.system.thickness)

        // AppKit inserts new items to the left. Install the profile first so the optional mood
        // uses the same initial left-to-right order as the Windows taskbar.
        if profileItem == nil {
            (profileItem, profileHost) = makeItem("mizon.menuBar.profile", action: #selector(profilePressed))
        }
        if let profileItem, let profileHost, let button = profileItem.button {
            profileItem.length = size.itemWidth
            button.isEnabled = !profile.isOpening
            button.setAccessibilityLabel(profile.profileTitle)
            button.setAccessibilityValue(profile.profileStatus)
            button.toolTip = [profile.displayName, profile.profileStatus].filter { !$0.isEmpty }.joined(separator: " · ")
            profileHost.rootView = StatusArtwork(
                symbol: .profile(profile.avatar, profile.displayName, online: profile.isOnline, busy: profile.isOpening),
                metrics: size, interaction: profileHost.interaction
            )
        }

        if let mood = profile.mood {
            if moodItem == nil {
                (moodItem, moodHost) = makeItem("mizon.menuBar.mood", action: #selector(moodPressed))
            }
            if let moodItem, let moodHost, let button = moodItem.button {
                moodItem.length = size.itemWidth
                button.setAccessibilityLabel(mood.accessibilityTitle)
                button.toolTip = mood.title
                moodHost.rootView = StatusArtwork(symbol: .mood(mood.emoji, mood.loop),
                                                  metrics: size, interaction: moodHost.interaction)
                moodHost.refreshVisibility()
            }
        } else {
            stopEffect()
            if let moodItem { NSStatusBar.system.removeStatusItem(moodItem) }
            moodItem = nil
            moodHost = nil
        }
    }

    func showEffect(file: URL) {
        stopEffect()
        guard let button = moodItem?.button, let window = button.window, let screen = window.screen,
              window.isVisible, moodHost?.interaction.visible == true,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let frame = StatusArtworkMetrics.effectFrame(anchor: anchor, usableScreen: screen.visibleFrame)
        let effect = MoodEffectPresentation(id: UUID(), file: file)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.level = .statusBar
        panel.contentView = NSHostingView(rootView:
            MoodLottieView(file: file, playback: .once(effect.playback), playing: true) { } onCompletion: { [weak self] in
                self?.finishEffect(effect.id)
            }
        )
        effectID = effect.id
        effectPanel = panel
        panel.orderFrontRegardless()

        // A missing native completion or unreadable asset must release the overlay too.
        effectTimeout = Task { [weak self, id = effect.id] in
            do {
                try await Task.sleep(for: .seconds(25))
                self?.finishEffect(id)
            } catch { }
        }
    }

    func stopEffect() {
        effectTimeout?.cancel()
        effectTimeout = nil
        effectID = nil
        effectPanel?.orderOut(nil)
        effectPanel?.contentView = nil
        effectPanel?.close()
        effectPanel = nil
    }

    private func finishEffect(_ id: UUID) {
        if effectID == id { stopEffect() }
    }

    private func removeItems() {
        stopEffect()
        if let moodItem { NSStatusBar.system.removeStatusItem(moodItem) }
        if let profileItem { NSStatusBar.system.removeStatusItem(profileItem) }
        moodItem = nil
        profileItem = nil
        moodHost = nil
        profileHost = nil
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.stopEffect()
                self.render(profile: self.presentation)
            }
        }
        observers.append((center, observer))
    }

    private func makeItem(_ identifier: String, action: Selector) -> (NSStatusItem, StatusArtworkHost) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let interaction = StatusArtworkInteraction()
        let host = StatusArtworkHost(rootView: StatusArtwork(
            symbol: .empty, metrics: .init(barHeight: NSStatusBar.system.thickness), interaction: interaction
        ))
        host.interaction = interaction
        if let button = item.button {
            button.setAccessibilityIdentifier(identifier)
            button.target = self
            button.action = action
            host.frame = button.bounds
            host.autoresizingMask = [.width, .height]
            button.addSubview(host)
            if identifier == "mizon.menuBar.mood" { host.onHide = { [weak self] in self?.stopEffect() } }
        }
        return (item, host)
    }

    @objc private func profilePressed() { openProfile() }
    @objc private func moodPressed() { playMood() }
}

struct StatusArtworkMetrics {
    let control: CGFloat
    var itemWidth: CGFloat { control + 8 }
    var scale: CGFloat { control / 36 }
    var avatar: CGFloat { 32 * scale }
    var badge: CGFloat { avatar * 9 / 32 }
    var badgeOffset: CGFloat { avatar * 11 / 32 }
    var cutoutRadius: CGFloat { avatar * 7 / 32 }

    init(barHeight: CGFloat) {
        control = min(36, max(1, barHeight - 4))
    }

    static func effectFrame(anchor: CGRect, usableScreen: CGRect) -> CGRect {
        let size = MoodLottiePlayback.effectSize
        let x = max(usableScreen.minX, min(anchor.midX - size.width / 2, usableScreen.maxX - size.width))
        let top = min(anchor.minY, usableScreen.maxY)
        return CGRect(x: x, y: top - 8 - size.height, width: size.width, height: size.height)
    }
}

@MainActor @Observable
private final class StatusArtworkInteraction {
    var hovered = false
    var visible = false
}

private final class StatusArtworkHost: NSHostingView<StatusArtwork> {
    var interaction = StatusArtworkInteraction()
    var onHide: (() -> Void)?
    private var tracking: NSTrackingArea?
    private var occlusionObserver: (any NSObjectProtocol)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited,
                                                       .cursorUpdate], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { interaction.hovered = true }
    override func mouseExited(with event: NSEvent) { interaction.hovered = false }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        if let window {
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshVisibility() }
            }
        }
        refreshVisibility()
    }

    func refreshVisibility() {
        let wasVisible = interaction.visible
        interaction.visible = window?.isVisible == true && window?.occlusionState.contains(.visible) == true
        if !interaction.visible {
            interaction.hovered = false
            if wasVisible { onHide?() }
        }
    }

    isolated deinit {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }
}

private struct StatusArtwork: View {
    enum Symbol {
        case empty
        case profile(CGImage?, String, online: Bool, busy: Bool)
        case mood(String, URL?)
    }

    let symbol: Symbol
    let metrics: StatusArtworkMetrics
    let interaction: StatusArtworkInteraction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var readyLoop: URL?

    var body: some View {
        ZStack {
            switch symbol {
            case .empty:
                Color.clear
            case let .profile(image, name, online, busy):
                ZStack {
                    if busy { progress }
                    ZStack {
                        MusicHomeProfilePicture(avatar: image, displayName: name)
                            .scaleEffect(metrics.scale)
                            .frame(width: metrics.avatar, height: metrics.avatar)
                            .mask { cutoutMask }
                        Circle()
                            .fill(online ? Color(red: 48 / 255, green: 201 / 255, blue: 127 / 255)
                                         : Color(red: 141 / 255, green: 150 / 255, blue: 168 / 255))
                            .frame(width: metrics.badge, height: metrics.badge)
                            .offset(x: metrics.badgeOffset, y: metrics.badgeOffset)
                    }
                    .scaleEffect(interaction.hovered && !reduceMotion ? 1.06 : 1)
                }
            case let .mood(emoji, loop):
                let playsLoop = interaction.visible && !reduceMotion
                ZStack {
                    if !playsLoop || loop == nil || loop != readyLoop {
                        Text(emoji).font(.system(size: 26 * metrics.scale))
                    }
                    if let loop {
                        MoodLottieView(file: loop, playback: .loop, playing: playsLoop,
                                       onReady: { readyLoop = loop })
                            .id(loop)
                            .opacity(playsLoop ? 1 : 0)
                            .scaleEffect(x: 28 * metrics.scale / MoodLottiePlayback.badgeSize.width,
                                         y: 28 * metrics.scale / MoodLottiePlayback.badgeSize.height)
                    }
                }
                .scaleEffect(interaction.hovered && !reduceMotion ? 1.06 : 1)
            }
        }
        .frame(width: metrics.control, height: metrics.control)
        .overlay {
            if interaction.hovered {
                Circle()
                    .fill(LinearGradient(colors: [
                        Color(red: 156 / 255, green: 221 / 255, blue: 237 / 255).opacity(0.24), .clear
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay { Circle().strokeBorder(.white.opacity(0.34), lineWidth: 1) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: interaction.hovered)
        .accessibilityHidden(true)
    }

    private var progress: some View {
        TimelineView(.animation(paused: !interaction.visible || reduceMotion)) { context in
            let angle = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(MizonPalette.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .padding(1)
                .rotationEffect(.degrees(angle))
        }
        .frame(width: metrics.control, height: metrics.control)
        .mask { cutoutMask }
    }

    private var cutoutMask: some View {
        Path { path in
            let size = metrics.control
            path.addRect(CGRect(x: 0, y: 0, width: size, height: size))
            let center = size / 2 + metrics.badgeOffset
            let radius = metrics.cutoutRadius
            path.addEllipse(in: CGRect(x: center - radius, y: center - radius, width: radius * 2, height: radius * 2))
        }
        .fill(.white, style: FillStyle(eoFill: true))
        .frame(width: metrics.control, height: metrics.control)
    }
}
#endif
