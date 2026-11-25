import SwiftUI

enum MizonPalette {
    static let surface = color(0x1E1E2E)
    static let ink = color(0xCDD6F4)
    static let accent = color(0xCBA6F7)
    static let secondaryAccent = color(0xAD7BF9)
    static let positive = color(0xA6E3A1)
    static let negative = color(0xF38BA8)
    static let secondaryText = ink.opacity(197.0 / 255)

    private static func color(_ rgb: UInt32) -> Color {
        Color(.sRGB, red: Double((rgb >> 16) & 255) / 255,
              green: Double((rgb >> 8) & 255) / 255,
              blue: Double(rgb & 255) / 255)
    }
}
