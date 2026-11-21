#if os(macOS) || os(iOS)
import CoreGraphics
import SwiftUI

struct MusicArtworkEdgeColor: Equatable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var color: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }

    @concurrent
    static func extract(from image: CGImage) async -> Self? {
        let width = image.width
        let height = image.height
        guard !Task.isCancelled, width > 0, height > 0, max(width, height) <= Int.max / 4,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let halfCount = UInt64(width) + UInt64(height)
        guard halfCount <= UInt64.max / 510 else { return nil }

        // The Windows sampler reads four complete strips and counts the corners twice.
        let edges = [
            CGRect(x: 0, y: 0, width: width, height: 1),
            CGRect(x: 0, y: height - 1, width: width, height: 1),
            CGRect(x: 0, y: 0, width: 1, height: height),
            CGRect(x: width - 1, y: 0, width: 1, height: height),
        ]
        var totals: (red: UInt64, green: UInt64, blue: UInt64) = (0, 0, 0)
        for edge in edges {
            guard !Task.isCancelled, let strip = image.cropping(to: edge),
                  accumulate(strip, colorSpace: space, into: &totals) else { return nil }
        }
        guard !Task.isCancelled else { return nil }
        let count = halfCount * 2
        return Self(red: UInt8(totals.red / count), green: UInt8(totals.green / count), blue: UInt8(totals.blue / count))
    }

    private static func accumulate(_ strip: CGImage, colorSpace: CGColorSpace,
                                   into totals: inout (red: UInt64, green: UInt64, blue: UInt64)) -> Bool {
        // Win2D exposes premultiplied RGB. Draw one strip into sRGB without scaling or compositing.
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: strip.width, height: strip.height, bitsPerComponent: 8,
                                      bytesPerRow: strip.width * 4, space: colorSpace, bitmapInfo: bitmapInfo),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(strip, in: CGRect(x: 0, y: 0, width: strip.width, height: strip.height))
        let bytesPerRow = context.bytesPerRow
        for row in 0..<strip.height {
            if row.isMultiple(of: 256), Task.isCancelled { return false }
            let start = row * bytesPerRow
            for column in 0..<strip.width {
                let index = start + column * 4
                totals.red += UInt64(pixels[index])
                totals.green += UInt64(pixels[index + 1])
                totals.blue += UInt64(pixels[index + 2])
            }
        }
        return true
    }
}
#endif
