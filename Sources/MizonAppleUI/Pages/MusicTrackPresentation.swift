#if os(macOS) || os(iOS)
import AVKit
import MizonAPIClient
import MizonAppleCore
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
import CoreAudio
#else
import UIKit
#endif

struct TrackPulsingArtwork: View {
    let details: MusicTrackDetailsViewModel
    let position: MusicTrackDetailsView.Playhead
    let size: CGFloat
    let namespace: Namespace.ID
    let coverOpen: Bool
    let accent: Color
    let focus: Bool
    let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let localization = AuthLocalization()

    var body: some View {
        let active = details.music.playingTrack == details.id && details.music.isPlaying
        let energy = active && !reduceMotion ? amplitude : 0
        Button(action: open) {
            MusicArtwork(mediaID: details.track.musicCover?.mediaPublicId, model: details.music, symbol: "music.note", stretch: true)
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: 8))
                .matchedGeometryEffect(id: "track-artwork", in: namespace, isSource: !coverOpen)
                .opacity(coverOpen ? 0 : 1)
        }
        .buttonStyle(.plain)
        .disabled(details.track.musicCover == nil)
        .shadow(color: accent.opacity(active ? 0.43 : 0.27), radius: 30, x: 0, y: 16)
        .modifier(TrackFocus(isFocused: focus))
        .scaleEffect(1 + energy * 0.10)
        .animation(reduceMotion ? nil : .spring(response: 0.20, dampingFraction: 0.71), value: energy)
        .authHandPointer(enabled: details.track.musicCover != nil)
        .accessibilityLabel(localization.string("Cover", table: "MusicDetails"))
        .accessibilityIdentifier("music.track.cover")
    }

    private var amplitude: Double {
        let wave = details.wave
        guard details.duration > 0, !wave.isEmpty else { return 0 }
        let point = min(wave.count - 1, max(0, Int(position.seconds / details.duration * Double(wave.count))))
        return wave[point].energy
    }
}

struct TrackTimeLabel: View {
    let position: MusicTrackDetailsView.Playhead
    let duration: Double
    var body: some View {
        Text(MusicTrackDetailsView.time(position.seconds) + " / " + MusicTrackDetailsView.time(duration))
            .font(AuthLocalization.englishFont(12)).monospacedDigit().lineLimit(1)
            .foregroundStyle(MizonPalette.secondaryText)
            .padding(.horizontal, 5).frame(minHeight: 34)
            .environment(\.layoutDirection, .leftToRight)
    }
}

struct TrackWaveformPlayback: View {
    let details: MusicTrackDetailsViewModel
    let position: MusicTrackDetailsView.Playhead
    let seek: (Double) -> Void
    let addComment: (Double) -> Void
    let openComment: (MusicCommentItemResponse) -> Void
    var body: some View {
        MusicTrackWaveform(bars: details.wave, comments: details.timedComments, listeners: details.listeners,
                           duration: details.duration, position: position.seconds,
                           playing: details.music.playingTrack == details.id && details.music.isPlaying,
                           music: details.music, seek: seek, addComment: addComment, openComment: openComment)
    }
}

struct TrackCurrentLyric: View {
    let details: MusicTrackDetailsViewModel
    let position: MusicTrackDetailsView.Playhead
    let localization = AuthLocalization()
    var body: some View {
        let time = Int(min(max(0, position.seconds), 1_000_000) * 1_000)
        if let current = details.lyrics.first(where: { $0.startTimeInMilliseconds <= time && time < max($0.endTimeInMilliseconds, $0.startTimeInMilliseconds + 1) }) {
            Text(current.text).font(localization.font(13)).lineLimit(1)
                .foregroundStyle(MizonPalette.secondaryText).frame(maxWidth: .infinity)
        }
    }
}

struct TrackLyrics: View {
    let details: MusicTrackDetailsViewModel
    let position: MusicTrackDetailsView.Playhead
    let focus: MusicTrackDetailsView.Target?
    let select: (MusicTrackDetailsView.Target) -> Void
    let localization = AuthLocalization()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let time = Int(min(max(0, position.seconds), 1_000_000) * 1_000)
        if details.lyrics.isEmpty {
            if details.loading.contains(.lyrics) { ProgressView() }
            else if details.failures.contains(.lyrics) {
                Button(localization.string("TrackRetry", table: "MusicDetails")) { select(.retry(.lyrics)) }
                    .buttonStyle(TrackButtonStyle(focused: focus == .retry(.lyrics))).id(MusicTrackDetailsView.Target.retry(.lyrics))
            } else { Text(localization.string("TrackNoLyrics", table: "MusicDetails")).foregroundStyle(.secondary) }
        } else {
            let current = details.lyrics.first { $0.startTimeInMilliseconds <= time &&
                time < max($0.endTimeInMilliseconds, $0.startTimeInMilliseconds + 1) }?.lineOrder
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(details.lyrics, id: \.lineOrder) { line in
                            Button { select(.lyric(line.lineOrder)) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    if line.musicLyricLineWords.isEmpty {
                                        Text(line.text).font(localization.font(14))
                                    } else {
                                        TrackControlsLayout(horizontal: 4, vertical: 6) {
                                            ForEach(line.musicLyricLineWords, id: \.wordOrder) { word in
                                                let active = line.lineOrder == current && word.startTimeInMilliseconds <= time &&
                                                    time < max(word.endTimeInMilliseconds, word.startTimeInMilliseconds + 1)
                                                Text(word.text).font(localization.font(14))
                                                    .padding(.horizontal, 3).padding(.vertical, 2)
                                                    .background(active ? musicColor("0078D4").opacity(0.48) : .clear, in: .rect(cornerRadius: 4))
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(line.lineOrder == current ? Color.white.opacity(0.08) : .clear, in: .rect(cornerRadius: 8))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .modifier(TrackFocus(isFocused: focus == .lyric(line.lineOrder)))
                            .accessibilityLabel(line.text)
                            .accessibilityAddTraits(line.lineOrder == current ? .isSelected : [])
                            .id(MusicTrackDetailsView.Target.lyric(line.lineOrder))
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 300)
                .onChange(of: current) { _, line in
                    if let line {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
                            reader.scrollTo(MusicTrackDetailsView.Target.lyric(line), anchor: .center)
                        }
                    }
                }
                .onChange(of: focus) { _, next in
                    if case .lyric = next { reader.scrollTo(next, anchor: .center) }
                }
            }
        }
    }
}

#if os(macOS)
@MainActor final class TrackFloatingWindow {
    private var panel: NSPanel?

    func open<Content: View>(_ content: Content, title: String) {
        close()
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 156),
                            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.contentView = NSHostingView(rootView: content)
        panel.center()
        panel.orderFront(nil)
        self.panel = panel
    }

    func close() {
        panel?.close()
        panel = nil
    }
}

struct TrackAudioOutput: Identifiable {
    let id: String
    let name: String

    static func list() -> [Self] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard !ids.isEmpty, ids.withUnsafeMutableBytes({
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!)
        }) == noErr else { return [] }
        return ids.compactMap { id in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                       mScope: kAudioDevicePropertyScopeOutput,
                                                       mElement: kAudioObjectPropertyElementMain)
            var dataSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &dataSize) == noErr, dataSize > 0,
                  let uid = string(id, kAudioDevicePropertyDeviceUID), let name = string(id, kAudioObjectPropertyName) else { return nil }
            return Self(id: uid, name: name)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
        var result: Unmanaged<CFString>?
        var length = UInt32(MemoryLayout.size(ofValue: result))
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &length, &result) == noErr else { return nil }
        return result?.takeRetainedValue() as String?
    }
}
#else
struct TrackAudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor(MizonPalette.ink)
        view.activeTintColor = UIColor(MizonPalette.accent)
        view.prioritizesVideoDevices = false
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
#endif
#endif

#if os(macOS) || os(iOS)
struct MusicTrackLoadingView: View {
    let loading: Bool
    let focus: Bool
    let retry: () -> Void
    private let localization = AuthLocalization()

    var body: some View {
        ScrollView {
            GeometryReader { geometry in
                let metrics = MusicTrackLayoutMetrics(width: geometry.size.width, height: geometry.size.height)
                let layout = metrics.sideBySide ? AnyLayout(HStackLayout(alignment: .top, spacing: metrics.compactLandscape ? 16 : 32)) :
                    AnyLayout(VStackLayout(alignment: .center, spacing: 24))
                layout {
                    RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06))
                        .frame(width: metrics.artwork, height: metrics.artwork)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        if loading {
                            MusicReferenceRailSkeleton(title: localization.string("LoadingTrack", table: "MusicDetails"),
                                                       minimumHeight: 135, localization: localization)
                        } else {
                            Text(localization.string("TrackLoadFailed", table: "MusicDetails"))
                                .font(localization.font(14, weight: .semibold))
                            Button(localization.string("TrackRetry", table: "MusicDetails"), action: retry)
                                .buttonStyle(.glass)
                                .modifier(TrackFocus(isFocused: focus))
                                .accessibilityIdentifier("music.track.retry")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, metrics.wide ? 16 : 0)
                }
                .padding(32)
                .frame(maxWidth: .infinity)
                .background(MusicHomeStyle.secondaryCard, in: .rect(cornerRadius: 8))
            }
            .frame(minHeight: 500)
            .padding(.horizontal, 14).padding(.top, 16)
        }
        .accessibilityIdentifier("music.track.loading")
    }
}
#endif
