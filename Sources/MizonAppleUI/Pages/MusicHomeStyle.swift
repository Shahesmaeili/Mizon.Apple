#if os(macOS) || os(iOS)
import SwiftUI

enum MusicHomeStyle {
    static let card = Color.white.opacity(0.0605)
    static let secondaryCard = Color.white.opacity(0.0326)
    static let stroke = Color.black.opacity(0.10)
    static let inset = Color.white.opacity(11.0 / 255)
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.786)
    static let tertiary = Color.white.opacity(0.544)
    static let cyan = musicColor("8BCBE2")
    static let gold = musicColor("F1C27D")

    static func duration(seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "–:––" }
        let count = Int(seconds)
        if count >= 3600 {
            return String(format: "%d:%02d:%02d", count / 3600, (count / 60) % 60, count % 60)
        }
        return String(format: "%d:%02d", count / 60, count % 60)
    }
}

struct MusicHomeButtonStyle: ButtonStyle {
    var fill: Color = .clear
    var stroke: Color = .clear
    var corner: CGFloat = 7

    func makeBody(configuration: Configuration) -> some View {
        Surface(label: configuration.label, pressed: configuration.isPressed, fill: fill, stroke: stroke, corner: corner)
    }

    private struct Surface<Label: View>: View {
        let label: Label
        let pressed: Bool
        let fill: Color
        let stroke: Color
        let corner: CGFloat
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            label
                .background(fill, in: .rect(cornerRadius: corner))
                .overlay {
                    RoundedRectangle(cornerRadius: corner)
                        .fill(.white.opacity(enabled ? (pressed ? 0.11 : hovering ? 0.065 : 0) : 0))
                        .allowsHitTesting(false)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: corner).strokeBorder(stroke)
                        .allowsHitTesting(false)
                }
                .contentShape(.rect(cornerRadius: corner))
                .opacity(enabled ? 1 : 0.44)
                .authHandPointer(enabled: enabled)
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovering)
        }
    }
}

struct MusicHomeSkeleton: View {
    let height: CGFloat
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    var body: some View {
        let canAnimate = visible && !reduceMotion && scenePhase == .active
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !canAnimate)) { time in
            let phase = canAnimate ? time.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.65) / 1.65 : 0
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 5).frame(width: 108, height: 10)
                RoundedRectangle(cornerRadius: 8).frame(maxWidth: .infinity, maxHeight: .infinity)
                RoundedRectangle(cornerRadius: 4).frame(width: 145, height: 7)
            }
            .foregroundStyle(.white.opacity(22.0 / 255))
            .overlay {
                if canAnimate {
                    GeometryReader { size in
                        let band = size.size.width * 0.48
                        LinearGradient(colors: [.clear, .white.opacity(0.045), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: band)
                            .offset(x: (size.size.width + band) * phase - band)
                    }
                    .clipped()
                }
            }
        }
        .padding(18)
        .frame(height: height)
        .background(MusicHomeStyle.secondaryCard, in: .rect(cornerRadius: 12))
        .onScrollVisibilityChange { visible = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}
#endif
