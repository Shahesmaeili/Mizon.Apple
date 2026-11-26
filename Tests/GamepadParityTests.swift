import Foundation
import MizonAppleCore
import Testing

private struct WindowsControllerContract: Decodable {
    let version: Int
    let inputCases: [InputCase]
    let feedback: [FeedbackCase]

    struct InputCase: Decodable {
        let name: String
        let frames: [Frame]
    }

    struct Frame: Decodable {
        let ms: Int64
        let buttons: [String]?
        let leftX: Double?
        let leftY: Double?
        let rightY: Double?
        let leftTrigger: Double?
        let rightTrigger: Double?
        let reset: Bool?
        let action: String?
    }

    struct FeedbackCase: Decodable {
        let kind: String
        let durationMs: Int
        let samples: [Sample]
    }

    struct Sample: Decodable {
        let time: Int
        let left: Float
        let right: Float
        let completed: Bool

        init(from decoder: Decoder) throws {
            var row = try decoder.unkeyedContainer()
            time = try row.decode(Int.self)
            left = try row.decode(Float.self)
            right = try row.decode(Float.self)
            completed = try row.decode(Bool.self)
        }
    }

    static func load() throws -> Self {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/auth-gamepad-v1.json")
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: fixture))
    }
}

struct GamepadParityTests {
    @Test func windowsContractDrivesTheProductionInputReducer() throws {
        let contract = try WindowsControllerContract.load()
        #expect(contract.version == 1)
        #expect(contract.inputCases.count == 15)
        let buttons: [String: GamepadInputReducer.Buttons] = [
            "A": .a, "B": .b, "X": .x, "Y": .y, "View": .view, "Menu": .menu,
            "Up": .up, "Down": .down, "Left": .left, "Right": .right,
            "LeftShoulder": .leftShoulder, "RightShoulder": .rightShoulder,
            "LeftThumbstick": .leftThumbstick, "RightThumbstick": .rightThumbstick
        ]
        let actions: [String: GamepadInputReducer.Action] = [
            "Back": .back, "ToggleHelp": .help, "Submit": .submit, "Accept": .accept, "Clear": .clear,
            "RevealPassword": .reveal, "PreviousSection": .previousSection, "NextSection": .nextSection,
            "PreviousField": .previousField, "NextField": .nextField, "FocusPrimary": .primary, "ResetFocus": .reset,
            "Up": .move(.up), "Down": .move(.down), "Left": .move(.left), "Right": .move(.right),
            "ScrollUp": .scroll(.up), "ScrollDown": .scroll(.down)
        ]
        for row in contract.inputCases {
            var reducer = GamepadInputReducer()
            for frame in row.frames {
                if frame.reset == true { reducer.reset() }
                var pressed: GamepadInputReducer.Buttons = []
                for button in frame.buttons ?? [] { pressed.formUnion(try #require(buttons[button])) }
                let reading = GamepadInputReducer.Reading(
                    buttons: pressed, leftX: frame.leftX ?? 0, leftY: frame.leftY ?? 0, rightY: frame.rightY ?? 0,
                    leftTrigger: frame.leftTrigger ?? 0, rightTrigger: frame.rightTrigger ?? 0)
                let expected = try frame.action.map { try #require(actions[$0]) }
                #expect(reducer.read(reading, atMilliseconds: frame.ms) == expected,
                        "Windows fixture case '\(row.name)' at \(frame.ms) ms")
            }
        }
    }

    @Test func feedbackUsesWindowsDurationsAndEnvelopes() throws {
        let feedback: [String: GamepadFeedback] = ["Success": .success, "Error": .error, "Validation": .validation]
        for fixture in try WindowsControllerContract.load().feedback {
            let effect = try #require(feedback[fixture.kind])
            #expect(effect.durationMilliseconds == fixture.durationMs)
            for sample in fixture.samples {
                let actual = effect.sample(atMilliseconds: sample.time)
                #expect(abs(actual.left - sample.left) < 0.0001)
                #expect(abs(actual.right - sample.right) < 0.0001)
                #expect(actual.completed == sample.completed)
            }
        }
    }

    @Test func keyboardRejectsIdentifierInputAndSupportsCaretAndSelection() {
        var keyboard = GamepadKeyboard(allowsPersian: false, masksValue: false, persian: true, length: 3)
        let accepts: (String) -> Bool = { AuthIdentifierInput.isAllowed($0, allowsEmail: true) }
        #expect(!keyboard.persian)
        #expect(!keyboard.isEnabled(.language))
        #expect(keyboard.edit(.character("ش"), value: "abc", accepts: accepts) == nil)
        #expect(keyboard.caret == 3)
        _ = keyboard.edit(.caretPrevious, value: "abc", accepts: accepts)
        #expect(keyboard.edit(.character("@"), value: "abc", accepts: accepts) == "ab@c")
        _ = keyboard.edit(.selectAll, value: "ab@c", accepts: accepts)
        #expect(keyboard.edit(.character("z"), value: "ab@c", accepts: accepts) == "z")
    }

    @Test func maskedEditorDisallowsCaretAndSelectionAndDeletesWholeCharacters() {
        var keyboard = GamepadKeyboard(allowsPersian: true, masksValue: true, persian: true, length: 2)
        #expect(keyboard.persian)
        #expect(!keyboard.isEnabled(.caretPrevious))
        #expect(!keyboard.isEnabled(.selectAll))
        #expect(keyboard.edit(.backspace, value: "a👨‍👩‍👧", accepts: { _ in true }) == "a")
        for _ in 0..<6 { keyboard.move(.down) }
        #expect(keyboard.isEnabled(keyboard.selectedKey))
        keyboard.resetFocus()
        #expect(keyboard.selectedKey == .character("0"))
    }

    @Test func reentryRequiresPhysicalNeutralForEachInputFamily() {
        var reducer = GamepadInputReducer()
        #expect(reducer.read(.init(buttons: [.up, .down, .menu], rightY: -0.45, leftTrigger: 0.40), atMilliseconds: 0) == nil)
        #expect(reducer.read(.init(buttons: [.down, .menu], rightY: -0.8, leftTrigger: 0.8), atMilliseconds: 400) == nil)
        #expect(reducer.read(.init(buttons: .down), atMilliseconds: 410) == nil)
        #expect(reducer.read(.init(leftX: .nan), atMilliseconds: 411) == nil)
        #expect(reducer.read(.init(buttons: .down), atMilliseconds: 412) == .move(.down))
    }
}
