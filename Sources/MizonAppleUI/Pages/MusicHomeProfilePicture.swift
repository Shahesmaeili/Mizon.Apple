#if os(macOS) || os(iOS)
import SwiftUI

struct MusicHomeProfilePicture: View {
    let avatar: CGImage?
    let displayName: String?

    var body: some View {
        ZStack {
            if let avatar {
                Image(decorative: avatar, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
            } else {
                Circle().fill(MizonPalette.ink.opacity(0.14))
                if let initials {
                    Text(initials)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MizonPalette.ink)
                        .lineLimit(1)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(MizonPalette.ink)
                }
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initials: String? {
        guard let words = displayName?.split(whereSeparator: \.isWhitespace), let first = words.first?.first else { return nil }
        if words.count > 1, let last = words.last?.first { return String([first, last]).uppercased() }
        return String(first).uppercased()
    }
}
#endif
