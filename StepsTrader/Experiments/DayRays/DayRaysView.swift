import SwiftUI

/// One day's fan, drawn in a single shader pass.
struct DayRaysView: View {
    let composition: DayRayComposition
    let happeningCount: Int
    let dayKey: String
    var isAnimating: Bool = true

    /// Packed once at init: the blades are a pure function of the day, so
    /// rebuilding them on every frame would be work for an identical result.
    private let packed: [Float]

    init(
        composition: DayRayComposition,
        happeningCount: Int = 5,
        dayKey: String = "",
        isAnimating: Bool = true
    ) {
        self.composition = composition
        self.happeningCount = happeningCount
        self.dayKey = dayKey
        self.isAnimating = isAnimating
        self.packed = Self.pack(
            composition.blades(happeningCount: happeningCount, dayKey: dayKey)
        )
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { timeline in
                let t = Self.shaderTime(timeline.date)
                let origin = animatedOrigin(at: t)

                Rectangle()
                    .fill(.black)
                    .colorEffect(ShaderLibrary.dayRays(
                        .float2(Float(geo.size.width), Float(geo.size.height)),
                        .float(Float(t)),
                        .float2(Float(origin.x), Float(origin.y)),
                        .float(Float(motionIndex)),
                        .float(Float(motionSpeed)),
                        .float(Float(profileIndex)),
                        .float(Float(shapeIndex)),
                        .float(Float(composition.maxLength)),
                        .color(composition.backgroundTop),
                        .color(composition.backgroundBottom),
                        .floatArray(packed)
                    ))
            }
        }
    }

    // MARK: - Motion

    /// Drift is the one law that moves the convergence point rather than the
    /// blades, so it is applied here instead of inside the shader.
    private func animatedOrigin(at t: Double) -> CGPoint {
        guard composition.motion == .drift else { return composition.originUV }
        return CGPoint(
            x: composition.originUV.x + 0.045 * sin(t * 0.11),
            y: composition.originUV.y + 0.030 * cos(t * 0.083)
        )
    }

    private var motionIndex: Int {
        switch composition.motion {
        case .rotate: 0
        case .breathe: 1
        case .wave: 2
        case .swirl: 3
        case .flicker: 4
        case .drift: 5
        case .still: 6
        }
    }

    private var motionSpeed: Double {
        switch composition.motion {
        case .rotate:  0.055
        case .breathe: 0.45
        case .wave:    0.40
        case .swirl:   0.11
        case .flicker: 0.9
        case .drift:   0
        case .still:   0
        }
    }

    /// Must match the constants in `DayRaysShader.metal`.
    private var shapeIndex: Int {
        switch composition.shape {
        case .spike:     0
        case .petal:     1
        case .trapezoid: 2
        case .slab:      3
        case .lozenge:   4
        case .comet:     5
        }
    }

    private var profileIndex: Int {
        switch composition.profile {
        case .burnout: 0
        case .direct:  1
        case .double:  2
        case .head:    3
        }
    }

    /// Wrapped before narrowing to `Float` — at ~8e8 seconds a 32-bit float
    /// quantises to tens of milliseconds and the motion visibly stutters.
    static func shaderTime(_ date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
    }

    // MARK: - Packing

    /// 12 floats per blade — must stay in step with `kRayStride` in
    /// `DayRaysShader.metal`.
    static func pack(_ blades: [RayBlade]) -> [Float] {
        var out = [Float]()
        out.reserveCapacity(blades.count * 12)
        for blade in blades {
            let rgb = hsbToRgb(h: blade.hue, s: blade.saturation, b: blade.brightness)
            out.append(Float(blade.angle))
            out.append(Float(blade.innerRadius))
            out.append(Float(blade.length))
            out.append(Float(blade.halfWidthInner))
            out.append(Float(blade.halfWidthOuter))
            out.append(Float(blade.tilt))
            out.append(blade.isDark ? 1 : 0)
            out.append(Float(blade.phase))
            out.append(Float(rgb.r))
            out.append(Float(rgb.g))
            out.append(Float(rgb.b))
            out.append(Float(blade.softness))
        }
        return out
    }

    /// Done in Swift rather than by round-tripping through `UIColor`, so the
    /// packing stays a pure function and can run off the main actor.
    static func hsbToRgb(h: Double, s: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        if s <= 0 { return (b, b, b) }
        let sector = (h - h.rounded(.down)) * 6
        let i = Int(sector)
        let f = sector - Double(i)
        let p = b * (1 - s)
        let q = b * (1 - s * f)
        let t = b * (1 - s * (1 - f))
        switch i % 6 {
        case 0: return (b, t, p)
        case 1: return (q, b, p)
        case 2: return (p, b, t)
        case 3: return (p, q, b)
        case 4: return (t, p, b)
        default: return (b, p, q)
        }
    }
}
