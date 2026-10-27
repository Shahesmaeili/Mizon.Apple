import SwiftUI
import ImageIO

private enum BrandArtwork {
    static let frames: [(CGImage, Double)] = {
        guard let url = Bundle.module.url(forResource: "Animation", withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
        var end = 0.0
        return (0..<CGImageSourceGetCount(source)).compactMap { index in
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            end += (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            return (image, end)
        }
    }()
}
struct AnimatedBrand: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { timeline in
            let frames = BrandArtwork.frames
            if let duration = frames.last?.1, duration > 0 {
                let time = reduceMotion ? 0 : max(0, timeline.date.timeIntervalSince(start)).truncatingRemainder(dividingBy: duration)
                if let frame = frames.first(where: { time < $0.1 }) {
                    Image(decorative: frame.0, scale: 1).resizable().scaledToFit()
                }
            }
        }
        .frame(width: 140, height: 140)
        .accessibilityHidden(true)
    }
}
struct BrandWordmark: View {
    var body: some View { Text("MIZON").font(WindowsTypography.iranSans(16)) }
}
