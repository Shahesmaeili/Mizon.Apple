#if os(macOS) || os(iOS)
import AVKit
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(macOS)
struct MusicInlineVideo: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        view.wantsLayer = true
        view.layer = layer
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view.layer as? AVPlayerLayer)?.player = player
    }
}
#else
struct MusicInlineVideo: UIViewRepresentable {
    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
    }

    let player: AVPlayer

    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        (view.layer as? AVPlayerLayer)?.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: Surface, context: Context) {
        (view.layer as? AVPlayerLayer)?.player = player
    }
}
#endif

struct MusicFeatureExport: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { file in
            SentTransferredFile(file.url)
        }
    }
}

struct MusicFeatureScrubber: View {
    let player: AVPlayer
    let title: String
    @State private var position = 0.0
    @State private var duration = 0.0
    @State private var dragging = false

    var body: some View {
        Slider(value: $position, in: 0...max(1, duration)) { Text(title) } onEditingChanged: { editing in
            dragging = editing
            if !editing {
                player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
            }
        }
        .disabled(duration <= 0)
        .task {
            while !Task.isCancelled {
                if !dragging, let item = player.currentItem, item.duration.seconds.isFinite {
                    duration = max(0, item.duration.seconds)
                    let current = player.currentTime().seconds
                    if current.isFinite { position = max(0, min(duration, current)) }
                }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
        }
    }
}

struct MusicFullWindowPresentation<Video: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder var video: () -> Video

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: $isPresented, content: video)
        #else
        content.sheet(isPresented: $isPresented) { video().frame(minWidth: 780, minHeight: 480) }
        #endif
    }
}
#endif
