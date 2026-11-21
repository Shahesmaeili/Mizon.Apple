#if os(macOS) || os(iOS)
import CoreText
import SwiftUI

struct MusicStoryOrbit: View {
    private struct Card {
        let asset: String
        let title: String
        let rating: String
        let accent: Color
        let photo: Path
        let paper: Path
        let imageBounds: CGRect
        let edition: CGPoint
        let badge: CGPoint
        let heading: CGPoint
        let typeSizes: (CGFloat, CGFloat)
        let angles: (Double, Double, Double)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var pointer: CGPoint?

    private static let typeface: String = {
        guard let url = Bundle.module.url(forResource: "BodoniModa", withExtension: "ttf"),
              let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider),
              let name = font.postScriptName else { return "Georgia" }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return name as String
    }()

    var body: some View {
        let animating = visible && !reduceMotion && scenePhase == .active
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animating)) { time in
            Canvas { context, size in
                var context = context
                let scale = size.width / 1440
                context.scaleBy(x: scale, y: scale)
                let elapsed = animating ? time.date.timeIntervalSinceReferenceDate : nil
                let hover = animating ? pointer.map { CGPoint(x: $0.x / scale, y: $0.y / scale) } : nil
                for (index, card) in Self.cards.enumerated() {
                    draw(card, index: index, context: context, elapsed: elapsed, pointer: hover)
                }
            }
        }
        .aspectRatio(1440 / 560.0, contentMode: .fit)
        .frame(maxWidth: 1130)
        .frame(maxWidth: .infinity)
        .onScrollVisibilityChange(threshold: 0.1) { visible = $0 }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): pointer = location
            case .ended: pointer = nil
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    private func draw(_ card: Card, index: Int, context: GraphicsContext, elapsed: Double?, pointer: CGPoint?) {
        let direction = index == 1 ? -1.0 : 1.0
        let phase = Double(index) * 113
        let center = CGPoint(x: 260 + 440 * index, y: index == 1 ? 302 : 248)
        let influence = pointer.flatMap { point -> CGPoint? in
            guard abs(point.x - center.x) < 225 else { return nil }
            return CGPoint(x: (point.x - center.x) / 225, y: min(1, max(-1, (point.y - center.y) / 210)))
        } ?? .zero

        func layer(period: Double, phase offset: Double = 0, x: Double, y: Double,
                   pointerX: Double = 0, pointerY: Double = 0) -> GraphicsContext {
            let angle = elapsed.map { $0.truncatingRemainder(dividingBy: period) / period * 2 * .pi
                + (phase + offset) * .pi / 180 }
            var layer = context
            layer.translateBy(x: (angle.map { sin($0) * x } ?? 0) + influence.x * pointerX,
                              y: (angle.map { sin($0) * y } ?? 0) + influence.y * pointerY)
            return layer
        }

        let paper = layer(period: 31 + Double(index) * 2.5, phase: 71, x: -3 * direction, y: 3,
                          pointerX: -4, pointerY: -3)
        paper.drawLayer { shadow in
            var shadow = shadow
            shadow.addFilter(.shadow(color: card.accent.opacity(0.20), radius: 42, y: 24))
            shadow.fill(card.paper, with: .color(card.accent.opacity(0.18)))
        }
        paper.stroke(card.paper, with: .color(card.accent.opacity(index == 1 ? 0.16 : 0.48)), lineWidth: 1.6)

        var photo = layer(period: 23 + Double(index) * 2.3, x: 4 * direction, y: -4, pointerX: 10, pointerY: 7)
        photo.clip(to: card.photo)
        photo.fill(card.photo, with: .color(card.accent))
        let image = photo.resolve(Image(card.asset, bundle: .module))
        let bounds = card.imageBounds
        if image.size.width > 0, image.size.height > 0 {
            let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
            let width = image.size.width * scale
            let height = image.size.height * scale
            photo.draw(image, in: CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2,
                                        width: width, height: height))
        }

        var year = layer(period: 26 + Double(index) * 1.3, phase: 43, x: -5, y: 5 * direction, pointerX: -14, pointerY: -10)
        year.translateBy(x: card.edition.x, y: card.edition.y)
        year.rotate(by: .degrees(card.angles.0))
        year.draw(Text(String(22 + index)).font(.custom(Self.typeface, fixedSize: card.typeSizes.0))
            .foregroundStyle(index == 1 ? musicColor("90B5FF") : card.accent), at: .zero, anchor: .topLeading)

        var rating = layer(period: 21 + Double(index) * 2.1, phase: 173, x: 5 * direction, y: -5, pointerX: 18, pointerY: -12)
        rating.translateBy(x: card.badge.x, y: card.badge.y)
        rating.rotate(by: .degrees(card.angles.1 + influence.x * 7))
        rating.draw(Text(card.rating).font(.system(size: 12)).foregroundStyle(.primary), at: CGPoint(x: 29, y: 6))
        rating.fill(Path(ellipseIn: CGRect(x: 9, y: 28, width: 40, height: 40)), with: .color(.black))
        rating.draw(rating.resolve(Image(systemName: "star.fill").symbolRenderingMode(.monochrome)),
                    in: CGRect(x: 21, y: 40, width: 16, height: 16))

        var title = layer(period: 25 + Double(index) * 1.8, phase: 283, x: -3 * direction, y: 3, pointerX: 12, pointerY: 6)
        title.translateBy(x: card.heading.x, y: card.heading.y)
        title.rotate(by: .degrees(card.angles.2))
        title.draw(Text(card.title).font(.custom(Self.typeface, fixedSize: card.typeSizes.1)),
                   at: .zero, anchor: .topLeading)
    }

    private static func orbitPath(_ coordinates: [(CGFloat, CGFloat)]) -> Path {
        let points = coordinates.map { CGPoint(x: $0.0 - 80, y: $0.1 - 320) }
        return Path { path in
            path.move(to: points[0])
            for index in stride(from: 1, to: points.count, by: 3) {
                path.addCurve(to: points[index + 2], control1: points[index], control2: points[index + 1])
            }
            path.closeSubpath()
        }
    }

    private static let cards: [Card] = [
        .init(asset: "orbit-models", title: "Models", rating: "5,0", accent: musicColor("A3AA94"),
              photo: leftPhoto, paper: leftOutline, imageBounds: CGRect(x: 90, y: 77, width: 340, height: 340),
              edition: CGPoint(x: 307, y: 28), badge: CGPoint(x: 138, y: 87), heading: CGPoint(x: 110, y: 330),
              typeSizes: (64, 84), angles: (8, -13, -10)),
        .init(asset: "orbit-illustration", title: "Illustration", rating: "4,5", accent: musicColor("0058F5"),
              photo: middlePhoto, paper: middleOutline, imageBounds: CGRect(x: 388.25, y: 109.33, width: 714.54, height: 1021.18),
              edition: CGPoint(x: 556, y: 163), badge: CGPoint(x: 792, y: 161), heading: CGPoint(x: 592, y: 350),
              typeSizes: (84, 56), angles: (-13, 15, 0)),
        .init(asset: "orbit-team", title: "Team", rating: "4,8", accent: musicColor("F4C240"),
              photo: rightPhoto, paper: rightOutline, imageBounds: CGRect(x: 1029.03, y: 73.06, width: 300.62, height: 393.72),
              edition: CGPoint(x: 1302, y: 123), badge: CGPoint(x: 1288, y: 230), heading: CGPoint(x: 1031, y: 321),
              typeSizes: (70, 74), angles: (84, -10, 0))
    ]
}

// Bézier coordinates from Mizon.Windows/Common/StoryOrbitGeometry.cs.
private extension MusicStoryOrbit {
    static let leftPhoto = orbitPath([
        (392, 415.5), (410.679, 415.5), (426.945, 417.454),
        (442, 430), (470.801, 454.001), (491.235, 563.139),
        (494, 600), (495.889, 625.19), (499.51, 684.11),
        (458, 680.5), (428.345, 677.921), (399.546, 667.432),
        (370, 663), (329.897, 656.985), (290.417, 654.684),
        (250, 653), (230.967, 652.207), (199.982, 654.883),
        (187, 636), (180.938, 627.183), (198.4, 606.545),
        (202, 600), (206.753, 591.358), (209, 579.81),
        (209, 570), (209, 543.432), (187.373, 516.51),
        (194, 490), (197.836, 474.656), (211.575, 466.393),
        (225, 460), (276.828, 435.32), (333.919, 415.5),
        (392, 415.5),
    ])
    static let leftOutline = orbitPath([
        (392, 415.5), (412.7, 413.775), (431.794, 416.495),
        (448, 430), (479.866, 456.555), (502.918, 568.365),
        (505, 610), (506.512, 640.242), (514.333, 685.867),
        (479, 700), (466.961, 704.816), (423.323, 691.998),
        (410, 689), (360.648, 677.896), (310.391, 674.84),
        (260, 674), (234.714, 673.579), (203.478, 676.522),
        (182, 660), (162.161, 644.739), (196.358, 606.417),
        (198, 590), (200.988, 560.12), (172.883, 514.703),
        (184, 490), (193.506, 468.876), (228.463, 460.179),
        (247, 454), (293.991, 438.336), (342.274, 419.644),
        (392, 415.5),
    ])
    static let middlePhoto = orbitPath([
        (756, 504), (796.159, 504.359), (837.341, 508.285),
        (876, 520), (894.071, 525.476), (911.644, 532.562),
        (929, 540), (979.842, 561.789), (1005.206, 616.937),
        (949, 650), (935.374, 658.015), (918.947, 665.027),
        (905, 672), (842.69, 703.155), (781.31, 737.915),
        (710, 739.5), (641.95, 741.012), (647.267, 714.653),
        (650, 660), (651.011, 639.782), (650.505, 620.202),
        (650, 600), (649.651, 586.028), (646.384, 518.094),
        (665, 510), (666.792, 509.221), (747.676, 503.926),
        (756, 504),
    ])
    static let middleOutline = orbitPath([
        (720, 510), (772.093, 507.395), (782.055, 505.735),
        (835, 515), (855.23, 518.54), (875.38, 522.932),
        (895, 529), (925.858, 538.544), (926.88, 543.694),
        (951, 555), (955.204, 556.971), (960.111, 557.464),
        (964, 560), (968.406, 562.874), (978.854, 575.505),
        (982, 580), (1004.237, 611.767), (994.504, 639.952),
        (963, 660), (936.55, 676.832), (907.425, 688.141),
        (879, 701), (824.087, 725.842), (771.66, 755.917),
        (710, 759), (686.46, 760.177), (650.012, 763.095),
        (635, 740), (625.766, 725.794), (631.231, 705.377),
        (632, 690), (633.829, 653.422), (634.832, 616.638),
        (633, 580), (632.164, 563.288), (629.324, 544.011),
        (641, 530), (655.58, 512.504), (698.779, 511.061),
        (720, 510),
    ])
    static let rightPhoto = orbitPath([
        (1260, 416.5), (1334.605, 419.073), (1297.715, 484.922),
        (1318, 530), (1325.262, 546.137), (1340.838, 561.408),
        (1356, 570), (1361.065, 572.87), (1366.525, 575.023),
        (1372, 577), (1378.546, 579.364), (1387.078, 578.078),
        (1392, 583), (1403.021, 594.021), (1389.052, 628.997),
        (1383, 640), (1357.321, 686.689), (1314.952, 715.5),
        (1260, 715.5), (1181.689, 715.5), (1163.115, 663.717),
        (1144, 600), (1118.655, 515.518), (1122.794, 444.605),
        (1225, 420), (1232.098, 418.291), (1250.853, 416.185),
        (1260, 416.5),
    ])
    static let rightOutline = orbitPath([
        (1260, 399), (1336.571, 404.743), (1291.788, 484.407),
        (1314, 530), (1325.405, 553.41), (1354.394, 569.725),
        (1377, 580), (1386.309, 584.231), (1397.531, 584.271),
        (1406, 590), (1420.435, 599.765), (1396.584, 648.028),
        (1390, 660), (1359.519, 715.42), (1302.318, 742.674),
        (1240, 738), (1155.579, 731.668), (1135.956, 671.823),
        (1118, 600), (1114.656, 586.622), (1109.705, 573.526),
        (1107, 560), (1092.561, 487.807), (1124.586, 424.282),
        (1200, 406), (1218.563, 401.5), (1240.806, 397.56),
        (1260, 399),
    ])
}
#endif
