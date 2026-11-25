#if os(macOS) || os(iOS)
import simd
import SwiftUI

enum MusicStoryOrbitInput {
    static func pointer(_ location: CGPoint?, in panel: CGRect) -> CGPoint? {
        guard let location, panel.width > 0, panel.height > 0, panel.contains(location) else { return nil }
        return CGPoint(x: unit((location.x - panel.midX) / (panel.width / 2)),
                       y: unit((location.y - panel.midY) / (panel.height / 2)))
    }

    static func unit(_ value: CGFloat) -> CGFloat { min(1, max(-1, value)) }
}

@MainActor
final class MusicStoryOrbitPointerMotion {
    private static let response = 0.220
    private static let ease = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.18, y: 0.7),
                                              endControlPoint: UnitPoint(x: 0.2, y: 1))
    private var target: CGPoint?
    private var origin = CGPoint.zero
    private var startedAt = 0.0

    func update(_ target: CGPoint?, at time: TimeInterval) {
        if (self.target == nil) != (target == nil) {
            origin = position(at: time)
            startedAt = time
        }
        self.target = target
    }

    func position(at time: TimeInterval) -> CGPoint {
        let target = target ?? .zero
        let fraction = (time - startedAt) / Self.response
        if fraction >= 1 { return target }
        let progress = Self.ease.value(at: max(0, fraction))
        return CGPoint(x: origin.x + (target.x - origin.x) * progress,
                       y: origin.y + (target.y - origin.y) * progress)
    }

    func reset() {
        target = nil
        origin = .zero
        startedAt = 0
    }
}

enum MusicStoryOrbitOrientation: Equatable {
    case portrait, portraitUpsideDown, landscapeLeft, landscapeRight

    func screenVector(_ device: CGPoint) -> CGPoint {
        switch self {
        case .portrait: CGPoint(x: device.x, y: -device.y)
        case .portraitUpsideDown: CGPoint(x: -device.x, y: device.y)
        // UIKit's interface orientations are opposite the corresponding UIDevice names.
        case .landscapeLeft: CGPoint(x: device.y, y: device.x)
        case .landscapeRight: CGPoint(x: -device.y, y: -device.x)
        }
    }
}

struct MusicStoryOrbitTilt {
    static let sampleInterval = 1.0 / 30
    private static let fullTilt = Double.pi / 12
    private static let response = 0.120
    private var reference: simd_quatd?
    private var orientation: MusicStoryOrbitOrientation?
    private var timestamp = 0.0
    private var position = CGPoint.zero

    mutating func sample(_ attitude: simd_quatd, orientation: MusicStoryOrbitOrientation, at time: TimeInterval) -> CGPoint {
        let rotation = attitude.vector
        guard rotation.x.isFinite, rotation.y.isFinite, rotation.z.isFinite, rotation.w.isFinite,
              simd_length_squared(rotation) > 0, time.isFinite else { return position }
        guard let reference, self.orientation == orientation else {
            self.reference = attitude.normalized
            self.orientation = orientation
            timestamp = time
            position = .zero
            return position
        }
        guard time > timestamp else { return position }

        // Core Motion rotation matrices map the reference frame into device axes.
        // Express the displacement of the screen normal in the calibrated device axes.
        let normal = (reference * attitude.normalized.inverse).act(SIMD3<Double>(0, 0, 1))
        let direction = orientation.screenVector(CGPoint(x: atan2(normal.x, normal.z) / Self.fullTilt,
                                                        y: atan2(normal.y, normal.z) / Self.fullTilt))
        let weight = 1 - exp(-min(time - timestamp, 0.1) / Self.response)
        position.x += (MusicStoryOrbitInput.unit(direction.x) - position.x) * weight
        position.y += (MusicStoryOrbitInput.unit(direction.y) - position.y) * weight
        timestamp = time
        return position
    }
}
#endif
