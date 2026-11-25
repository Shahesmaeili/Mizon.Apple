#if os(macOS) || os(iOS)
import AVFoundation
import Foundation

@MainActor
enum MusicFeatureVideoReadiness {
    static func observe(_ item: AVPlayerItem, timeout: Duration = .seconds(10),
                        ready: @MainActor () throws -> Void) async throws {
        let (statuses, output) = AsyncStream<AVPlayerItem.Status>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let observation = item.observe(\.status, options: [.initial, .new]) { @Sendable item, _ in
            output.yield(item.status)
        }
        defer { observation.invalidate(); output.finish() }
        let deadline = Task {
            try await Task.sleep(for: timeout)
            output.finish()
        }
        defer { deadline.cancel() }
        var didBecomeReady = false
        for await status in statuses {
            try Task.checkCancellation()
            if status == .failed { throw item.error ?? CocoaError(.fileReadCorruptFile) }
            if status == .readyToPlay, !didBecomeReady {
                didBecomeReady = true
                deadline.cancel()
                try ready()
            }
        }
        try Task.checkCancellation()
        if !didBecomeReady { throw URLError(.timedOut) }
    }
}
#endif
