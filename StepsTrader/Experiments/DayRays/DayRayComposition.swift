import SwiftUI

// ════════════════════════════════════════════════════════════════════
// MARK: - Axes
//
// The day's seed picks the rules; happenings fill them. No element ever
// chooses its own style — that is what keeps a canvas one picture.
//
// The coarse axes below (centre, scale, density, key, symmetry, layers)
// are the ones visible from arm's length: they decide the silhouette of
// the whole frame. The fine axes (blade shape, profile, colour rule,
// motion) make a day unique inside its frame.
// ════════════════════════════════════════════════════════════════════

/// Where the blades converge. Off-screen is not a variation of centred —
/// only a sector of the fan lands in frame, which is a different picture.
enum RayFanCenter: String, CaseIterable, Hashable {
    case centered, offset, offscreen
}

/// Length of the longest blade, in fractions of the short side.
enum RayFanScale: String, CaseIterable, Hashable {
    case compact, full, overflow

    /// Fractions of HALF the short side, not the whole one: on a portrait
    /// phone the horizontal half-extent is only ~0.23 of the height, so a
    /// length measured against the full short side leaves the frame long
    /// before it looks large.
    var range: ClosedRange<Double> {
        switch self {
        case .compact:  0.14...0.20
        case .full:     0.22...0.30
        case .overflow: 0.38...0.55   // clipped by the frame, on purpose
        }
    }
}

/// How many blades in total. The single most visible difference between days.
enum RayFanDensity: String, CaseIterable, Hashable {
    case sparse, medium, dense

    var range: ClosedRange<Int> {
        switch self {
        case .sparse: 3...6
        case .medium: 10...16
        case .dense:  25...40
        }
    }
}

/// Light key inverts the picture: dark blades on a pale ground.
enum RayTonalKey: String, CaseIterable, Hashable {
    case light, dark

    var darkShareRange: ClosedRange<Double> {
        switch self {
        case .light: 0.70...1.00
        case .dark:  0.00...0.35
        }
    }
}

enum RayFanSymmetry: String, CaseIterable, Hashable {
    case mirror, rotational, free
}

/// Where the blades sit along the radius.
///
/// The first version had every blade start at the convergence point, which is
/// why all fifteen days read the same: a starburst is a starburst. In the
/// references most elements are *detached* — they float in a band at some
/// distance, each with its own beginning and end, and the centre is a glow
/// rather than a place where lines meet.
enum RayFanAnchor: String, CaseIterable, Hashable {
    case converging   // classic starburst, all from the point
    case band         // floating in a ring at a shared radius
    case scattered    // each blade at its own radius
}

/// The blade's silhouette. Width is linear, not angular: an angular width
/// makes every long blade a thin wedge, and the references are full of slabs
/// and lozenges that keep their body all the way out.
enum RayBladeShape: String, CaseIterable, Hashable {
    case spike     // wide base, sharp outer point — a triangle
    case petal     // narrow at both ends, widest in the middle
    case trapezoid // wide flat outer end, narrower inward
    case slab      // even width, flat ends — a bar
    case lozenge   // short, rounded, capsule-like
    case comet     // narrow head, long fading tail
}

enum RayBrightnessProfile: String, CaseIterable, Hashable {
    case burnout  // saturated tip, washed-out core — the reference look
    case direct   // bright at the centre, fades outward
    case double   // dark middle, both ends lit
    case head     // bright head near the tip, faint tail
}

enum RayColorRule: String, CaseIterable, Hashable {
    case rotate     // hue travels around the circle
    case arc        // hue covers only part of the range
    case poles      // two opposed groups
    case byLength   // hue follows length, so colour reads as depth
    case monoAccent // one tone, one or two contrasting blades
}

enum RayMotion: String, CaseIterable, Hashable {
    case rotate, breathe, wave, swirl, flicker, drift, still
}

/// How the palette is built around the anchor hue.
enum RayHarmony: String, CaseIterable, Hashable {
    case analogous, triad, splitComplement, mono

    /// Hue offsets in degrees, relative to the anchor.
    var spread: Double {
        switch self {
        case .analogous:      70
        case .triad:          240
        case .splitComplement: 180
        case .mono:           16
        }
    }
}

// ════════════════════════════════════════════════════════════════════
// MARK: - Composition
// ════════════════════════════════════════════════════════════════════

/// One day's rules. Never persisted — a pure function of identity + day,
/// exactly like `DayComposition`, so it survives reinstalls and syncs for
/// free.
struct DayRayComposition: Equatable {
    var center: RayFanCenter
    var scale: RayFanScale
    var density: RayFanDensity
    var key: RayTonalKey
    var symmetry: RayFanSymmetry
    /// Rotational fold count; meaningful only when `symmetry == .rotational`.
    var fold: Int
    /// 1 or 2 nested fans.
    var layers: Int
    var anchor: RayFanAnchor
    var shape: RayBladeShape
    var profile: RayBrightnessProfile
    var colorRule: RayColorRule
    var motion: RayMotion
    /// Maximum lean away from radial, in radians. Non-zero turns a starburst
    /// into a shoal.
    var tilt: Double
    /// Edge softness, 0 crisp … 1 bloomy.
    var softness: Double

    var anchorHue: Double       // 0..<1
    var harmony: RayHarmony
    var darkShare: Double       // 0...1
    var originUV: CGPoint       // convergence point, may sit outside 0...1
    var maxLength: Double       // fraction of the short side
    var bladeCount: Int

    // MARK: Derivation

    /// `identity` is the stable per-person value, not the auth account id —
    /// see the seeding notes: an id that changes on sign-in would repaint
    /// every past day.
    static func forDay(dayKey: String, identity: String = "local") -> DayRayComposition {
        let seed = CanvasElement.makeSeed(
            optionId: "dayRays:\(identity)", dayKey: dayKey, index: 0
        )

        func pick<T>(_ options: [T], _ domain: StaticString) -> T {
            var rng = SeededRNG.derived(from: seed, domain: domain)
            return options[rng.nextInt(in: 0...(options.count - 1))]
        }
        func value(_ range: ClosedRange<Double>, _ domain: StaticString) -> Double {
            var rng = SeededRNG.derived(from: seed, domain: domain)
            return rng.nextDouble(in: range)
        }

        let center = pick(RayFanCenter.allCases, "center")
        var scale = pick(RayFanScale.allCases, "scale")
        // A convergence point outside the frame only shows up if the blades
        // are long enough to reach back in. Compact plus off-screen renders
        // an empty picture — the one outcome the generator must never ship.
        if center == .offscreen { scale = .overflow }
        let density = pick(RayFanDensity.allCases, "density")
        let key = pick(RayTonalKey.allCases, "key")
        let symmetry = pick(RayFanSymmetry.allCases, "symmetry")
        let fold = pick([3, 4, 5, 6, 8], "fold")
        let layers = pick([1, 1, 2], "layers")   // two fans are the exception
        let anchor = pick(RayFanAnchor.allCases, "anchor")
        let shape = pick(RayBladeShape.allCases, "shape")
        let profile = pick(RayBrightnessProfile.allCases, "profile")
        let colorRule = pick(RayColorRule.allCases, "colorRule")
        let motion = pick(RayMotion.allCases, "motion")
        let harmony = pick(RayHarmony.allCases, "harmony")

        var countRng = SeededRNG.derived(from: seed, domain: "bladeCount")
        let bladeCount = countRng.nextInt(in: density.range)

        var originRng = SeededRNG.derived(from: seed, domain: "origin")
        let origin: CGPoint = switch center {
        case .centered:
            // Optical centre, not geometric — a fan pinned to 0.5 sags.
            CGPoint(x: 0.5, y: 0.42)
        case .offset:
            CGPoint(
                x: 0.5 + originRng.nextDouble(in: -0.32...0.32),
                y: 0.42 + originRng.nextDouble(in: -0.26...0.26)
            )
        case .offscreen:
            {
                let angle = originRng.nextDouble(in: 0...(2 * .pi))
                let push = originRng.nextDouble(in: 1.02...1.22)
                return CGPoint(
                    x: 0.5 + cos(angle) * 0.5 * push,
                    y: 0.5 + sin(angle) * 0.5 * push
                )
            }()
        }

        let raw = DayRayComposition(
            center: center,
            scale: scale,
            density: density,
            key: key,
            symmetry: symmetry,
            fold: fold,
            layers: layers,
            anchor: anchor,
            shape: shape,
            profile: profile,
            colorRule: colorRule,
            motion: motion,
            tilt: value(0...0.55, "tilt"),
            softness: value(0.25...0.9, "softness"),
            anchorHue: value(0...1, "hue"),
            harmony: harmony,
            darkShare: value(key.darkShareRange, "darkShare"),
            originUV: origin,
            maxLength: value(scale.range, "length"),
            bladeCount: bladeCount
        )
        return raw.sanitized()
    }

    /// Pairs that cancel each other out. Expressed as an explicit list rather
    /// than as weights: the conflicts are categorical, and a weight that makes
    /// them merely unlikely still ships the broken frame eventually.
    func sanitized() -> DayRayComposition {
        var c = self

        // A ring of blades smears into a disc once it starts swirling.
        if c.motion == .swirl && c.anchor == .band { c.motion = .rotate }
        // Rotational symmetry is invisible when only a sector is in frame,
        // and it costs blades to build.
        if c.center == .offscreen && c.symmetry == .rotational { c.symmetry = .free }
        // These shapes exist to move; frozen they read as a rendering bug.
        if c.motion == .still && c.shape == .comet { c.motion = .breathe }
        // One tone + mostly silhouettes + a full frame collapses to grey mush.
        if c.colorRule == .monoAccent && c.key == .light && c.density == .dense {
            c.darkShare = min(c.darkShare, 0.55)
        }
        // Two fans at forty blades is simply too much.
        if c.layers == 2 && c.density == .dense { c.layers = 1 }

        return c
    }

    /// How far the blades sit from the convergence point, as a fraction of
    /// the fan's reach. A converging day keeps the classic starburst; the
    /// other two detach the blades so the centre becomes a glow rather than a
    /// junction — which is what the references actually do.
    var bandOffsetRange: ClosedRange<Double> {
        switch anchor {
        case .converging: 0.0...0.06
        case .band:       0.45...0.62
        case .scattered:  0.05...0.70
        }
    }

    // MARK: Palette

    /// Hue for a blade at normalised position `t` (angle or length, per rule).
    func hue(at t: Double, index: Int) -> Double {
        let spread = harmony.spread / 360.0
        switch colorRule {
        case .rotate:   return wrap(anchorHue + t * max(spread, 0.75))
        case .arc:      return wrap(anchorHue + t * spread * 0.35)
        case .poles:    return wrap(anchorHue + (t < 0.5 ? 0 : spread * 0.5))
        case .byLength: return wrap(anchorHue + t * spread * 0.6)
        case .monoAccent:
            return index % 7 == 3 ? wrap(anchorHue + 0.5) : wrap(anchorHue + t * 0.04)
        }
    }

    var backgroundTop: Color {
        switch key {
        case .light: Color(hue: wrap(anchorHue + 0.08), saturation: 0.14, brightness: 0.94)
        case .dark:  Color(hue: wrap(anchorHue + 0.08), saturation: 0.55, brightness: 0.16)
        }
    }

    var backgroundBottom: Color {
        switch key {
        case .light: Color(hue: wrap(anchorHue - 0.06), saturation: 0.22, brightness: 0.80)
        case .dark:  Color(hue: wrap(anchorHue - 0.06), saturation: 0.70, brightness: 0.06)
        }
    }

    private func wrap(_ h: Double) -> Double {
        let x = h.truncatingRemainder(dividingBy: 1)
        return x < 0 ? x + 1 : x
    }

    /// Short human-readable summary, for the lab's readout.
    var summary: String {
        "\(center.rawValue) · \(scale.rawValue) · \(density.rawValue)(\(bladeCount)) · \(key.rawValue) · "
        + "\(symmetry == .rotational ? "rot\(fold)" : symmetry.rawValue) · L\(layers) · "
        + "\(anchor.rawValue) · \(shape.rawValue) · \(profile.rawValue) · "
        + "\(colorRule.rawValue) · \(motion.rawValue)"
    }
}

// ════════════════════════════════════════════════════════════════════
// MARK: - Blades
// ════════════════════════════════════════════════════════════════════

/// One resolved blade, ready for the shader.
struct RayBlade: Equatable {
    /// Direction from the convergence point to where the blade sits.
    var angle: Double
    /// Distance from the convergence point to the blade's inner end.
    var innerRadius: Double
    var length: Double
    /// Half-widths in the same units as `length` — linear, so a long blade
    /// keeps its body instead of fanning into a wedge.
    var halfWidthInner: Double
    var halfWidthOuter: Double
    /// Lean away from radial, in radians.
    var tilt: Double
    var isDark: Bool
    var phase: Double
    var hue: Double
    var saturation: Double
    var brightness: Double
    /// 0 crisp … 1 bloomy.
    var softness: Double
}

extension DayRayComposition {

    /// Blades for a day. `happeningCount` decides how the total is grouped:
    /// each happening opens into a bundle, so a day with three things logged
    /// reads as three gestures rather than as N unrelated spokes.
    ///
    /// The total itself comes from the day's density, not from the count —
    /// otherwise how diligently someone journals would decide how full the
    /// picture looks.
    func blades(happeningCount: Int, dayKey: String = "") -> [RayBlade] {
        let seed = CanvasElement.makeSeed(optionId: "dayRays:blades", dayKey: dayKey, index: bladeCount)
        var rng = SeededRNG.derived(from: seed, domain: "blades")

        let bundles = max(1, min(happeningCount, bladeCount))
        let perBundle = Int(ceil(Double(bladeCount) / Double(bundles)))
        let baseAngles = bundleAngles(count: bundles)

        var result = [RayBlade]()
        result.reserveCapacity(bladeCount)

        for index in 0..<bladeCount {
            let bundle = index / perBundle
            let withinBundle = index % perBundle
            let base = baseAngles[min(bundle, baseAngles.count - 1)]

            // Blades inside one bundle fan out slightly: a feather at a narrow
            // spread, a comb at a wide one.
            let spread = rng.nextDouble(in: 0.02...0.12)
            let offset = perBundle > 1
                ? (Double(withinBundle) - Double(perBundle - 1) / 2) * spread
                : 0
            let jitter = symmetry == .free ? rng.nextDouble(in: -0.10...0.10) : 0

            let layerScale = (layers == 2 && index % 3 == 0) ? 0.45 : 1.0
            // Lengths vary far more than before. Uniform lengths were half of
            // why every day looked like the same starburst.
            let lengthJitter = rng.nextDouble(in: 0.35...1.0)
            let length = maxLength * layerScale * lengthJitter

            let bandOffset = rng.nextDouble(in: bandOffsetRange)
            let widths = silhouette(length: length, rng: &rng)
            // Hue steps per BUNDLE, not per blade. Ramping smoothly across
            // thirty blades gives thirty neighbouring hues — which reads as one
            // colour. The references put contrasting colours side by side, and
            // a bundle is the natural unit for that: one happening, one colour.
            let bundleT = Double(bundle) / Double(max(bundles - 1, 1))
            let hueT = colorRule == .byLength ? lengthJitter : bundleT

            result.append(
                RayBlade(
                    angle: base + offset + jitter,
                    innerRadius: maxLength * bandOffset,
                    length: length,
                    halfWidthInner: widths.inner,
                    halfWidthOuter: widths.outer,
                    tilt: tilt * rng.nextDouble(in: -1...1),
                    isDark: rng.nextDouble() < darkShare,
                    phase: rng.nextDouble(),
                    hue: hue(at: hueT, index: index),
                    saturation: key == .light ? 0.62 : 0.85,
                    brightness: key == .light ? 0.32 : 0.95,
                    softness: softness * rng.nextDouble(in: 0.6...1.0)
                )
            )
        }
        return result
    }

    /// Where each bundle points, honouring the day's symmetry.
    private func bundleAngles(count: Int) -> [Double] {
        let full = 2 * Double.pi
        switch symmetry {
        case .rotational:
            // Build one wedge, then repeat it — that is what makes the
            // repetition legible as symmetry rather than as coincidence.
            let wedge = full / Double(fold)
            let perWedge = max(1, Int(ceil(Double(count) / Double(fold))))
            var angles = [Double]()
            for repeatIndex in 0..<fold {
                for slot in 0..<perWedge {
                    angles.append(Double(repeatIndex) * wedge
                                  + wedge * (Double(slot) + 0.5) / Double(perWedge))
                }
            }
            return Array(angles.prefix(max(count, 1)))

        case .mirror:
            let half = max(1, count / 2 + count % 2)
            var angles = [Double]()
            for i in 0..<half {
                let a = Double.pi * (Double(i) + 0.5) / Double(half)
                angles.append(a)
                angles.append(-a)
            }
            return Array(angles.prefix(max(count, 1)))

        case .free:
            return (0..<max(count, 1)).map { full * (Double($0) + 0.5) / Double(max(count, 1)) }
        }
    }

    /// Half-widths at the inner and outer ends, in length units. The ratio
    /// between them is the silhouette: equal makes a bar, zero at the tip
    /// makes a spike, wider at the tip makes a trapezoid.
    private func silhouette(length: Double, rng: inout SeededRNG) -> (inner: Double, outer: Double) {
        // Proportional to the blade's own length, so short blades are chunky
        // lozenges and long ones are still substantial.
        let body = length * rng.nextDouble(in: 0.10...0.30)
        switch shape {
        case .spike:     return (body * 1.35, body * 0.04)
        case .petal:     return (body * 0.18, body * 0.10)   // waist handled by the profile
        case .trapezoid: return (body * 0.45, body * 1.25)
        case .slab:      return (body, body)
        case .lozenge:   return (body * 0.85, body * 0.85)
        case .comet:     return (body * 0.30, body * 1.05)
        }
    }
}
