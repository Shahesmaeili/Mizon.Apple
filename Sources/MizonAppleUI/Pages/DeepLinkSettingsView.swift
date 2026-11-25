#if os(macOS) || os(iOS)
import GameController
import MizonAppleCore
import SwiftUI
import UserNotifications
#if os(iOS)
import UIKit
#endif

struct DeepLinkSettingsView: View {
    private typealias Section = MizonDeepLink.SettingsSection

    private enum Control: Hashable {
        case close, section(Section), server, language(String), notificationSettings, menuBar
    }

    let model: LoginViewModel
    let onOpen: () -> Void
    @State private var selection: Section
    @State private var reportedOpen = false
    @State private var showsServerSettings = false
    @State private var notificationStatus: UNAuthorizationStatus?
    @FocusState private var focused: Control?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    #if os(macOS)
    @AppStorage(MacMenuBarProfile.preferenceKey) private var showsMenuBarProfile = true
    @Environment(\.appearsActive) private var appearsActive
    #endif
    private var localization = AuthLocalization()

    init(model: LoginViewModel, section: MizonDeepLink.SettingsSection?, onOpen: @escaping () -> Void) {
        self.model = model
        self.onOpen = onOpen
        _selection = State(initialValue: section ?? .account)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.horizontal, 20)
            GeometryReader { geometry in
                if geometry.size.width >= 620 {
                    HStack(spacing: 0) {
                        sectionPicker(compact: false)
                            .frame(width: 195)
                        Divider()
                        details
                    }
                } else {
                    VStack(spacing: 0) {
                        sectionPicker(compact: true)
                        Divider()
                        details
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 680, minHeight: 320, idealHeight: 475)
        #endif
        .foregroundStyle(MizonPalette.ink)
        .background { WindowGlass().ignoresSafeArea() }
        .preferredColorScheme(.dark)
        .environment(\.layoutDirection, localization.isPersian ? .rightToLeft : .leftToRight)
        .accessibilityIdentifier("deeplink.settings")
        .sheet(isPresented: $showsServerSettings) {
            ScrollView { ServerSettingsView(model: model) }
        }
        .onAppear {
            guard !reportedOpen else { return }
            reportedOpen = true
            onOpen()
        }
        .task(id: readsNotifications) {
            guard readsNotifications, Bundle.main.bundleIdentifier != nil else { return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if !Task.isCancelled { notificationStatus = settings.authorizationStatus }
        }
        .task(id: pollsController) {
            if pollsController { await observeController() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape")
                .foregroundStyle(MizonPalette.accent)
                .accessibilityHidden(true)
            Text(text("SettingsTitle"))
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { activate(.close) } label: {
                Image(systemName: "xmark")
                    .frame(minWidth: 24, minHeight: 24)
            }
            .buttonStyle(.glass)
            .focused($focused, equals: .close)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(text("Close"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func sectionPicker(compact: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView(compact ? .horizontal : .vertical) {
                if compact {
                    HStack(spacing: 6) {
                        sectionButtons(compact: true)
                    }
                } else {
                    VStack(spacing: 4) {
                        sectionButtons(compact: false)
                    }
                }
            }
            .contentMargins(compact ? .horizontal : .vertical, 12, for: .scrollContent)
            .contentMargins(compact ? .vertical : .horizontal, 8, for: .scrollContent)
            .onChange(of: selection, initial: true) { _, section in
                proxy.scrollTo(section, anchor: .center)
            }
            .onChange(of: focused) { _, target in
                if case .section(let section) = target { proxy.scrollTo(section, anchor: .center) }
            }
        }
    }

    private func sectionButtons(compact: Bool) -> some View {
        ForEach(Section.allCases, id: \.self) { section in
            let target = Control.section(section)
            Button { activate(target) } label: {
                Label(text(section.rawValue), systemImage: icon(section))
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 12)
                    .frame(maxWidth: compact ? nil : .infinity, minHeight: 38, alignment: .leading)
                    .background(selection == section ? MizonPalette.accent.opacity(0.15) : .clear,
                                in: .rect(cornerRadius: 9))
                    .overlay {
                        if focused == target {
                            RoundedRectangle(cornerRadius: 9).strokeBorder(MizonPalette.accent, lineWidth: 2)
                        }
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .focused($focused, equals: target)
            .accessibilityAddTraits(selection == section ? .isSelected : [])
            .accessibilityIdentifier("deeplink.settings.section.\(section.rawValue)")
            .id(section)
        }
    }

    private var details: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    Text(text(selection.rawValue))
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                        .id("section-title")
                    sectionDetails
                }
                .padding(20)
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: selection) {
                proxy.scrollTo("section-title", anchor: .top)
            }
            .onChange(of: focused) { _, target in
                if let target { proxy.scrollTo(target, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private var sectionDetails: some View {
        switch selection {
        case .account:
            if let session = model.session {
                value("SignedInAs", session.identifier)
                value("ConnectedServer", session.server.absoluteString)
            }
            action(localization.string("ServerSettings", table: "Settings"), symbol: "server.rack", target: .server)
        case .security:
            note("Keychain")
        case .language:
            languageButton("en", key: "GamepadKeyboardLanguageEnglish")
            languageButton("fa", key: "GamepadKeyboardLanguagePersian")
        case .appearance:
            value("CurrentTheme", text("DarkAppearance"))
            value("ReduceMotion", text(reduceMotion ? "Enabled" : "Disabled"))
            value("ReduceTransparency", text(reduceTransparency ? "Enabled" : "Disabled"))
        case .notifications:
            value("NotificationPermission", text(notificationPermissionKey))
            #if os(iOS)
            if canOpenNotificationSettings {
                action(text("NotificationSettings"), symbol: "arrow.up.right", target: .notificationSettings)
            }
            #endif
        case .storage:
            note("StorageDetail")
        case .updates:
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                value("AppVersion", version)
            }
            if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                value("AppBuild", build)
            }
            note("UpdatesDetail")
        case .platforms:
            #if os(macOS)
            value("Platform", "macOS")
            let label = localization.string("ShowMenuBarProfile", table: "MenuBarProfile")
            let state = text(showsMenuBarProfile ? "Enabled" : "Disabled")
            action(label, symbol: showsMenuBarProfile ? "checkmark.circle.fill" : "circle", target: .menuBar)
                .accessibilityValue(state)
            #else
            value("Platform", "iOS")
            #endif
        case .aiConnections:
            note("AIConnectionsUnavailable")
        }
    }

    private func value(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text(key)).font(.subheadline.weight(.medium))
            Text(value)
                .foregroundStyle(MizonPalette.secondaryText)
                .font(.callout)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    private func note(_ key: String) -> some View {
        Text(text(key))
            .foregroundStyle(MizonPalette.secondaryText)
            .font(.callout)
    }

    private func languageButton(_ code: String, key: String) -> some View {
        let selected = (code == "fa") == localization.isPersian
        return action(localization[key], symbol: selected ? "checkmark.circle.fill" : "circle",
                      target: .language(code))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func action(_ title: String, symbol: String, target: Control) -> some View {
        Button { activate(target) } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        }
        .buttonStyle(.glass)
        .focused($focused, equals: target)
        .id(target)
    }

    private func activate(_ target: Control) {
        switch target {
        case .close:
            dismiss()
        case .section(let section):
            selection = section
        case .language(let language):
            localization.language = language
            AccessibilityNotification.Announcement(
                AuthLocalization.string("LanguageChangedAnnouncement", table: "Auth", language: language)
            ).post()
        case .server:
            showsServerSettings = true
        case .notificationSettings:
            #if os(iOS)
            if canOpenNotificationSettings, let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                openURL(url)
            }
            #endif
        case .menuBar:
            #if os(macOS)
            showsMenuBarProfile.toggle()
            MacMenuBarProfile.shared.setEnabled(showsMenuBarProfile)
            #endif
        }
    }

    private var notificationPermissionKey: String {
        switch notificationStatus {
        case .authorized: "NotificationAuthorized"
        case .denied: "NotificationDenied"
        case .provisional: "NotificationProvisional"
        case .ephemeral: "NotificationTemporary"
        case .notDetermined: "NotificationUndecided"
        case nil: "NotificationUnavailable"
        @unknown default: "NotificationUnavailable"
        }
    }

    private var canOpenNotificationSettings: Bool {
        notificationStatus != nil && notificationStatus != .notDetermined
    }

    private var readsNotifications: Bool { scenePhase == .active && selection == .notifications }

    private var pollsController: Bool {
        guard scenePhase == .active, !showsServerSettings else { return false }
        #if os(macOS)
        return appearsActive
        #else
        return true
        #endif
    }

    private var controls: [Control] {
        let sections = Section.allCases.map(Control.section)
        switch selection {
        case .account: return [.close] + sections + [.server]
        case .language: return [.close] + sections + [.language("en"), .language("fa")]
        #if os(iOS)
        case .notifications where canOpenNotificationSettings: return [.close] + sections + [.notificationSettings]
        #endif
        #if os(macOS)
        case .platforms: return [.close] + sections + [.menuBar]
        #endif
        default: return [.close] + sections
        }
    }

    private func observeController() async {
        var latch = NearbyControllerLatch()
        while !Task.isCancelled {
            if let controller = GCController.controllers().first(where: { $0.extendedGamepad != nil }),
               let gamepad = controller.extendedGamepad {
                let x = gamepad.dpad.xAxis.value
                let y = gamepad.dpad.yAxis.value
                let horizontal = x == 0 ? gamepad.leftThumbstick.xAxis.value : x
                let input = NearbyControllerInput(horizontal: localization.isPersian ? -horizontal : horizontal,
                                                  vertical: y == 0 ? gamepad.leftThumbstick.yAxis.value : y,
                                                  confirm: gamepad.buttonA.isPressed, dismiss: gamepad.buttonB.isPressed)
                switch latch.consume(input, controller: ObjectIdentifier(controller)) {
                case .close: activate(.close)
                case .activate: activate(focused ?? .section(selection))
                case .focusClose: moveFocus(by: -1)
                case .focusVisibility: moveFocus(by: 1)
                case nil: break
                }
            } else {
                latch = NearbyControllerLatch()
            }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
    }

    private func moveFocus(by offset: Int) {
        let available = controls
        let index = available.firstIndex(of: focused ?? .section(selection)) ?? 0
        focused = available[min(max(0, index + offset), available.count - 1)]
    }

    private func icon(_ section: Section) -> String {
        switch section {
        case .account: "person.crop.circle"
        case .security: "lock.shield"
        case .language: "globe"
        case .appearance: "circle.lefthalf.filled"
        case .notifications: "bell"
        case .storage: "internaldrive"
        case .updates: "arrow.triangle.2.circlepath"
        case .platforms: "laptopcomputer.and.iphone"
        case .aiConnections: "link"
        }
    }

    private func text(_ key: String) -> String { localization.string(key, table: "DeepLinkSettings") }
}
#endif
