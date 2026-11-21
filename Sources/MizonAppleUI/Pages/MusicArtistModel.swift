#if os(macOS) || os(iOS)
import Foundation
@preconcurrency import GLTFKit2
import MizonAPIClient
import MizonAppleCore
@preconcurrency import SceneKit
import simd
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct MusicArtistModel: View {
    let artist: FeaturedPersonItem
    let model: MusicHomeViewModel
    let rotateHint: String
    let resetLabel: String
    var showsRotationHint = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private var localization = AuthLocalization()
    @State private var visible = false
    @State private var scene: ArtistPreviewScene?
    @State private var dragOrigin: simd_quatf?

    private var rest: simd_quatf {
        let yaw = artist.modelYawInDegrees.isFinite ? artist.modelYawInDegrees.truncatingRemainder(dividingBy: 360) : 0
        return simd_quatf(angle: yaw * .pi / 180, axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: -0.04, axis: SIMD3(1, 0, 0))
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let scene, visible, scenePhase == .active {
                SceneView(scene: scene.scene, pointOfView: scene.camera, options: [.autoenablesDefaultLighting])
                    .allowsHitTesting(false)
                rotationSurface(scene)
                    .accessibilityLabel(rotateHint)
                    .accessibilityAdjustableAction { direction in
                        let angle: Float = direction == .increment ? 0.22 : -0.22
                        scene.pivot.simdOrientation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
                            * scene.pivot.simdOrientation
                    }
                HStack(spacing: 5) {
                    Button { reset(scene) } label: {
                        FluentIcon(symbol: .arrowCounterclockwise, size: 12).frame(width: 28, height: 28)
                    }
                    .buttonStyle(MusicHomeButtonStyle(fill: MusicHomeStyle.inset, stroke: MusicHomeStyle.stroke, corner: 8))
                    .accessibilityLabel(resetLabel)
                    if showsRotationHint {
                        Text(rotateHint).font(localization.font(8)).foregroundStyle(MusicHomeStyle.secondary)
                            .lineLimit(1).allowsHitTesting(false)
                    }
                }
                .padding(.leading, 10)
                .padding(.bottom, 9)
            } else if visible {
                MusicArtwork(mediaID: artist.profileMediaPublicId, model: model, symbol: "person.fill")
                    .frame(width: showsRotationHint ? 118 : 96, height: showsRotationHint ? 118 : 96)
                    .clipShape(.circle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            } else {
                Color.clear
            }
        }
        .onScrollVisibilityChange(threshold: 0.15) { visible = $0 }
        .task(id: activeModelID) {
            guard scene == nil, let id = activeModelID else { return }
            do {
                let path = try await model.artwork.file(id, session: model.session, maximumBytes: 32 * 1024 * 1024)
                let decoded = try await ArtistPreviewScene.load(path)
                try Task.checkCancellation()
                scene = decoded
                decoded.configure(orientation: rest, zoom: artist.modelViewScale, verticalFocus: artist.modelVerticalFocus)
            } catch {}
        }
        .help(artist.modelAttribution ?? rotateHint)
    }

    @ViewBuilder
    private func rotationSurface(_ scene: ArtistPreviewScene) -> some View {
        let surface = Color.clear.contentShape(.rect)
        #if os(iOS)
        surface.gesture(MusicArtistPan(update: { translation in
            rotate(scene, by: translation)
        }, end: {
            if dragOrigin != nil { reset(scene) }
        }))
        #else
        surface.gesture(DragGesture(minimumDistance: 6)
            .onChanged { value in rotate(scene, by: value.translation) }
            .onEnded { _ in if dragOrigin != nil { reset(scene) } })
        #endif
    }

    private func rotate(_ scene: ArtistPreviewScene, by translation: CGSize) {
        if dragOrigin == nil { dragOrigin = scene.pivot.presentation.simdOrientation }
        guard let origin = dragOrigin else { return }
        let yaw = Float.pi * tanh(Float(translation.width) / 220)
        let pitch = 1.2 * tanh(Float(translation.height) / 160)
        scene.pivot.simdOrientation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
            * origin * simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
    }

    private var activeModelID: UUID? {
        visible && scenePhase == .active ? artist.modelMediaPublicId : nil
    }

    private func reset(_ scene: ArtistPreviewScene) {
        dragOrigin = nil
        let current = scene.pivot.presentation.simdOrientation
        scene.pivot.simdOrientation = current
        SCNTransaction.begin()
        SCNTransaction.animationDuration = reduceMotion ? 0 : 0.5
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
        scene.pivot.simdOrientation = rest
        SCNTransaction.commit()
    }
}

#if os(iOS)
private struct MusicArtistPan: UIGestureRecognizerRepresentable {
    let update: (CGSize) -> Void
    let end: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let gesture = UIPanGestureRecognizer()
        gesture.maximumNumberOfTouches = 1
        gesture.cancelsTouchesInView = false
        gesture.delegate = context.coordinator
        return gesture
    }

    func handleUIGestureRecognizerAction(_ gesture: UIPanGestureRecognizer, context: Context) {
        switch gesture.state {
        case .began, .changed:
            let offset = gesture.translation(in: gesture.view)
            update(CGSize(width: offset.x, height: offset.y))
        case .ended, .cancelled, .failed:
            end()
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let gesture = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = gesture.velocity(in: gesture.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView
        }
    }
}
#endif

private final class ArtistPreviewScene: @unchecked Sendable {
    let scene: SCNScene
    let pivot = SCNNode()
    let camera = SCNNode()

    private init(scene source: SCNScene) throws {
        scene = SCNScene()
        let mesh = SCNNode()
        for child in source.rootNode.childNodes { mesh.addChildNode(child) }
        let (minimum, maximum) = mesh.boundingBox
        let lower = SIMD3<Float>(minimum)
        let upper = SIMD3<Float>(maximum)
        let extent = upper - lower
        let dimension = max(extent.x, extent.y, extent.z)
        guard dimension.isFinite, dimension > 0.0001 else { throw LoginFailure.invalidResponse }
        let center = (upper + lower) / 2
        let scale = 2 / dimension
        mesh.simdScale = SIMD3(repeating: scale)
        mesh.simdPosition = -center * scale
        pivot.addChildNode(mesh)
        scene.rootNode.addChildNode(pivot)

        let lens = SCNCamera()
        lens.usesOrthographicProjection = true
        lens.zNear = 0.1
        lens.zFar = 30
        camera.camera = lens
        camera.simdPosition = SIMD3(0, 0, 4)
        scene.rootNode.addChildNode(camera)
    }

    @MainActor
    func configure(orientation: simd_quatf, zoom: Float, verticalFocus: Float) {
        pivot.simdOrientation = orientation
        camera.camera?.orthographicScale = 2.22 / Double(zoom.isFinite ? min(2.5, max(0.5, zoom)) : 1)
        pivot.simdPosition.y = verticalFocus.isFinite ? -min(1, max(-1, verticalFocus)) : 0
    }

    @concurrent
    static func load(_ file: URL) async throws -> ArtistPreviewScene {
        let data = try Data(contentsOf: file, options: [.mappedIfSafe])
        try validateEmbeddedGLB(data)
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            GLTFAsset.load(with: data, options: [:]) { _, status, asset, error, _ in
                switch status {
                case .error:
                    continuation.resume(throwing: error ?? LoginFailure.invalidResponse)
                case .complete:
                    do {
                        guard let asset, let scene = GLTFSCNSceneSource(asset: asset).defaultScene else {
                            throw LoginFailure.invalidResponse
                        }
                        continuation.resume(returning: try ArtistPreviewScene(scene: scene))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                default: break
                }
            }
        }
    }

    private static func validateEmbeddedGLB(_ data: Data) throws {
        guard data.count >= 20, data.count <= 32 * 1024 * 1024,
              data.prefix(4) == Data([0x67, 0x6C, 0x54, 0x46]) else { throw LoginFailure.invalidResponse }
        func number(at offset: Int) -> Int {
            Int(data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) })
        }
        let jsonLength = number(at: 12)
        guard number(at: 4) == 2, number(at: 8) == data.count, number(at: 16) == 0x4E4F534A,
              jsonLength <= min(data.count - 20, 2 * 1024 * 1024),
              let json = try JSONSerialization.jsonObject(with: data.subdata(in: 20..<(20 + jsonLength))) as? [String: Any],
              let nodes = json["nodes"] as? [[String: Any]], nodes.count <= 4096,
              (json["extensionsRequired"] as? [String] ?? []).isEmpty,
              let accessors = json["accessors"] as? [[String: Any]], accessors.count <= 8192 else {
            throw LoginFailure.invalidResponse
        }
        for key in ["images", "buffers"] {
            if (json[key] as? [[String: Any]])?.contains(where: { $0["uri"] != nil }) == true {
                throw LoginFailure.invalidResponse
            }
        }
        var vertices = 0
        for mesh in json["meshes"] as? [[String: Any]] ?? [] {
            for primitive in mesh["primitives"] as? [[String: Any]] ?? [] {
                guard let attributes = primitive["attributes"] as? [String: Int], let index = attributes["POSITION"],
                      accessors.indices.contains(index), let count = accessors[index]["count"] as? Int,
                      count >= 0, count <= 500_000 - vertices else { throw LoginFailure.invalidResponse }
                vertices += count
            }
        }
        guard vertices > 0 else { throw LoginFailure.invalidResponse }
    }
}
#endif
