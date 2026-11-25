#if os(macOS) || os(iOS)
import GameController
import MizonAppleCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct NearbyDevicesControl: View {
    let peers: [NearbyDiscoveredPeer]
    var avatars: [String: CGImage] = [:]
    @Binding var enabled: Bool
    let status: NearbyDiscoveryStatus
    let viewport: CGSize
    var controllerPress: UInt = 0
    var onPresentationChange: (Bool) -> Void = { _ in }

    @State private var showing = false
    @State private var controllerEntry = false
    private var localization = AuthLocalization()

    var body: some View {
        Button {
            controllerEntry = false
            showing = true
        } label: {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(enabled ? status.tint : Color.secondary)
                .frame(width: 36, height: 32)
        }
        .buttonStyle(MusicHomeButtonStyle(corner: 10))
        .accessibilityIdentifier("music.home.nearby")
        .accessibilityLabel(text("Title"))
        .accessibilityValue(text(status.titleKey))
        .help(text("Title"))
        .popover(isPresented: $showing, arrowEdge: .top) {
            NearbyDevicesPanel(peers: peers, avatars: avatars, enabled: $enabled, status: status, viewport: viewport,
                               controllerEntry: controllerEntry) { showing = false }
                .presentationCompactAdaptation(.popover)
        }
        .onChange(of: controllerPress) {
            controllerEntry = true
            showing = true
        }
        .onChange(of: showing) {
            if !showing { controllerEntry = false }
            onPresentationChange(showing)
        }
        .onDisappear { onPresentationChange(false) }
    }

    private func text(_ key: String) -> String { localization.string(key, table: "NearbyDevices") }
}

private struct NearbyDevicesPanel: View {
    private enum FocusTarget: Hashable { case close, visibility }

    let peers: [NearbyDiscoveredPeer]
    let avatars: [String: CGImage]
    @Binding var enabled: Bool
    let status: NearbyDiscoveryStatus
    let viewport: CGSize
    let controllerEntry: Bool
    let close: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var focused: FocusTarget?
    private var localization = AuthLocalization()

    private var visiblePeers: [NearbyDiscoveredPeer] {
        guard enabled && status == .ready else { return [] }
        return peers.sorted {
            let order = $0.deviceName.localizedStandardCompare($1.deviceName)
            return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
        }
    }

    private var width: CGFloat { max(1, min(356, viewport.width - 28)) }

    private func height(for count: Int) -> CGFloat {
        let desired: CGFloat = enabled ? 412 + CGFloat(min(count, 2)) * 52 : 372
        return max(180, min(520, desired, viewport.height - 70))
    }

    var body: some View {
        let devices = visiblePeers
        VStack(alignment: .leading, spacing: 12) {
            heading

            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        visibility.id(FocusTarget.visibility)
                        NearbyOrbit(peers: Array(devices.prefix(6)),
                                    scanAvailable: enabled && (status == .searching || status == .ready),
                                    enabled: enabled, tint: status.tint)
                            .frame(height: width < 300 ? 127 : 153)
                        if devices.isEmpty {
                            stateMessage
                        } else {
                            deviceList(devices)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.bottom, 2)
                }
                .scrollIndicators(.visible)
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: focused) {
                    if focused == .visibility { reader.scrollTo(FocusTarget.visibility, anchor: .top) }
                }
            }
        }
        .padding(14)
        .frame(width: width, height: height(for: devices.count))
        .background {
            if reduceTransparency {
                Color(white: 0.14)
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
        .environment(\.layoutDirection, localization.isPersian ? .rightToLeft : .leftToRight)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            if controllerEntry { focused = .visibility }
            await observeController()
        }
    }

    private var heading: some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(NearbyAppearance.accent)
                .frame(width: 40, height: 40)
                .background(NearbyAppearance.accent.opacity(0.12), in: .rect(cornerRadius: 13))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(text("Title")).font(localization.font(18, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(text("Subtitle")).font(localization.font(11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
            }
            .buttonStyle(MusicHomeButtonStyle(fill: .primary.opacity(0.06), corner: 10))
            .focused($focused, equals: .close)
            .overlay {
                if focused == .close { NearbyFocusOutline(corner: 10) }
            }
            .accessibilityLabel(text("Close"))
            .accessibilityIdentifier("music.home.nearby.close")
            .keyboardShortcut(.cancelAction)
        }
    }

    private var visibility: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(text("Disclosure"))
                .font(localization.font(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $enabled) {
                Text(text("Discoverability"))
                    .font(localization.font(13, weight: .semibold))
            }
            .toggleStyle(.switch)
            .tint(NearbyAppearance.accent)
            .focused($focused, equals: .visibility)
            .accessibilityHint(text("Disclosure"))
            .accessibilityIdentifier("music.home.nearby.visibility")
        }
        .padding(11)
        .background(.primary.opacity(0.045), in: .rect(cornerRadius: 13))
        .overlay {
            if focused == .visibility { NearbyFocusOutline(corner: 13) }
        }
    }

    private var stateMessage: some View {
        let title = status == .ready ? "NoDevices" : status.titleKey
        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: status.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(status.tint)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(text(title)).font(localization.font(13, weight: .semibold))
                Text(text(status.detailKey)).font(localization.font(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("music.home.nearby.status")
    }

    private func deviceList(_ devices: [NearbyDiscoveredPeer]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text("DiscoveredDevices"))
                .font(localization.font(13, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 2)

            LazyVStack(spacing: 5) {
                ForEach(devices) { peer in
                    let account = NearbyProfileArtworkService.normalizedUsername(peer.account)
                    NearbyDeviceRow(peer: peer, avatar: account.flatMap { avatars[$0] })
                }
            }
        }
        .accessibilityIdentifier("music.home.nearby.devices")
    }

    private func text(_ key: String) -> String { localization.string(key, table: "NearbyDevices") }

    private func observeController() async {
        var latch = NearbyControllerLatch()
        while !Task.isCancelled {
            if isAppActive, let controller = GCController.controllers().first(where: { $0.extendedGamepad != nil }),
               let gamepad = controller.extendedGamepad {
                let x = gamepad.dpad.xAxis.value
                let y = gamepad.dpad.yAxis.value
                let input = NearbyControllerInput(horizontal: x == 0 ? gamepad.leftThumbstick.xAxis.value : x,
                                                  vertical: y == 0 ? gamepad.leftThumbstick.yAxis.value : y,
                                                  confirm: gamepad.buttonA.isPressed, dismiss: gamepad.buttonB.isPressed)
                switch latch.consume(input, controller: ObjectIdentifier(controller)) {
                case .close:
                    close()
                    return
                case .activate:
                    if focused == .close {
                        close()
                        return
                    }
                    focused = .visibility
                    enabled.toggle()
                case .focusClose: focused = .close
                case .focusVisibility: focused = .visibility
                case nil: break
                }
            } else {
                latch = NearbyControllerLatch()
            }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
    }

    private var isAppActive: Bool {
        #if os(macOS)
        NSApp.isActive
        #else
        true
        #endif
    }
}

struct NearbyControllerInput {
    let horizontal: Float
    let vertical: Float
    let confirm: Bool
    let dismiss: Bool

    fileprivate func direction(wasActive: Bool) -> Int {
        let value = abs(vertical) >= abs(horizontal) ? -vertical : horizontal
        let threshold: Float = wasActive ? 0.43 : 0.64
        return abs(value) >= threshold ? (value > 0 ? 1 : -1) : 0
    }
}

struct NearbyControllerLatch {
    enum Action: Equatable { case close, activate, focusClose, focusVisibility }

    private var controller: ObjectIdentifier?
    private var released = false
    private var direction = 0
    private var confirm = false
    private var dismiss = false

    mutating func consume(_ input: NearbyControllerInput, controller: ObjectIdentifier) -> Action? {
        if self.controller != controller {
            self = NearbyControllerLatch()
            self.controller = controller
        }
        let next = input.direction(wasActive: direction != 0)
        defer {
            direction = next
            confirm = input.confirm
            dismiss = input.dismiss
        }
        guard released else {
            released = next == 0 && !input.confirm && !input.dismiss
            return nil
        }
        if !dismiss && input.dismiss { return .close }
        if !confirm && input.confirm { return .activate }
        if direction != next, next != 0 { return next < 0 ? .focusClose : .focusVisibility }
        return nil
    }
}

private struct NearbyDeviceRow: View {
    let peer: NearbyDiscoveredPeer
    let avatar: CGImage?
    private var localization = AuthLocalization()

    private var identity: String? {
        if let name = peer.displayName, let account = peer.account,
           name.caseInsensitiveCompare(account) != .orderedSame {
            return "\(name) · \(account)"
        }
        return peer.displayName ?? peer.account
    }

    var body: some View {
        HStack(spacing: 9) {
            badge
                .frame(width: 33, height: 33)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.deviceName)
                    .font(localization.font(13, weight: .semibold))
                    .lineLimit(2)
                Text(peer.platform.displayName)
                    .font(localization.font(10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 3)
            if let identity {
                Text(identity)
                    .font(localization.font(11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .frame(maxWidth: 118, alignment: .trailing)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(minHeight: 45)
        .background(.primary.opacity(0.045), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var badge: some View {
        if let avatar {
            WelcomeProfileBadge(avatar: avatar)
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(peer.platform.tint.opacity(0.12))
                .overlay {
                    Image(systemName: peer.platform.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(peer.platform.tint)
                }
        }
    }
}

private struct NearbyOrbit: View {
    let peers: [NearbyDiscoveredPeer]
    let scanAvailable: Bool
    let enabled: Bool
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var sweeping = false
    @State private var rotation = 0.0

    private var shouldScan: Bool { scanAvailable && !reduceMotion && scenePhase == .active }

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = max(1, min(center.x, center.y) - 16)
            ZStack {
                RadialGradient(colors: [NearbyAppearance.accent.opacity(enabled ? 0.23 : 0.11), .clear],
                               center: .center, startRadius: 6, endRadius: radius + 54)
                ForEach(0..<3, id: \.self) { ring in
                    Circle().strokeBorder(NearbyAppearance.accent.opacity(ring == 2 ? 0.24 : 0.14),
                                          style: StrokeStyle(lineWidth: 1, dash: ring == 2 ? [3, 5] : []))
                        .frame(width: radius * (1 + CGFloat(ring) * 0.5), height: radius * (1 + CGFloat(ring) * 0.5))
                        .position(center)
                }
                if sweeping {
                    Circle()
                        .fill(AngularGradient(stops: [
                            .init(color: .clear, location: 0), .init(color: .clear, location: 0.78),
                            .init(color: NearbyAppearance.accent.opacity(0.30), location: 0.995),
                            .init(color: .clear, location: 1)
                        ], center: .center))
                        .frame(width: radius * 2, height: radius * 2)
                        .rotationEffect(.degrees(rotation))
                        .position(center)
                        .transition(.opacity)
                }

                Image(systemName: NearbyAppearance.deviceSymbol)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(enabled ? tint : Color.secondary)
                    .frame(width: 42, height: 42)
                    .background(.thinMaterial, in: Circle())
                    .overlay { Circle().strokeBorder((enabled ? tint : Color.secondary).opacity(0.38)) }
                    .position(center)

                ForEach(Array(peers.enumerated()), id: \.element.id) { index, peer in
                    let angle = Double(index) * 2 * Double.pi / Double(max(6, peers.count)) - Double.pi / 3
                    let distance = radius * (index.isMultiple(of: 2) ? 1 : 0.78)
                    Image(systemName: peer.platform.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(peer.platform.tint)
                        .frame(width: 28, height: 28)
                        .background(.regularMaterial, in: Circle())
                        .overlay { Circle().strokeBorder(peer.platform.tint.opacity(0.45)) }
                        .position(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: peers.map(\.id))
        }
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.06)) }
        .clipShape(.rect(cornerRadius: 16))
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .task(id: shouldScan) {
            var immediate = Transaction()
            immediate.disablesAnimations = true
            withTransaction(immediate) {
                sweeping = shouldScan
                rotation = 0
            }
            guard shouldScan else { return }
            do {
                try await Task.sleep(for: .milliseconds(35))
                withAnimation(.linear(duration: 1.25).repeatCount(2, autoreverses: false)) {
                    rotation = 360
                }
                try await Task.sleep(for: .milliseconds(2500))
                withAnimation(.easeOut(duration: 0.18)) { sweeping = false }
            } catch { }
        }
    }
}

private struct NearbyFocusOutline: View {
    let corner: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: corner)
            .strokeBorder(NearbyAppearance.accent, lineWidth: 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private enum NearbyAppearance {
    static let accent = Color(red: 0.49, green: 0.83, blue: 0.91)

    static var deviceSymbol: String {
        #if os(macOS)
        "laptopcomputer"
        #else
        "iphone"
        #endif
    }
}

private extension NearbyDiscoveryStatus {
    var tint: Color {
        switch self {
        case .off: .secondary
        case .searching, .ready: NearbyAppearance.accent
        case .permissionDenied, .unavailable: .orange
        }
    }

    var titleKey: String {
        switch self {
        case .off: "Off"
        case .searching: "Searching"
        case .ready: "Active"
        case .permissionDenied: "PermissionDenied"
        case .unavailable: "Unavailable"
        }
    }

    var detailKey: String {
        switch self {
        case .off: "OffDetail"
        case .searching: "SearchingDetail"
        case .ready: "NoDevicesDetail"
        case .permissionDenied: "PermissionDetail"
        case .unavailable: "UnavailableDetail"
        }
    }

    var icon: String {
        switch self {
        case .off: "circle.slash"
        case .searching: "waveform.path"
        case .ready: "display"
        case .permissionDenied: "lock.shield"
        case .unavailable: "wifi.exclamationmark"
        }
    }
}

private extension NearbyPeerPlatform {
    var displayName: String {
        switch self {
        case .windows: "Windows"
        case .macOS: "macOS"
        case .iOS: "iOS"
        case .android: "Android"
        case .watchOS: "watchOS"
        case .wearOS: "Wear OS"
        }
    }

    var symbol: String {
        switch self {
        case .windows: "display"
        case .macOS: "laptopcomputer"
        case .iOS: "iphone"
        case .android: "rectangle.portrait"
        case .watchOS, .wearOS: "applewatch"
        }
    }

    var tint: Color {
        switch self {
        case .windows: .cyan
        case .macOS: .indigo
        case .iOS: .mint
        case .android: .green
        case .watchOS: .orange
        case .wearOS: .blue
        }
    }
}
#endif
