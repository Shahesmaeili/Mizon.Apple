import SwiftUI
import ImageIO

private enum BrandArtwork {
    static let headphones: CGImage? = {
        guard let url = Bundle.module.url(forResource: "MizonHeadphones", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()
    static let animationFrames: [CGImage] = {
        guard let url = Bundle.module.url(forResource: "Animation", withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
        return (0..<CGImageSourceGetCount(source)).compactMap { CGImageSourceCreateImageAtIndex(source, $0, nil) }
    }()
}

struct HeadphonesImage: View {
    var body: some View {
        if let image = BrandArtwork.headphones {
            Image(decorative: image, scale: 1).resizable().scaledToFit()
        } else { Image(systemName: "headphones").resizable().scaledToFit() }
    }
}

struct AnimatedBrand: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().fill(.cyan.opacity(0.06)).frame(width: 122, height: 122)
            Circle().stroke(LinearGradient(colors: [.cyan.opacity(0.4), .white.opacity(0.04), .indigo.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                .frame(width: 122, height: 122)
            HeadphonesImage().frame(width: 78, height: 78)
            TimelineView(.animation(minimumInterval: 0.05, paused: reduceMotion)) { timeline in
                let frames = BrandArtwork.animationFrames
                if !frames.isEmpty {
                    let frame = reduceMotion ? frames.count / 2 : Int(timeline.date.timeIntervalSinceReferenceDate / 0.05) % frames.count
                    Image(decorative: frames[frame], scale: 1).resizable().scaledToFit()
                        .frame(width: 140, height: 140).blendMode(.screen)
                } else { HeadphonesImage().frame(width: 70, height: 70) }
            }
            .frame(width: 96, height: 96).clipped().opacity(0.45)
        }
        .frame(height: 132)
        .accessibilityHidden(true)
    }
}

struct BrandWordmark: View {
    var body: some View {
        HStack(spacing: 10) {
            HeadphonesImage().frame(width: 28, height: 28)
            Text("MIZON").font(.system(size: 16, weight: .bold, design: .rounded)).tracking(3.5)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("میزون")
    }
}
