import SwiftUI
import CoreText

/// The exact font families used by Mizon.Windows and FluentIcons.WinUI.
enum WindowsTypography {
    static let registered: Void = {
        for (name, ext) in [("IRANSANS", "TTF"), ("SeagullFluentIcons", "otf")] {
            if let url = Bundle.module.url(forResource: name, withExtension: ext) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()
    static let segoeAvailable = (CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? [])
        .contains("Segoe UI Variable")

    static func iranSans(_ size: CGFloat) -> Font {
        _ = registered
        return .custom("IRANSans", size: size)
    }
}

enum FluentSymbol: Int, CaseIterable {
    case personAccounts = 216, inPrivateAccount = 399, webAsset = 335
    case xboxController = 2009, dismiss = 112, settings = 257
    case arrowLeft = 18, desktop = 106, globe = 149, headphones = 152, person = 215
    case personAdd = 217, play = 234, video = 309, moviesAndTv = 408, tv = 864
    case moreHorizontal = 1086, musicNote1 = 1087
    case shieldLock = 1449, eyeOff = 1498, eye = 1824, filmstrip = 2023, wifi = 2692
    case checkmarkCircle = 82, dismissCircle = 113, networkCheck = 192
    case add = 2, apps = 12, arrowUpRight = 22, chevronLeft = 84, chevronRight = 85
    case clock = 90, heart = 154, history = 156, pause = 208, people = 209, search = 253, shield = 263
    case star = 276, arrowCounterclockwise = 430, album = 1005, speaker2 = 1109, speakerMute = 1110
    case sparkle = 1682, mic = 1826
    case agentsAdd = 2754, image = 158, checkmark = 81, guitar = 1206, soundWaveCircle = 1781
    case musicNote2 = 1088, pulse = 945, record = 550, fire = 2052, leafOne = 1077

    func glyph(rightToLeft: Bool = false, usesColor: Bool = false, filled: Bool = false) -> String {
        // FluentIcons.Common.Internals.Extensions.ToString(Regular or Color, isRtl).
        let variant = usesColor ? 2 : (filled ? 1 : 0)
        return String(UnicodeScalar(0xF0000 + 4 * rawValue + variant + (rightToLeft ? 0x10000 : 0))!)
    }
}
struct FluentIcon: View {
    var symbol: FluentSymbol
    var size: CGFloat = 20
    var rightToLeft = false
    var usesColor = false
    var filled = false
    var body: some View {
        let _ = WindowsTypography.registered
        Text(symbol.glyph(rightToLeft: rightToLeft, usesColor: usesColor, filled: filled))
            .font(.custom("SeagullFluentIcons", size: size))
            .accessibilityHidden(true)
    }
}
