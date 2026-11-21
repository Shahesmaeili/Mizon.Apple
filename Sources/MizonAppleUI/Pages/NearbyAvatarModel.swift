#if os(macOS) || os(iOS)
import CoreGraphics
import Foundation
import MizonAppleCore
import Observation

@MainActor @Observable
final class NearbyAvatarModel {
    private struct Lookup: Sendable {
        let username: String
        let image: CGImage?
    }

    private struct CachedImage {
        let image: CGImage?
        let expiresAt: ContinuousClock.Instant
    }

    private static let maximumConcurrent = 3
    private static let maximumCached = 64

    private(set) var images: [String: CGImage] = [:]
    @ObservationIgnored private var cache: [String: CachedImage] = [:]
    @ObservationIgnored private var generation: UInt = 0

    static func usernames(for peers: [NearbyDiscoveredPeer]) -> [String] {
        Set(peers.compactMap { NearbyProfileArtworkService.normalizedUsername($0.account) }).sorted()
    }

    func load(for usernames: [String],
              using fetch: @escaping @Sendable (String) async throws -> CGImage?) async {
        guard !Task.isCancelled else { return }
        generation &+= 1
        let currentGeneration = generation
        let now = ContinuousClock.now
        cache = cache.filter { now < $0.value.expiresAt }
        images = Dictionary(uniqueKeysWithValues: usernames.compactMap { username in
            cache[username]?.image.map { (username, $0) }
        })
        let pending = usernames.filter { cache[$0] == nil }
        guard !pending.isEmpty else { return }

        do {
            try await Task.sleep(for: .milliseconds(150))
        } catch { return }
        guard !Task.isCancelled, currentGeneration == generation else { return }

        await withTaskGroup(of: Lookup.self) { group in
            var remaining = pending.makeIterator()
            func submitNext() {
                guard let username = remaining.next() else { return }
                _ = group.addTaskUnlessCancelled {
                    Lookup(username: username, image: try? await fetch(username))
                }
            }
            for _ in 0..<Self.maximumConcurrent { submitNext() }
            for await lookup in group {
                guard !Task.isCancelled, currentGeneration == generation else {
                    group.cancelAll()
                    return
                }
                if cache.count == Self.maximumCached,
                   let evicted = cache.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
                    cache.removeValue(forKey: evicted)
                }
                let lifetime: Duration = .seconds(lookup.image == nil ? 30 : 300)
                cache[lookup.username] = CachedImage(image: lookup.image,
                                                   expiresAt: .now.advanced(by: lifetime))
                images[lookup.username] = lookup.image
                submitNext()
            }
        }
    }
}
#endif
