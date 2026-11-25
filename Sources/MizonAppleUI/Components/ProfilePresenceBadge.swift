import SwiftUI

struct ProfilePresenceBadgeMetrics {
    let size: CGFloat
    var badge: CGFloat { size * 9 / 32 }
    var center: CGFloat { size - badge / 2 - size / 64 }
    var cutoutRadius: CGFloat { badge / 2 + size * 2.5 / 32 }

    static func color(isOnline: Bool) -> Color {
        isOnline ? Color(.sRGB, red: 48 / 255, green: 201 / 255, blue: 127 / 255)
                 : Color(.sRGB, red: 141 / 255, green: 150 / 255, blue: 168 / 255)
    }
}

struct ProfilePresenceBadge<Portrait: View>: View {
    let size: CGFloat
    let isOnline: Bool
    @ViewBuilder let portrait: () -> Portrait

    var body: some View {
        let metrics = ProfilePresenceBadgeMetrics(size: size)
        portrait()
            .frame(width: size, height: size)
            .mask {
                Path { path in
                    path.addRect(CGRect(x: 0, y: 0, width: size, height: size))
                    let radius = metrics.cutoutRadius
                    path.addEllipse(in: CGRect(x: metrics.center - radius, y: metrics.center - radius,
                                               width: radius * 2, height: radius * 2))
                }
                .fill(.white, style: FillStyle(eoFill: true))
            }
            .overlay {
                Circle()
                    .fill(ProfilePresenceBadgeMetrics.color(isOnline: isOnline))
                    .frame(width: metrics.badge, height: metrics.badge)
                    .position(x: metrics.center, y: metrics.center)
            }
            .accessibilityHidden(true)
    }
}
