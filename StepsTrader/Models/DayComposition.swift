import CoreGraphics
import Foundation

// MARK: - Archetype

/// The spatial schema of a canvas: where mass goes and how sizes relate.
///
/// This is what makes days differ. Randomising per-element parameters produces
/// numerically vast but perceptually identical output — every canvas ends up
/// the same kind of picture with different numbers. Varying the schema itself
/// is what produces structurally different work.
enum CompositionArchetype: String, Codable, CaseIterable, Hashable {
    case centeredMass    // one dominant form, satellites around it
    case diagonalSweep   // mass along a diagonal, two empty corners
    case horizonBand     // mass along a horizontal band, large empty above/below
    case cornerWeight    // weight in one corner, a long empty diagonal
    case twoMasses       // two groups in tension, emptiness between
    case constellation   // even scatter — one option among six, not the default

    /// Placement preference in `0...1` at a normalised canvas point. Handed
    /// straight to `PoissonDiscSampler` as its weight field.
    func weight(at point: CGPoint) -> Double {
        let x = Double(point.x)
        let y = Double(point.y)

        switch self {
        case .centeredMass:
            let d = hypot(x - 0.5, y - 0.5) / 0.707
            return clamp(1.0 - pow(d, 1.4))

        case .diagonalSweep:
            // Distance from the leading diagonal y = x.
            let d = abs(x - y) / 1.414
            return clamp(1.0 - pow(d / 0.42, 1.6))

        case .horizonBand:
            // A band slightly below centre reads better than dead middle.
            let d = abs(y - 0.58) / 0.30
            return clamp(1.0 - pow(d, 1.8))

        case .cornerWeight:
            let d = hypot(x - 0.18, y - 0.20) / 0.62
            return clamp(1.0 - pow(d, 1.1))

        case .twoMasses:
            let a = hypot(x - 0.30, y - 0.34) / 0.34
            let b = hypot(x - 0.72, y - 0.68) / 0.30
            return clamp(max(1.0 - pow(a, 1.5), 1.0 - pow(b, 1.5)))

        case .constellation:
            return 1.0
        }
    }

    /// Size multiplier by arrival order. Each archetype has its own curve —
    /// a centred mass has one dominant form, a constellation has peers.
    func sizeMultiplier(rank: Int, count: Int) -> Double {
        let total = max(1, count)
        // Clamped: a rank beyond `count - 1` (the caller passes a nominal day
        // length, not the running total, so this happens routinely once a day
        // has more than `nominalDayCount` elements) would otherwise push
        // `position` past 1 — and `cornerWeight`'s `pow(1 - position, 2.2)`
        // on a negative base returns NaN.
        let position = min(1, max(0,
            Double(rank) / Double(max(1, total - 1))))   // 0…1

        switch self {
        case .centeredMass:
            // Steep: the first form leads, everything else is a satellite.
            return rank == 0 ? 1.75 : 0.62 + (1 - position) * 0.18

        case .diagonalSweep:
            // Graded along the sweep.
            return 1.35 - position * 0.65

        case .horizonBand:
            // Even along the band, with a couple of taller accents.
            return rank.isMultiple(of: 3) ? 1.25 : 0.85

        case .cornerWeight:
            // Convex decay, not a second straight ramp: mass piles at the
            // anchor and thins fast along the diagonal, distinct in shape
            // from diagonalSweep's linear slope even though both start high
            // and end low.
            return 0.55 + 1.05 * pow(1 - position, 2.2)

        case .twoMasses:
            // Two leads, one per mass.
            return rank < 2 ? 1.45 : 0.70

        case .constellation:
            // Peers: a narrow spread is the point.
            return 1.05 - position * 0.25
        }
    }

    private func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
}

// MARK: - Contrast

/// How wide the day's opacity spread is. A low-key day is quiet and close in
/// value; a high-key day has strong darks and lights.
enum ContrastKey: String, Codable, CaseIterable, Hashable {
    case low, mid, high
}

// MARK: - Texture policy

/// Which fills a day uses. One dominant fill gives the canvas a signature; a
/// minority accent keeps it from being monotonous.
struct TexturePolicy: Codable, Hashable {
    var dominant: TextureKind
    var accent: TextureKind
    /// Fraction of elements that get the accent, `0...1`.
    var accentShare: Double

    init(dominant: TextureKind, accent: TextureKind, accentShare: Double) {
        self.dominant = dominant
        self.accent = accent
        // Capped at 0.45, not 1: kind(forRank:)'s stride is
        // max(2, round(1/accentShare)), which floors at a stride of 2 (i.e.
        // 50% accent) once accentShare reaches 0.5. Above that the accent
        // would tie or overtake the dominant, breaking the "dominant must
        // dominate" invariant the type implies.
        self.accentShare = min(max(accentShare, 0), 0.45)
    }

    /// Every figure in a day shares one fill style, so the canvas reads as one
    /// painting rather than a collection of independently styled objects.
    func kind(forRank rank: Int) -> TextureKind {
        dominant
    }
}

// MARK: - Composition

/// One composition per day, derived from the day. Never persisted — it is a
/// pure function of `dayKey`, so it survives reinstalls and syncs for free.
struct DayComposition: Codable, Hashable {
    var archetype: CompositionArchetype
    /// 3–5 hex colours, drawn from one region of the palette.
    var palette: [String]
    var contrastKey: ContrastKey
    var texturePolicy: TexturePolicy
    var hatchAngle: Double

    /// The size curves grade a day's elements from anchor to accent, so they need
    /// a projected day length to normalise against — not the count so far, which
    /// would put every new element at the end of its own curve. Ten matches the
    /// configured happening palette, which admits one addition per happening per day.
    static let nominalDayCount = 10

    /// The day's identity. `happeningCount` is accepted so density decisions
    /// can respond to how full the day is, but archetype, palette and contrast
    /// deliberately ignore it: adding a happening must grow the picture, not
    /// restart it.
    ///
    /// Future hook: sleep and step fractions belong here too — a quiet day
    /// choosing a low-key, sparse composition is what would make the canvas a
    /// portrait of the day rather than decoration. Left out of this task so it
    /// stays testable without HealthKit.
    static func forDay(
        dayKey: String,
        happeningCount: Int,
        allowedTextureKinds: [TextureKind] = TextureKind.allowedByUser
    ) -> DayComposition {
        let seed = CanvasElement.makeSeed(optionId: "composition", dayKey: dayKey, index: 0)

        var archetypeRng = SeededRNG.derived(from: seed, domain: "archetype")
        let archetypes = CompositionArchetype.allCases   // CaseIterable order is stable
        let archetype = archetypes[archetypeRng.nextInt(in: 0...(archetypes.count - 1))]

        var contrastRng = SeededRNG.derived(from: seed, domain: "contrast")
        let keys = ContrastKey.allCases
        let contrastKey = keys[contrastRng.nextInt(in: 0...(keys.count - 1))]

        return DayComposition(
            archetype: archetype,
            palette: makePalette(seed: seed),
            contrastKey: contrastKey,
            texturePolicy: makeTexturePolicy(seed: seed, allowedKinds: allowedTextureKinds),
            hatchAngle: makeHatchAngle(seed: seed)
        )
    }

    /// The colour for an element by arrival order. Cycling a small palette is
    /// what makes a canvas read as one work — independent sampling from all 29
    /// swatches is a sample, not a palette.
    func color(forRank rank: Int) -> String {
        palette[rank % palette.count]
    }

    /// Opacity range for an element, widened or narrowed by the contrast key.
    /// Early elements sit at the top of the range so the composition has
    /// something to read at a glance.
    func opacityRange(forRank rank: Int) -> ClosedRange<Double> {
        let spread: Double = switch contrastKey {
        case .low:  0.12
        case .mid:  0.26
        case .high: 0.42
        }
        let lead = rank < 2 ? 0.14 : 0.0
        let center = min(0.62, 0.30 + lead)
        return max(0.08, center - spread / 2)...min(0.9, center + spread / 2)
    }

    // MARK: - Derivation

    /// 3–5 colours from one contiguous stretch of `paletteHex`. The palette is
    /// already ordered by hue family, so a window over it is a hue-coherent
    /// selection without needing a colour-space conversion.
    private static func makePalette(seed: UInt64) -> [String] {
        var rng = SeededRNG.derived(from: seed, domain: "palette")
        let all = CanvasColorPalette.paletteHex
        let size = rng.nextInt(in: 3...5)
        // Window slightly wider than the palette size, so the picks inside it
        // are related but not simply consecutive.
        let window = min(all.count, size + 4)
        let start = rng.nextInt(in: 0...(all.count - window))

        var candidates = Array(all[start..<(start + window)])
        var picked = [String]()
        for _ in 0..<size {
            let index = rng.nextInt(in: 0...(candidates.count - 1))
            picked.append(candidates.remove(at: index))
        }
        return picked
    }

    private static func makeTexturePolicy(seed: UInt64, allowedKinds: [TextureKind]) -> TexturePolicy {
        var rng = SeededRNG.derived(from: seed, domain: "texturePolicy")
        let allowed = Set(allowedKinds)
        let filtered = TextureKind.allCases.filter(allowed.contains)
        let kinds = filtered.isEmpty ? TextureKind.allCases : filtered
        let dominant = kinds[rng.nextInt(in: 0...(kinds.count - 1))]
        return TexturePolicy(
            dominant: dominant,
            accent: dominant,
            accentShare: 0
        )
    }

    private static func makeHatchAngle(seed: UInt64) -> Double {
        var rng = SeededRNG.derived(from: seed, domain: "hatchAngle")
        return rng.nextDouble() * 2 * .pi
    }
}
