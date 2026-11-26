#if os(macOS) || os(iOS)
import MizonAPI
import MizonAPIClient
import MizonAppleCore
import SwiftUI

struct MusicTrackWaveform: View {
    let bars: [TrackWaveformBar]
    let comments: [MusicCommentItemResponse]
    let listeners: [MusicListenerPresence]
    let duration: Double
    let position: Double
    let playing: Bool
    let music: MusicHomeViewModel
    let seek: (Double) -> Void
    let addComment: (Double) -> Void
    let openComment: (MusicCommentItemResponse) -> Void

    private let timelineWidth: CGFloat = 1_500
    @State private var hover: CGPoint?
    @State private var scroll = ScrollPosition(edge: .leading)
    @State private var manuallyScrolling = false
    @State private var viewportWidth: CGFloat = 0
    @State private var viewportOffset: CGFloat = 0
    @State private var pinnedComment: MusicCommentItemResponse?
    private let localization = AuthLocalization()
    private var progress: CGFloat { duration > 0 ? min(1, max(0, position / duration)) : 0 }

    var body: some View {
        ScrollView(.horizontal) {
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let step = size.width / Double(max(1, TrackWaveformBar.count))
                    let baseline: CGFloat = 73
                    let crossing = Int(progress * CGFloat(TrackWaveformBar.count))
                    let topHover = hover.flatMap { $0.y < baseline ? Int($0.x / step) : nil } ?? -1
                    let bottomHover = hover.flatMap { $0.y >= baseline ? Int($0.x / step) : nil } ?? -1
                    var quiet = Path(), played = Path(), hot = Path(), reflections = Path(), selected = Path()
                    if bars.isEmpty {
                        for index in 0..<TrackWaveformBar.count {
                            let height = Double(9 + ((index * 37 + index % 7 * 9) % 28))
                            quiet.addRoundedRect(in: CGRect(x: Double(index) * step + 2, y: baseline - height,
                                                          width: 2, height: height), cornerSize: CGSize(width: 1, height: 1))
                        }
                    }
                    for (index, bar) in bars.enumerated() {
                        let x = Double(index) * step + 2
                        let upper = CGRect(x: x, y: baseline - CGFloat(bar.top), width: 2, height: CGFloat(bar.top))
                        let lower = CGRect(x: x, y: baseline + 6, width: 2, height: CGFloat(bar.bottom))
                        let radius = CGSize(width: 1, height: 1)
                        if topHover >= index { hot.addRoundedRect(in: upper, cornerSize: radius) }
                        else if index < crossing { played.addRoundedRect(in: upper, cornerSize: radius) }
                        else { quiet.addRoundedRect(in: upper, cornerSize: radius) }
                        if bottomHover == index { selected.addRoundedRect(in: lower, cornerSize: radius) }
                        else { reflections.addRoundedRect(in: lower, cornerSize: radius) }
                    }
                    context.fill(quiet, with: .color(.white.opacity(bars.isEmpty ? 0.19 : 120.0 / 255)))
                    context.fill(reflections, with: .color(.white.opacity(50.0 / 255)))
                    context.fill(played, with: .color(playing ? musicColor("00B4FF") : musicColor("E6FF0D").opacity(180.0 / 255)))
                    context.fill(hot, with: .color(musicColor("1E90FF").opacity(180.0 / 255)))
                    context.fill(selected, with: .color(musicColor("FF4D6D").opacity(220.0 / 255)))
                    if duration > 0 {
                        for (start, length, color) in [(20.0, 320.0, "FF4D6D"), (370, 290, "00B4FF"),
                                                       (630, 120, "FFC107"), (1_010, 420, "9C27B0")] {
                            let segment = CGRect(x: start, y: baseline + 2, width: length, height: 2)
                            context.fill(Path(roundedRect: segment, cornerRadius: 1), with: .color(musicColor(color).opacity(0.8)))
                        }
                    }
                }
                .frame(width: timelineWidth, height: 110)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                VStack(spacing: 0) {
                    Color.clear.frame(height: 73).contentShape(.rect)
                        .gesture(SpatialTapGesture().onEnded { seek(seconds(at: $0.location.x)) })
                    Color.clear.frame(height: 37).contentShape(.rect)
                        .gesture(SpatialTapGesture().onEnded { addComment(seconds(at: $0.location.x)) })
                }
                .frame(width: timelineWidth)
                .onContinuousHover { phase in
                    if case .active(let point) = phase { hover = point }
                    else { hover = nil }
                }
                .accessibilityElement()
                .accessibilityLabel(text("Waveform"))
                .accessibilityHint(text("WaveformControls"))
                .accessibilityValue(MusicTrackDetailsView.time(position))
                .accessibilityAdjustableAction { change in
                    if change == .increment { seek(min(duration, position + 5)) }
                    if change == .decrement { seek(max(0, position - 5)) }
                }
                .accessibilityAction(named: Text(text("CommentNew"))) { addComment(position) }
                .authHandPointer(enabled: duration > 0)

                if duration > 0 {
                    ForEach(listeners.prefix(100), id: \.clientPublicId) { listener in
                        let label = [listener.firstName, listener.lastName].filter { !$0.isEmpty }.joined(separator: " ")
                        MusicArtwork(mediaID: listener.profileMediaPublicId, model: music, symbol: "person.fill")
                            .frame(width: 20, height: 20)
                            .clipShape(.circle)
                            .overlay(Circle().strokeBorder(listener.isPlaying ? musicColor("00B4FF") : MizonPalette.accent, lineWidth: 1))
                            .opacity(0.8)
                            .position(x: min(timelineWidth - 10, max(10, Double(listener.positionMilliseconds) / 1_000 / duration * timelineWidth)),
                                      y: 65)
                            .accessibilityLabel(label.isEmpty ? text("AudienceListener") : label)
                            .allowsHitTesting(false)
                    }
                    ForEach(comments.prefix(100), id: \.publicId) { comment in
                        if let time = comment.timestamp?.totalSeconds, time.isFinite, time >= 0, time <= duration {
                            Button {
                                pinnedComment = comment
                            } label: {
                                MusicArtwork(mediaID: comment.profileMediaPublicId, model: music, symbol: "person.fill")
                                    .frame(width: 24, height: 24).clipShape(.circle)
                                    .padding(2)
                                    .overlay(Circle().strokeBorder(comment.clientPublicId == music.session.clientPublicId
                                                                   ? MizonPalette.accent.opacity(0.45) : .white.opacity(0.34)))
                            }
                            .buttonStyle(.plain)
                            .position(x: min(timelineWidth - 14, max(14, time / duration * timelineWidth)), y: 91)
                            .accessibilityLabel(MusicReferenceRailFormat.substitute(text("CommentBy"),
                                                        with: [comment.firstName, comment.text]))
                            .popover(isPresented: Binding(get: { pinnedComment?.publicId == comment.publicId },
                                                          set: { if !$0 { pinnedComment = nil } })) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(comment.text).font(localization.font(13)).lineLimit(6)
                                    Button(text("OpenWaveformCommentInList")) {
                                        pinnedComment = nil
                                        openComment(comment)
                                    }.buttonStyle(.glass)
                                }
                                .padding(12).frame(idealWidth: 240, maxWidth: 280)
                                .presentationCompactAdaptation(.popover)
                            }
                        }
                    }
                }
            }
            .frame(width: timelineWidth, height: 110)
        }
        .environment(\.layoutDirection, .leftToRight)
        .scrollIndicators(.hidden)
        .scrollPosition($scroll)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, offset in viewportOffset = offset }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
        .onScrollPhaseChange { _, phase in manuallyScrolling = phase == .tracking || phase == .interacting || phase == .decelerating }
        .onChange(of: Int(progress * 250)) {
            let playhead = progress * timelineWidth
            guard playing, !manuallyScrolling, viewportWidth > 0 else { return }
            if playhead > viewportOffset + viewportWidth * 0.72 || playhead < viewportOffset {
                scroll.scrollTo(x: min(max(0, playhead - viewportWidth * 0.30), max(0, timelineWidth - viewportWidth)))
            }
        }
    }

    private func seconds(at x: CGFloat) -> Double { min(1, max(0, x / timelineWidth)) * duration }
    private func text(_ key: String) -> String { localization.string(key, table: "MusicDetails") }
}

struct TrackControlsLayout: Layout {
    var horizontal: CGFloat = 6
    var vertical: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
        let result = layout(subviews, width: width ?? .infinity)
        return CGSize(width: width ?? result.size.width, height: result.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews, width: bounds.width)
        for (subview, position) in zip(subviews, result.positions) {
            subview.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                          anchor: .topLeading, proposal: .unspecified)
        }
    }

    private func layout(_ subviews: Subviews, width: CGFloat) -> (positions: [CGPoint], size: CGSize) {
        var result: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + vertical
                rowHeight = 0
            }
            result.append(CGPoint(x: x, y: y))
            maxWidth = max(maxWidth, x + size.width)
            x += size.width + horizontal
            rowHeight = max(rowHeight, size.height)
        }
        return (result, CGSize(width: maxWidth, height: y + rowHeight))
    }
}
#endif
