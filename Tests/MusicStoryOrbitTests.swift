#if os(macOS)
import CoreGraphics
import simd
import SwiftUI
import Testing
@testable import MizonAppleUI

struct MusicStoryOrbitTests {
    @MainActor @Test func crossingTheThreeImagesKeepsTheSharedPointerMotionContinuous() throws {
        let panel = CGRect(x: 0, y: 0, width: 1440, height: 560)
        let motion = MusicStoryOrbitPointerMotion()
        let crossingPoints: [CGFloat] = [440, 475, 485, 915, 920, 925, 1365]
        for boundary in crossingPoints {
            let before = try #require(MusicStoryOrbitInput.pointer(CGPoint(x: boundary - 1, y: 210), in: panel))
            let after = try #require(MusicStoryOrbitInput.pointer(CGPoint(x: boundary + 1, y: 210), in: panel))
            motion.update(before, at: 1)
            let previous = motion.position(at: 2)
            motion.update(after, at: 2)
            let next = motion.position(at: 2)
            #expect(abs(next.x - previous.x) < 0.003)
            #expect(next.y == previous.y)
        }
        #expect(MusicStoryOrbitInput.pointer(CGPoint(x: 1440, y: 210), in: panel) == nil)
    }

    @MainActor @Test func leavingAndReenteringThePanelStartsFromTheDisplayedPose() {
        let motion = MusicStoryOrbitPointerMotion()
        motion.update(CGPoint(x: 0.8, y: -0.5), at: 1)
        let hovered = motion.position(at: 2)
        motion.update(nil, at: 2)
        #expect(motion.position(at: 2) == hovered)

        let exiting = motion.position(at: 2.08)
        #expect(exiting.x > 0 && exiting.x < hovered.x)
        motion.update(CGPoint(x: -1, y: 0.3), at: 2.08)
        #expect(motion.position(at: 2.08) == exiting)
        #expect(motion.position(at: 3) == CGPoint(x: -1, y: 0.3))
        motion.update(nil, at: 3)
        #expect(motion.position(at: 4) == .zero)
    }

    @Test func deviceAxesFollowPortraitAndBothUIKitLandscapeDirections() {
        let vector = CGPoint(x: 0.25, y: 0.75)
        #expect(MusicStoryOrbitOrientation.portrait.screenVector(vector) == CGPoint(x: 0.25, y: -0.75))
        #expect(MusicStoryOrbitOrientation.portraitUpsideDown.screenVector(vector) == CGPoint(x: -0.25, y: 0.75))
        #expect(MusicStoryOrbitOrientation.landscapeLeft.screenVector(vector) == CGPoint(x: 0.75, y: 0.25))
        #expect(MusicStoryOrbitOrientation.landscapeRight.screenVector(vector) == CGPoint(x: -0.75, y: -0.25))
    }

    @Test func fusedTiltCalibratesFromAnUprightPhoneAndRemainsBounded() {
        let upright = simd_quatd(angle: .pi / 2, axis: SIMD3<Double>(1, 0, 0))
        let turnsRight = simd_quatd(angle: .pi / 4, axis: SIMD3<Double>(0, 1, 0)).inverse * upright
        var tilt = MusicStoryOrbitTilt()
        #expect(tilt.sample(upright, orientation: .portrait, at: 1) == .zero)

        let first = tilt.sample(turnsRight, orientation: .portrait, at: 1.033)
        #expect(first.x > 0 && first.x < 0.35)
        #expect(abs(first.y) < 0.0001)
        #expect(tilt.sample(turnsRight, orientation: .portrait, at: 1.033) == first)
        var settled = first
        for step in 2...30 {
            settled = tilt.sample(turnsRight, orientation: .portrait, at: 1 + Double(step) / 30)
        }
        #expect(settled.x > 0.99 && settled.x <= 1)
        #expect(tilt.sample(turnsRight, orientation: .landscapeRight, at: 3) == .zero)

        let nextTilt = simd_quatd(angle: .pi / 12, axis: SIMD3<Double>(1, 0, 0)).inverse * turnsRight
        let landscape = tilt.sample(nextTilt, orientation: .landscapeRight, at: 3.033)
        #expect(landscape.x > 0 && abs(landscape.y) < 0.0001)
    }

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
