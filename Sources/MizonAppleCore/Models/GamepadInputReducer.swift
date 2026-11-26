public struct GamepadInputReducer: Sendable {
    public struct Buttons: OptionSet, Sendable {
        public let rawValue: UInt16

        public init(rawValue: UInt16) { self.rawValue = rawValue }

        public static let up = Self(rawValue: 1 << 0)
        public static let down = Self(rawValue: 1 << 1)
        public static let left = Self(rawValue: 1 << 2)
        public static let right = Self(rawValue: 1 << 3)
        public static let a = Self(rawValue: 1 << 4)
        public static let b = Self(rawValue: 1 << 5)
        public static let x = Self(rawValue: 1 << 6)
        public static let y = Self(rawValue: 1 << 7)
        public static let view = Self(rawValue: 1 << 8)
        public static let menu = Self(rawValue: 1 << 9)
        public static let leftShoulder = Self(rawValue: 1 << 10)
        public static let rightShoulder = Self(rawValue: 1 << 11)
        public static let leftThumbstick = Self(rawValue: 1 << 12)
        public static let rightThumbstick = Self(rawValue: 1 << 13)
        fileprivate static let direction: Self = [.up, .down, .left, .right]
    }

    public struct Reading: Sendable {
        var buttons: Buttons
        var leftX: Double
        var leftY: Double
        var rightY: Double
        var leftTrigger: Double
        var rightTrigger: Double

        public init(buttons: Buttons = [], leftX: Double = 0, leftY: Double = 0, rightY: Double = 0,
                    leftTrigger: Double = 0, rightTrigger: Double = 0) {
            self.buttons = buttons
            self.leftX = leftX.isFinite ? leftX : 0
            self.leftY = leftY.isFinite ? leftY : 0
            self.rightY = rightY.isFinite ? rightY : 0
            self.leftTrigger = leftTrigger.isFinite ? leftTrigger : 0
            self.rightTrigger = rightTrigger.isFinite ? rightTrigger : 0
        }
    }

    public enum Direction: Sendable, Equatable {
        case up, down, left, right
    }

    public enum Action: Sendable, Equatable {
        case back, help, submit, accept, clear, reveal
        case previousSection, nextSection, previousField, nextField, primary, reset
        case move(Direction), scroll(Direction)
    }

    private struct Repeater: Sendable {
        var previous: Direction?
        var blocked = false
        var nextAt: Int64?

        mutating func take(_ direction: Direction?, at time: Int64) -> Direction? {
            guard let direction, !blocked else {
                previous = direction
                nextAt = nil
                return nil
            }
            if previous != direction || nextAt == nil {
                previous = direction
                nextAt = time + 360
                return direction
            }
            guard let nextAt, time >= nextAt else { return nil }
            self.nextAt = time + 110
            return direction
        }
    }

    private static let press = 0.55
    private static let release = 0.35
    private static let axisSwitchMargin = 0.18
    private static let buttonActions: [(Buttons, Action)] = [
        (.b, .back), (.view, .help), (.menu, .submit), (.a, .accept), (.x, .clear), (.y, .reveal),
        (.leftShoulder, .previousSection), (.rightShoulder, .nextSection)
    ]

    private var previousButtons: Buttons?
    private var leftTrigger = false
    private var rightTrigger = false
    private var stick: Direction?
    private var navigation = Repeater()
    private var scrolling = Repeater()

    public init() {}

    public mutating func reset() { self = Self() }

    public mutating func read(_ reading: Reading, atMilliseconds time: Int64) -> Action? {
        let buttons = reading.buttons
        let directions = buttons.intersection(.direction)
        let navigationNeutral = directions.isEmpty && abs(reading.leftX) <= Self.release && abs(reading.leftY) <= Self.release
        let scrollNeutral = abs(reading.rightY) <= Self.release
        stick = stickDirection(x: reading.leftX, y: reading.leftY)
        let direction = navigationDirection(directions)
        let vertical: Direction = reading.rightY < 0 ? .down : .up
        let scroll = abs(reading.rightY) >= (scrolling.previous == vertical ? Self.release : Self.press) ? vertical : nil
        defer { previousButtons = buttons }

        guard let previousButtons else {
            leftTrigger = reading.leftTrigger > Self.release
            rightTrigger = reading.rightTrigger > Self.release
            navigation = Repeater(previous: direction, blocked: !navigationNeutral)
            scrolling = Repeater(previous: scroll, blocked: !scrollNeutral)
            return nil
        }

        let leftHeld = reading.leftTrigger >= (leftTrigger ? Self.release : 0.65)
        let rightHeld = reading.rightTrigger >= (rightTrigger ? Self.release : 0.65)
        let leftPressed = leftHeld && !leftTrigger
        let rightPressed = rightHeld && !rightTrigger
        leftTrigger = leftHeld
        rightTrigger = rightHeld
        if navigationNeutral { navigation.blocked = false }
        if scrollNeutral { scrolling.blocked = false }
        let moveDue = navigation.take(direction, at: time)
        let scrollDue = scrolling.take(scroll, at: time)

        // Consume all edges and both clocks even when a higher priority command wins.
        let pressed = buttons.subtracting(previousButtons)
        if let button = Self.buttonActions.first(where: { pressed.contains($0.0) }) { return button.1 }
        if leftPressed { return .previousField }
        if rightPressed { return .nextField }
        if pressed.contains(.leftThumbstick) { return .primary }
        if pressed.contains(.rightThumbstick) { return .reset }
        if let moveDue { return .move(moveDue) }
        if let scrollDue { return .scroll(scrollDue) }
        return nil
    }

    private func stickDirection(x: Double, y: Double) -> Direction? {
        let ax = abs(x), ay = abs(y)
        let horizontal: Direction = x < 0 ? .left : .right
        let vertical: Direction = y < 0 ? .down : .up
        if stick == horizontal, ax > Self.release, !(ay >= Self.press && ay > ax + Self.axisSwitchMargin) {
            return horizontal
        }
        if stick == vertical, ay > Self.release, !(ax >= Self.press && ax > ay + Self.axisSwitchMargin) {
            return vertical
        }
        guard max(ax, ay) >= Self.press else { return nil }
        return ay >= ax ? vertical : horizontal
    }

    private func navigationDirection(_ directions: Buttons) -> Direction? {
        guard !directions.isEmpty else { return stick }
        let up = directions.contains(.up), down = directions.contains(.down)
        let left = directions.contains(.left), right = directions.contains(.right)
        let vertical: Direction? = up == down ? nil : up ? .up : .down
        let horizontal: Direction? = left == right ? nil : left ? .left : .right
        if let previous = navigation.previous, previous == vertical || previous == horizontal { return previous }
        return vertical ?? horizontal
    }
}

public enum GamepadFeedback: Sendable {
    case success, error, validation

    public struct Pulse: Sendable {
        public let start: Double
        public let duration: Double
        public let left: Float
        public let right: Float
    }

    public var pulses: [Pulse] {
        switch self {
        case .success: [
            Pulse(start: 0, duration: 0.09, left: 0.08, right: 0.18),
            Pulse(start: 0.14, duration: 0.12, left: 0.14, right: 0.28)
        ]
        case .error: [
            Pulse(start: 0, duration: 0.14, left: 0.38, right: 0.18),
            Pulse(start: 0.22, duration: 0.14, left: 0.38, right: 0.18)
        ]
        case .validation: [Pulse(start: 0, duration: 0.10, left: 0, right: 0.16)]
        }
    }

    public var durationMilliseconds: Int {
        guard let last = pulses.last else { return 0 }
        return Int(((last.start + last.duration) * 1_000).rounded())
    }

    public func sample(atMilliseconds time: Int) -> (left: Float, right: Float, completed: Bool) {
        if time >= durationMilliseconds { return (0, 0, true) }
        let position = Double(time) / 1_000
        for pulse in pulses {
            let elapsed = position - pulse.start
            guard elapsed > 0, elapsed < pulse.duration else { continue }
            let amount = Float(min(1, min(elapsed, pulse.duration - elapsed) / 0.025))
            let gain = amount * amount * (3 - 2 * amount)
            return (pulse.left * gain, pulse.right * gain, false)
        }
        return (0, 0, false)
    }

    public var envelope: [(time: Double, value: Float)] {
        [(0, 0), (0.00625, 0.15625), (0.0125, 0.5), (0.01875, 0.84375), (0.025, 1)]
    }
}
