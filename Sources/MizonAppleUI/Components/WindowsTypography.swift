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
    static func iranSans(_ size: CGFloat) -> Font {
        _ = registered
        return .custom("IRANSans", size: size)
    }
}

enum FluentSymbol: Int {
    case personAccounts = 216, inPrivateAccount = 399, webAsset = 335
    case xboxController = 2009, dismiss = 112, settings = 257
    case checkmarkCircle = 82, networkCheck = 192, errorCircle = 425
    func glyph(rightToLeft: Bool = false) -> String {
        // FluentIcons.Common.Internals.Extensions.ToString(Regular, isRtl).
        String(UnicodeScalar(0xF0000 + 4 * rawValue + (rightToLeft ? 0x10000 : 0))!)
    }
}
struct FluentIcon: View {
    var symbol: FluentSymbol
    var size: CGFloat = 20
    var rightToLeft = false
    var body: some View {
        let _ = WindowsTypography.registered
        Text(symbol.glyph(rightToLeft: rightToLeft))
            .font(.custom("SeagullFluentIcons", size: size))
            .accessibilityHidden(true)
    }
}
