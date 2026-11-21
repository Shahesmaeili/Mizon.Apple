#if os(macOS) || os(iOS)
import Foundation
import SwiftUI
@preconcurrency import Lottie
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct MoodLottieView: View {
    let file: URL
    let looping: Bool
    let playing: Bool
    var restartID: UUID? = nil
    var onReady: (() -> Void)? = nil
    var onCompletion: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loaded: LoadedAnimation?
    nonisolated private static let cache: DefaultAnimationCache = {
        let cache = DefaultAnimationCache()
        cache.cacheSize = 8
        return cache
    }()

    var body: some View {
        Group {
            if let loaded, loaded.file == file {
                MoodLottieSurface(animation: loaded.animation, looping: looping, playing: playing && !reduceMotion,
                                  restartID: restartID, completion: onCompletion)
            } else {
                Color.clear
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .task(id: file) {
            do {
                let animation = try await Self.decode(file)
                try Task.checkCancellation()
                loaded = LoadedAnimation(file: file, animation: animation)
                onReady?()
            } catch {
                if !Task.isCancelled {
                    loaded = nil
                    // A failed one-shot must clear its overlay just as a completed effect does.
                    if !looping { onCompletion?() }
                }
            }
        }
    }

    private struct LoadedAnimation {
        let file: URL
        let animation: LottieAnimation
    }

    @concurrent
    static func decode(_ file: URL) async throws -> LottieAnimation {
        if let animation = cache.animation(forKey: file.path) { return animation }
        let data = try Data(contentsOf: file, options: [.mappedIfSafe])
        guard !data.isEmpty, data.count <= 8 * 1024 * 1024 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let animation = try LottieAnimation.from(data: data)
        try Task.checkCancellation()
        cache.setAnimation(animation, forKey: file.path)
        return animation
    }
}

#if os(macOS)
private typealias MoodNativeRepresentable = NSViewRepresentable
#else
private typealias MoodNativeRepresentable = UIViewRepresentable
#endif

private struct MoodLottieSurface: MoodNativeRepresentable {
    let animation: LottieAnimation
    let looping: Bool
    let playing: Bool
    let restartID: UUID?
    let completion: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func make() -> LottieAnimationView {
        let view = LottieAnimationView()
        view.contentMode = .scaleAspectFit
        view.backgroundBehavior = .pauseAndRestore
        view.maskAnimationToBounds = true
        return view
    }

    #if os(macOS)
    func makeNSView(context: Context) -> LottieAnimationView { make() }
    func updateNSView(_ view: LottieAnimationView, context: Context) { context.coordinator.update(view, from: self) }
    static func dismantleNSView(_ view: LottieAnimationView, coordinator: Coordinator) { coordinator.clear(view) }
    #else
    func makeUIView(context: Context) -> LottieAnimationView { make() }
    func updateUIView(_ view: LottieAnimationView, context: Context) { context.coordinator.update(view, from: self) }
    static func dismantleUIView(_ view: LottieAnimationView, coordinator: Coordinator) { coordinator.clear(view) }
    #endif

    @MainActor
    final class Coordinator {
        private var playing = false
        private var restartID: UUID?
        private var isLooping = false
        private var completed = false
        private var revision = 0

        func update(_ view: LottieAnimationView, from desired: MoodLottieSurface) {
            let changed = view.animation !== desired.animation || restartID != desired.restartID || isLooping != desired.looping
            if changed {
                revision += 1
                if view.animation !== desired.animation { view.animation = desired.animation }
                view.currentProgress = 0
                completed = false
            }
            restartID = desired.restartID
            isLooping = desired.looping
            guard changed || playing != desired.playing else { return }
            playing = desired.playing

            if !playing {
                view.pause()
            } else if !completed {
                if desired.looping {
                    view.play(fromProgress: 0, toProgress: 1, loopMode: .loop)
                    return
                }
                let playbackRevision = revision
                view.play(toProgress: 1, loopMode: .playOnce) { [weak self] finished in
                    guard let self, finished, self.revision == playbackRevision else { return }
                    self.completed = true
                    desired.completion?()
                }
            }
        }

        func clear(_ view: LottieAnimationView) {
            revision += 1
            view.stop()
        }
    }
}
#endif
