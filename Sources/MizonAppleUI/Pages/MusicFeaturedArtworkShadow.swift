#if os(macOS) || os(iOS)
import SwiftUI

struct MusicFeaturedArtworkShadow: View {
    static let cornerRadius: CGFloat = 12
    private static let blurRadius: CGFloat = 80
    // Canvas takes the standard deviation. Microsoft's WinUI reference render also follows
    // Direct2D's three-sigma kernel radius (25 points in the sample gives about 8.6 points).
    private static let standardDeviation = blurRadius / 3

    let color: Color

    var body: some View {
        Canvas(colorMode: .nonLinear) { context, size in
            let mask = CGRect(origin: .zero, size: size).insetBy(dx: Self.blurRadius, dy: Self.blurRadius)
            guard mask.width > 0, mask.height > 0 else { return }
            let radius = min(Self.cornerRadius, min(mask.width, mask.height) / 2)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: Self.standardDeviation))
                layer.fill(Path(roundedRect: mask, cornerRadius: radius, style: .circular), with: .color(color))
            }
        }
        .padding(-Self.blurRadius)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
