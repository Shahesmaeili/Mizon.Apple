import SwiftUI
import ImageIO

/// DevWinUI's Random.Create retries a rejected value at most FIVE times;
/// its predicate means regenerate, not accept. Keeping that distinction matters.
struct DevRandom {
    var state: UInt64
    mutating func next(_ min: Int, _ max: Int, reject: (Int) -> Bool = { _ in false }) -> Double {
        func draw(_ state: inout UInt64) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return min + Int((state >> 32) % UInt64(max - min))
        }
        var value = draw(&state)
        for _ in 0..<5 {
            if !reject(value) { break }
            value = draw(&state)
        }
        return Double(value)
    }
}
struct DevStar {
    let x, y, z, diameter, duration, deltaZ, minOpacity, maxOpacity, opacityDuration: Double
    let movementSeed: UInt64
    init(big: Bool, random: inout DevRandom) {
        z = random.next(big ? -240 : -160, big ? 0 : 160)
        diameter = big ? random.next(3, 5, reject: { $0 > 4 }) : random.next(1, 3)
        // Normalized coordinates are expanded to the centered 1.2x window square.
        x = random.next(-1_000_000, 1_000_000) / 1_000_000
        y = random.next(-1_000_000, 1_000_000) / 1_000_000
        deltaZ = big ? random.next(240, 400, reject: { $0 > 320 }) : 0
        duration = (big ? random.next(10_000, 40_000, reject: { $0 < 20_000 }) : random.next(40_000, 80_000)) / 1000
        minOpacity = big ? 0 : random.next(0, 60, reject: { $0 < 40 }) / 100
        maxOpacity = (big ? random.next(60, 100) : random.next(60, 100, reject: { $0 > 70 })) / 100
        opacityDuration = (big ? random.next(500, 1000) : random.next(250, 500)) / 1000
        movementSeed = random.state
        _ = random.next(0, Int.max / 2)
    }
    func sample(time: Double) -> (dx: Double, dy: Double, z: Double, opacity: Double) {
        let cycles = Int(time / duration)
        let progress = devEase(time / duration - Double(cycles))
        var random = DevRandom(state: movementSeed)
        var dx = 0.0, dy = 0.0
        for cycle in 0...cycles {
            let fraction = cycle == cycles ? progress : 1
            dx += random.next(-12, 12) * fraction
            dy += random.next(-12, 12) * fraction
        }
        let opacityProgress = deltaZ == 0
            ? (time / opacityDuration).truncatingRemainder(dividingBy: 1)
            : min(1, time / opacityDuration)
        return (dx, dy, z + deltaZ * (Double(cycles) + progress), minOpacity + (maxOpacity - minOpacity) * devEase(opacityProgress))
    }
}
/// Composition's default cubic easing, control points (0.5,0), (0.5,1).
func devEase(_ t: Double) -> Double {
    let t = max(0, min(1, t))
    if t == 0 || t == 1 { return t }
    var lower = 0.0, upper = 1.0
    for _ in 0..<14 {
        let u = (lower + upper) / 2
        let x = 1.5 * u * (1 - u) * (1 - u) + 1.5 * u * u * (1 - u) + u * u * u
        if x < t { lower = u } else { upper = u }
    }
    let u = (lower + upper) / 2
    return 3 * u * u - 2 * u * u * u
}
struct Starfield: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var stars: [DevStar] = {
        var random = DevRandom(state: UInt64.random(in: 1...UInt64.max))
        return (0..<2003).map { DevStar(big: $0 >= 1002, random: &random) }
    }()
    private static let mask: CGImage? = {
        guard let url = Bundle.module.url(forResource: "CircleMask", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                let t = reduceMotion ? 1.6 : max(0, timeline.date.timeIntervalSince(start))
                let startup = devEase(min(1, t / 1.6))
                let skyScale = 0.8 + 0.2 * startup
                let radius = max(size.width, size.height) * 1.2 / 2
                guard let mask = Self.mask else { return }
                let image = context.resolve(Image(decorative: mask, scale: 1))
                for star in stars {
                    let sample = star.sample(time: t)
                    // PerspectiveTransform3D default depth: 1000. Preserve cumulative Z.
                    guard sample.z < 999 else { continue }
                    let perspective = 1000 / (1000 - sample.z)
                    let x = size.width / 2 + (star.x * radius + sample.dx) * perspective * skyScale
                    let y = size.height / 2 + (star.y * radius + sample.dy) * perspective * skyScale
                    let diameter = star.diameter * perspective * skyScale
                    guard x > -diameter, y > -diameter, x < size.width, y < size.height else { continue }
                    context.opacity = startup * sample.opacity
                    context.draw(image, in: CGRect(x: x, y: y, width: diameter, height: diameter))
                }
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}
struct LoginBackdrop: View {
    var body: some View { ZStack { WindowGlass(); Starfield() }.ignoresSafeArea() }
}
