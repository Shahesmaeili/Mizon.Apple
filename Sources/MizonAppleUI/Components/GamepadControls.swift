#if os(macOS) || os(iOS)
import CoreHaptics
import GameController
import MizonAppleCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

typealias GamepadAction = GamepadInputReducer.Action

extension EnvironmentValues {
    @Entry var controllerInputSuspended = false
}

@MainActor
enum GamepadControls {
    /// Each surface supplies its current ownership key. A suspended surface drops all input
    /// and a new key primes against the currently held controls before it can act.
    static func observe<Scope: Equatable>(
        scope: () -> Scope?,
        onReset: () -> Void = {},
        perform: (GamepadAction, GamepadFeedbackPlayer) -> Void
    ) async {
        let clock = ContinuousClock()
        let start = clock.now
        var session = GamepadInputSession<ObjectIdentifier, Scope>()
        var owner: GCController?
        let feedback = GamepadFeedbackPlayer()
        defer {
            feedback.detach(finishingSuccess: true)
            onReset()
        }
        while !Task.isCancelled {
            let scope = scope()
            let connected = scope == nil ? [] : GCController.controllers()
            let controller = owner.flatMap { selected in connected.first { $0 === selected } }
                ?? connected.first { $0.extendedGamepad != nil }
            if controller !== owner {
                owner = controller
                feedback.attach(controller)
                onReset()
            }
            let elapsed = start.duration(to: clock.now).components
            let time = elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000
            let sample = (controller?.extendedGamepad).map(read)
            if let action = session.read(sample, controller: controller.map(ObjectIdentifier.init),
                                         surface: scope, atMilliseconds: time) {
                perform(action, feedback)
            }
            do { try await Task.sleep(for: controller == nil ? .milliseconds(250) : .milliseconds(20)) }
            catch { return }
        }
    }

    static func observe(when enabled: () -> Bool, perform: (GamepadAction) -> Void) async {
        await observe(scope: { enabled() ? true : nil }) { action, _ in perform(action) }
    }

    private static func read(_ pad: GCExtendedGamepad) -> GamepadInputReducer.Reading {
        var buttons: GamepadInputReducer.Buttons = []
        if pad.dpad.up.isPressed { buttons.insert(.up) }
        if pad.dpad.down.isPressed { buttons.insert(.down) }
        if pad.dpad.left.isPressed { buttons.insert(.left) }
        if pad.dpad.right.isPressed { buttons.insert(.right) }
        if pad.buttonA.isPressed { buttons.insert(.a) }
        if pad.buttonB.isPressed { buttons.insert(.b) }
        if pad.buttonX.isPressed { buttons.insert(.x) }
        if pad.buttonY.isPressed { buttons.insert(.y) }
        if pad.buttonOptions?.isPressed == true { buttons.insert(.view) }
        if pad.buttonMenu.isPressed { buttons.insert(.menu) }
        if pad.leftShoulder.isPressed { buttons.insert(.leftShoulder) }
        if pad.rightShoulder.isPressed { buttons.insert(.rightShoulder) }
        if pad.leftThumbstickButton?.isPressed == true { buttons.insert(.leftThumbstick) }
        if pad.rightThumbstickButton?.isPressed == true { buttons.insert(.rightThumbstick) }
        return .init(buttons: buttons,
                     leftX: Double(pad.leftThumbstick.xAxis.value), leftY: Double(pad.leftThumbstick.yAxis.value),
                     rightY: Double(pad.rightThumbstick.yAxis.value),
                     leftTrigger: Double(pad.leftTrigger.value), rightTrigger: Double(pad.rightTrigger.value))
    }
}

@MainActor
@Observable
final class GamepadScroll {
    var position = ScrollPosition(edge: .top)
    @ObservationIgnored private var offset: CGFloat = 0

    func move(by step: CGFloat) {
        position.scrollTo(y: max(0, offset + step))
    }

    struct Binding: ViewModifier {
        @Bindable var scroll: GamepadScroll

        func body(content: Content) -> some View {
            content
                .scrollPosition($scroll.position)
                .onScrollGeometryChange(for: CGFloat.self) {
                    $0.contentOffset.y + $0.contentInsets.top
                } action: { _, offset in
                    scroll.offset = offset
                }
        }
    }
}

extension View {
    func gamepadScrolling(_ scroll: GamepadScroll) -> some View {
        modifier(GamepadScroll.Binding(scroll: scroll))
    }
}

extension GamepadAction {
    /// Logical order for lists and form fields. Grid surfaces can use the physical direction directly.
    var focusStep: Int? {
        switch self {
        case .move(.left), .move(.up), .previousField, .previousSection: -1
        case .move(.right), .move(.down), .nextField, .nextSection: 1
        default: nil
        }
    }

    var scrollStep: CGFloat? {
        switch self {
        case .scroll(.up): -120
        case .scroll(.down): 120
        default: nil
        }
    }
}

extension Array where Element: Equatable {
    func gamepadTarget(from current: Element?, step: Int) -> Element? {
        guard let current, let index = firstIndex(of: current) else { return first }
        return self[Swift.min(count - 1, Swift.max(0, index + step))]
    }
}

@MainActor
final class GamepadFeedbackPlayer {
    private weak var controller: GCController?
    private(set) var generation = 0
    private var playing: [CHHapticEngine] = []
    private var successDeadline: ContinuousClock.Instant?

    func attach(_ controller: GCController?) {
        detach()
        self.controller = controller
    }

    func detach(finishingSuccess: Bool = false) {
        generation += 1
        let previousController = controller
        controller = nil
        let clock = ContinuousClock()
        if finishingSuccess, let deadline = successDeadline, clock.now < deadline,
           let previousController, Self.active, !playing.isEmpty {
            // Keep the last two pulses together when a successful form immediately opens Welcome.
            let engines = playing
            playing.removeAll()
            Task { @MainActor [weak previousController] in
                while clock.now < deadline, Self.active, let previousController,
                      GCController.controllers().contains(where: { $0 === previousController }) {
                    try? await clock.sleep(until: min(deadline, clock.now.advanced(by: .milliseconds(20))))
                }
                for engine in engines { engine.stop(completionHandler: nil) }
            }
        }
        stop()
    }

    private static var active: Bool {
        #if os(macOS)
        NSApplication.shared.isActive
        #else
        UIApplication.shared.applicationState == .active
        #endif
    }

    func play(_ feedback: GamepadFeedback, generation expected: Int? = nil) {
        guard Self.active, expected == nil || expected == generation,
              let controller, GCController.controllers().contains(where: { $0 === controller }),
              let haptics = controller.haptics else { return }
        stop()
        let localities = haptics.supportedLocalities
        if localities.contains(.leftHandle), localities.contains(.rightHandle) {
            play(feedback, haptics: haptics, locality: .leftHandle, intensity: \.left)
            play(feedback, haptics: haptics, locality: .rightHandle, intensity: \.right)
        } else {
            play(feedback, haptics: haptics, locality: .default) { max($0.left, $0.right) }
        }
        if feedback == .success, !playing.isEmpty {
            successDeadline = ContinuousClock().now.advanced(by: .milliseconds(feedback.durationMilliseconds))
        }
    }

    private func stop() {
        successDeadline = nil
        for engine in playing { engine.stop(completionHandler: nil) }
        playing.removeAll()
    }

    private func play(_ feedback: GamepadFeedback, haptics: GCDeviceHaptics, locality: GCHapticsLocality,
                      intensity: (GamepadFeedback.Pulse) -> Float) {
        let pulses = feedback.pulses.filter { intensity($0) > 0 }
        guard !pulses.isEmpty, let engine = haptics.createEngine(withLocality: locality) else { return }
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        let events = pulses.map { pulse in
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity(pulse))
            ], relativeTime: pulse.start, duration: pulse.duration)
        }
        let controls = pulses.flatMap { pulse in
            let ramp = feedback.envelope
            return ramp.map { (pulse.start + $0.time, $0.value) }
                + ramp.reversed().map { (pulse.start + pulse.duration - $0.time, $0.value) }
        }
        let curve = CHHapticParameterCurve(parameterID: .hapticIntensityControl,
                                         controlPoints: controls.map { .init(relativeTime: $0.0, value: $0.1) },
                                         relativeTime: 0)
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: [curve])
            try engine.start()
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
            playing.append(engine)
        } catch {
            engine.stop(completionHandler: nil)
        }
    }
}
#endif
