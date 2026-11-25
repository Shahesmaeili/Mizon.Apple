#if os(macOS)
import CoreGraphics
import SwiftUI
import Testing
@testable import MizonAppleUI

struct MusicStoryOrbitTests {
    @MainActor @Test func rendersTheLabelsIntoTransparentImages() throws {
        let cards = MusicStoryOrbit.renderLabels(pixelWidth: 1440, colorScheme: .dark)
        #expect(cards.count == 3)
        for card in cards {
            #expect(card.count == 3)
            for (index, label) in card.enumerated() {
                let image = try #require(label)
                let size = [CGSize(width: 180, height: 132), CGSize(width: 80, height: 88),
                            CGSize(width: 480, height: 132)][index]
                #expect(image.width == Int(size.width))
                #expect(image.height == Int(size.height))
                let bounds = try visibleBounds(of: image)
                #expect(bounds.width > 10 && bounds.height > 8)
                #expect(bounds.minX > 0 && bounds.minY > 0)
                #expect(bounds.maxX < size.width && bounds.maxY < size.height)
            }
        }
    }

    private func visibleBounds(of image: CGImage) throws -> CGRect {
        let width = image.width
        let height = image.height
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let format = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: width, height: height,
                                                 bitsPerComponent: 8, bytesPerRow: width * 4,
                                                 space: space, bitmapInfo: format))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var bounds = CGRect.null
            for y in 0..<height {
                for x in 0..<width where buffer[(y * width + x) * 4 + 3] > 16 {
                    bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
            return bounds
        }
    }
}
#endif
