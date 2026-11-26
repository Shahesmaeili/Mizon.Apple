#if os(macOS) || os(iOS)
import SwiftUI

struct MusicHomeProfilePicture: View {
    let avatar: CGImage?
    let displayName: String?
    var isOnline: Bool? = nil
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let isOnline {
                ProfilePresenceBadge(size: size, isOnline: isOnline) { portrait }
            } else {
                portrait
            }
        }
        .accessibilityHidden(true)
    }

    private var portrait: some View {
        ZStack {
            if let avatar {
                Image(decorative: avatar, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
            } else {
                Circle().fill(MizonPalette.ink.opacity(0.14))
                if let initials {
                    Text(initials)
                        .font(.system(size: size * 12 / 32, weight: .semibold))
                        .foregroundStyle(MizonPalette.ink)
                        .lineLimit(1)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 14 / 32))
                        .foregroundStyle(MizonPalette.ink)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String? {
        guard let words = displayName?.split(whereSeparator: \.isWhitespace), let first = words.first?.first else { return nil }
        if words.count > 1, let last = words.last?.first { return String([first, last]).uppercased() }
        return String(first).uppercased()
    }
}
#endif
