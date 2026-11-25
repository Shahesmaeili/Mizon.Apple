#if os(iOS)
import CoreMotion
import simd
import SwiftUI
import UIKit

@MainActor
final class MusicStoryOrbitDeviceMotion {
    private var manager: CMMotionManager?
    private weak var probe: UIView?
    private var wantsUpdates = false
    private var tilt = MusicStoryOrbitTilt()

    func setActive(_ active: Bool) {
        wantsUpdates = active
        updateSubscription()
    }

    func attach(_ view: UIView) {
        probe = view
        updateSubscription()
    }

    func detach(_ view: UIView) {
        guard probe === view else { return }
        probe = nil
        updateSubscription()
    }

    func position() -> CGPoint {
        guard let manager, manager.isDeviceMotionActive, let scene = probe?.window?.windowScene,
              scene.activationState == .foregroundActive,
              let orientation = MusicStoryOrbitOrientation(scene.effectiveGeometry.interfaceOrientation),
              let sample = manager.deviceMotion else { return .zero }
        let q = sample.attitude.quaternion
        return tilt.sample(simd_quatd(ix: q.x, iy: q.y, iz: q.z, r: q.w), orientation: orientation, at: sample.timestamp)
    }

    private func updateSubscription() {
        guard wantsUpdates, probe?.window?.windowScene?.activationState == .foregroundActive else {
            if let manager, manager.isDeviceMotionActive {
                manager.stopDeviceMotionUpdates()
                tilt = MusicStoryOrbitTilt()
            }
            return
        }
        let manager = self.manager ?? CMMotionManager()
        self.manager = manager
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = MusicStoryOrbitTilt.sampleInterval
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
    }
}

struct MusicStoryOrbitWindowProbe: UIViewRepresentable {
    let motion: MusicStoryOrbitDeviceMotion

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        view.motion = motion
        return view
    }

    func updateUIView(_ view: Probe, context: Context) {}

    static func dismantleUIView(_ view: Probe, coordinator: ()) {
        view.motion?.detach(view)
        view.motion = nil
    }

    final class Probe: UIView {
        weak var motion: MusicStoryOrbitDeviceMotion?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { motion?.attach(self) }
            else { motion?.detach(self) }
        }
    }
}

private extension MusicStoryOrbitOrientation {
    init?(_ orientation: UIInterfaceOrientation) {
        switch orientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }
}
#endif
