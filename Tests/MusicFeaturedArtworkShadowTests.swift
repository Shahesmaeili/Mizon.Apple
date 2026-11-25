#if os(macOS)
import CoreGraphics
import SwiftUI
import Testing
@testable import MizonAppleUI

struct MusicFeaturedArtworkShadowTests {
    @MainActor @Test func rendersTheCalibratedFalloffAndPreservesTheArtworkTint() throws {
        let tint = Color(.sRGB, red: 64.0 / 255, green: 128.0 / 255, blue: 192.0 / 255)
        let renderer = ImageRenderer(content: Color.clear.frame(width: 600, height: 600).overlay {
            MusicFeaturedArtworkShadow(color: tint).frame(width: 400, height: 400)
        })
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let near = try pixel(in: image, x: 519, y: 300)
        let opposite = try pixel(in: image, x: 80, y: 300)
        let farther = try pixel(in: image, x: 539, y: 300)
        let outside = try pixel(in: image, x: 590, y: 300)

        #expect((50...68).contains(near[3]))
        #expect((12...24).contains(farther[3]))
        #expect(abs(Int(near[3]) - Int(opposite[3])) <= 6)
        #expect(outside[3] == 0)
        let opacity = Double(near[3]) / 255
        for (channel, value) in zip(near.prefix(3), [64.0, 128.0, 192.0]) {
            #expect(abs(Double(channel) - value * opacity) <= 2)
        }
    }

    @MainActor @Test func keepsThePlayerHaloOnTheOutsideAndDampsItAsOneLayer() async throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let sample = try #require(CGContext(data: nil, width: 24, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        sample.setFillColor(red: 0.17, green: 0.38, blue: 0.92, alpha: 1)
        sample.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        let source = try #require(sample.makeImage())
        let palette = try #require(await MusicHeroPalette.extract(from: source))
        func render(opacity: Double) throws -> CGImage {
            let renderer = ImageRenderer(content: Color.clear.frame(width: 500, height: 400).overlay {
                MusicHeroSpectrum(center: CGPoint(x: 0, y: 100), palette: palette, opacity: opacity)
                    .frame(width: 300, height: 200)
            })
            renderer.scale = 1
            return try #require(renderer.cgImage)
        }

        let full = try render(opacity: 1)
        let half = try render(opacity: 0.5)
        let near = try pixel(in: full, x: 99, y: 200)
        let midway = try pixel(in: full, x: 94, y: 200)
        let outside = try pixel(in: full, x: 79, y: 200)
        let inside = try pixel(in: full, x: 104, y: 200)
        let opposite = try pixel(in: full, x: 401, y: 200)
        let dimmed = try pixel(in: half, x: 99, y: 200)

        #expect((28...55).contains(near[3]))
        #expect(midway[3] > 0 && midway[3] < near[3])
        #expect(near[2] > near[1] && near[1] > near[0])
        #expect(outside[3] == 0 && inside[3] == 0 && opposite[3] == 0)
        #expect(abs(Int(near[3]) - 2 * Int(dimmed[3])) <= 2, "Full alpha \(near[3]), half alpha \(dimmed[3])")
    }

    private func pixel(in image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let sample = try #require(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                                 bytesPerRow: 4, space: space, bitmapInfo: bitmapInfo))
            context.setBlendMode(.copy)
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }
}
#endif
