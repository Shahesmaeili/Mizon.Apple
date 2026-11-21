#if os(macOS) || os(iOS)
import ImageIO
import SwiftUI

/// Displays the loose image resources packaged by SwiftPM, with a bounded decoded size.
struct MusicLocalArtwork: View {
    private let request: MusicArtworkRequest
    @State private var loaded: LoadedArtwork?

    init(_ name: String, maximumPixelSize: Int = 960) {
        request = MusicArtworkRequest(name: name, maximumPixelSize: maximumPixelSize)
    }

    var body: some View {
        Group {
            if let loaded, loaded.request == request, let image = loaded.image {
                Image(decorative: image, scale: 1).resizable()
            } else {
                Color.clear
            }
        }
        .task(id: request) {
            let image = await MusicLocalArtworkCache.shared.image(for: request)
            if !Task.isCancelled { loaded = LoadedArtwork(request: request, image: image) }
        }
        .accessibilityHidden(true)
    }

    static func image(named name: String, maximumPixelSize: Int) async -> CGImage? {
        await MusicLocalArtworkCache.shared.image(for: MusicArtworkRequest(name: name, maximumPixelSize: maximumPixelSize))
    }

    private struct LoadedArtwork {
        let request: MusicArtworkRequest
        let image: CGImage?
    }
}

private struct MusicArtworkRequest: Hashable, Sendable {
    let name: String
    let maximumPixelSize: Int

    init(name: String, maximumPixelSize: Int) {
        self.name = name
        // Nearby card sizes share one decode. Keep the largest image below 2048 pixels.
        let bounded = min(2048, max(1, maximumPixelSize))
        self.maximumPixelSize = (bounded + 127) / 128 * 128
    }

    var cacheKey: NSString { "\(name):\(maximumPixelSize)" as NSString }
}

private actor MusicLocalArtworkCache {
    static let shared = MusicLocalArtworkCache()

    private let cache = NSCache<NSString, CGImage>()
    private var inFlight: [MusicArtworkRequest: Task<CGImage?, Never>] = [:]

    private init() {
        cache.totalCostLimit = 24 * 1024 * 1024
        cache.countLimit = 32
    }

    func image(for request: MusicArtworkRequest) async -> CGImage? {
        if let cached = cache.object(forKey: request.cacheKey) { return cached }
        if let loading = inFlight[request] { return await loading.value }

        let loading = Task.detached(priority: .utility) {
            Self.decode(request)
        }
        inFlight[request] = loading
        let image = await loading.value
        inFlight[request] = nil
        if let image {
            cache.setObject(image, forKey: request.cacheKey, cost: image.bytesPerRow * image.height)
        }
        return image
    }

    private static func decode(_ request: MusicArtworkRequest) -> CGImage? {
        let urls = ["jpg", "jpeg", "png"].lazy.compactMap {
            Bundle.module.url(forResource: request.name, withExtension: $0)
        }
        guard let url = urls.first, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: request.maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    }
}
#endif
