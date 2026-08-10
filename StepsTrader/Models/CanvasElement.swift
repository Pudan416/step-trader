import Foundation
import SwiftUI

/// Decode-only bridge for canvases written before happenings. It must never
/// escape into the domain model or be encoded by new builds.
private enum LegacyCategory: String, Decodable {
    case body, mind, heart

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "body", "activity": self = .body
        case "mind", "creativity", "recovery", "rest": self = .mind
        case "heart", "joys": self = .heart
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown legacy category: \(raw)")
            )
        }
    }

    var frozenShapeType: CanvasShapeType {
        switch self {
        case .body: .circle
        case .mind: .snowflake
        case .heart: .rays
        }
    }
}

// MARK: - Element Kind (shape type per category)

enum ElementKind: String, Codable, CaseIterable {
    case circle    // Body → grounded, centered energy
    case ray       // Heart → angled beams pointing inward
}

// MARK: - Canvas Element

struct CanvasElement: Identifiable, Codable {
    let id: UUID
    var kind: ElementKind
    let optionId: String

    /// Display name shown on the canvas (e.g. "Running", "Reading"). Nil for older saved elements.
    var label: String?

    // Visual
    var hexColor: String
    /// Optional second color for radial gradient fill. Nil = solid single color.
    var hexColor2: String?
    /// Re-rolled by `reroll(rank:composition:)` (dice tap), so `var` not `let`.
    /// Renderer reads `userSize ?? size` — clearing `userSize` lets the new
    /// value take effect immediately.
    var size: Double               // normalized 0…1 relative to canvas
    var basePosition: CGPoint      // normalized (0…1, 0…1)

    // Animation parameters (randomized on creation; ranges come from `spawn` below)
    /// Re-rolled by `reroll` so the element gets a fresh "personality" after
    /// dice tap and stops syncing with its prior motion.
    var phaseOffset: Double        // 0…2π — desynchronizes from other elements
    /// Re-rolled by `reroll` (see `phaseOffset`).
    var driftSpeed: Double         // 0.08…0.20 — how fast it moves
    let driftAmplitude: Double     // 0.01…0.03 — how far it drifts (normalized)
    let pulseFrequency: Double     // body 0.08…0.20 Hz, mind/heart 0.30…0.80 Hz
    let pulseAmplitude: Double     // 0.01…0.03 — scale oscillation range
    let rotationSpeed: Double      // 3…10 deg/sec (rays only)
    let opacity: Double            // body 0.20…0.45, mind/heart 0.35…0.75

    /// Which asset variant to use (0-based index into the category's asset array).
    /// Assigned at spawn time via round-robin so consecutive elements get different shapes.
    /// Legacy elements (saved before this field existed) fall back to UUID-based selection.
    var assetVariant: Int?

    /// User-applied rotation in radians (from move mode). 0 = default orientation.
    var userRotation: Double

    /// Deterministic seed for procedural shape generation.
    /// Nil for legacy elements saved before procedural shapes existed.
    var shapeSeed: UInt64?

    /// Shape type frozen at spawn time so historical canvases render with
    /// the shape that was active on that day, not the user's current preference.
    /// Nil for legacy elements — falls back to `CanvasShapeType.resolved(for:)`.
    var frozenShapeType: CanvasShapeType?

    /// User-overridden size from pinch gesture. Nil = use the random `size`.
    var userSize: CGFloat?

    /// How many times this option has been logged historically (drives shape complexity).
    var activityCount: Int?

    // Timestamps
    let createdAt: Date

    /// Updated whenever the element is mutated locally (color change, drag, reroll,
    /// resize, rotate). Nil for legacy elements; merge logic falls back to `createdAt`.
    /// Drives last-write-wins resolution between local edits and remote canvas snapshots.
    var lastEditedAt: Date?

    /// Title to draw on the canvas; falls back to optionId for legacy elements.
    var displayLabel: String { label ?? optionId }

    /// The shape type to use for rendering. Returns the frozen value if available,
    /// Newly spawned and decoded elements always freeze a shape.
    var resolvedShapeType: CanvasShapeType {
        let shape = frozenShapeType ?? .circle
        return shape == .blob ? .circle : shape
    }

    init(id: UUID, kind: ElementKind, optionId: String, label: String?, hexColor: String, hexColor2: String? = nil, size: CGFloat, basePosition: CGPoint, phaseOffset: Double, driftSpeed: Double, driftAmplitude: CGFloat, pulseFrequency: Double, pulseAmplitude: CGFloat, rotationSpeed: Double, opacity: Double, createdAt: Date, assetVariant: Int? = nil, userRotation: Double = 0, shapeSeed: UInt64? = nil, userSize: CGFloat? = nil, activityCount: Int? = nil, lastEditedAt: Date? = nil, frozenShapeType: CanvasShapeType? = nil) {
        self.id = id
        self.kind = kind
        self.optionId = optionId
        self.label = label
        self.hexColor = hexColor
        self.hexColor2 = hexColor2
        self.size = size
        self.basePosition = basePosition
        self.phaseOffset = phaseOffset
        self.driftSpeed = driftSpeed
        self.driftAmplitude = driftAmplitude
        self.pulseFrequency = pulseFrequency
        self.pulseAmplitude = pulseAmplitude
        self.rotationSpeed = rotationSpeed
        self.opacity = opacity
        self.createdAt = createdAt
        self.assetVariant = assetVariant
        self.userRotation = userRotation
        self.shapeSeed = shapeSeed
        self.userSize = userSize
        self.activityCount = activityCount
        self.lastEditedAt = lastEditedAt
        self.frozenShapeType = frozenShapeType
    }

    mutating func touchEdit(at date: Date = .now) {
        lastEditedAt = date
    }

    // MARK: - Factory

    /// Generates a deterministic seed from the element's identity.
    ///
    /// Uses FNV-1a (64-bit) on a stable byte composition of `optionId`,
    /// `dayKey`, and `index`. The same input always produces the same seed
    /// across launches, processes, and Swift versions — required so procedural
    /// shapes don't shuffle on every app start.
    static func makeSeed(optionId: String, dayKey: String, index: Int) -> UInt64 {
        let prime: UInt64 = 0x0000_0100_0000_01B3
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325

        @inline(__always) func mix(_ byte: UInt8) {
            hash ^= UInt64(byte)
            hash &*= prime
        }

        for byte in optionId.utf8 { mix(byte) }
        mix(0x1F) // unit-separator: prevents "ab"+"c" colliding with "a"+"bc"
        for byte in dayKey.utf8 { mix(byte) }
        mix(0x1F)

        var idx = UInt64(bitPattern: Int64(index))
        for _ in 0..<8 {
            mix(UInt8(truncatingIfNeeded: idx))
            idx >>= 8
        }
        return hash
    }

    // MARK: - Composition

    /// The normalised region new elements may occupy. The margin is deliberate
    /// negative space: it keeps the composition off the frame edge, where
    /// elements were previously cropped by the viewport.
    static let spawnBounds = CGRect(x: 0.12, y: 0.12, width: 0.76, height: 0.76)

    /// Target spacing, tightened as the canvas fills so late elements still
    /// land somewhere sensible instead of exhausting the sampler.
    ///
    /// Lowered from `max(0.09, 0.30 - count * 0.012)`: at 8 elements in the
    /// 0.76-wide `spawnBounds`, that packed to ~55% density, where a
    /// near-uniform arrangement was close to the only feasible layout — no
    /// choice of archetype field could make elements cluster because there
    /// was nowhere for a cluster to fit. This spacing leaves enough slack for
    /// `PoissonDiscSampler`'s weight field to actually concentrate mass.
    static func spawnMinDistance(existingCount: Int) -> Double {
        max(0.07, 0.20 - Double(existingCount) * 0.010)
    }

    /// Per-shape base size range, before the archetype's multiplier.
    static func baseSizeRange(for shape: CanvasShapeType) -> ClosedRange<Double> {
        switch shape {
        case .blob:                0.16...0.32
        case .organicBlob:         0.16...0.34
        case .snowflake:           0.04...0.48
        case .rays:                0.20...0.28
        case .circle, .spirograph: 0.14...0.30
        }
    }

    /// The fill for an element at a given arrival order under a day's policy.
    ///
    /// Seeded on `dayKey` + `rank` via the same FNV construction `makeSeed`
    /// uses everywhere else — never on `String.hashValue`. Swift randomises
    /// hash seeds per process, so a hashValue-derived seed would keep the
    /// fill *kind* stable (that comes from `texturePolicy`, which is
    /// Codable data) but reshuffle `density`/`uniformity`/`angle` on every
    /// launch, so a live render and a thumbnail or export rendered in a
    /// different process would disagree on the same element.
    static func textureSpec(rank: Int, dayKey: String, composition: DayComposition) -> TextureSpec {
        let kind = composition.texturePolicy.kind(forRank: rank)
        let seed = makeSeed(optionId: "composition-texture", dayKey: dayKey, index: rank)
        return TextureSpec.seeded(kind: kind, seed: seed)
    }

    /// Re-roll the visual variant of this element.
    ///
    /// Unlike `spawn` this is deliberately non-deterministic — the dice is a
    /// request for something new. It still obeys the day: size follows the
    /// archetype's curve and colour stays on the day's palette, so one re-roll
    /// cannot break the canvas's coherence.
    mutating func reroll(rank: Int, composition: DayComposition) {
        shapeSeed = UInt64.random(in: UInt64.min...UInt64.max)

        // Freeze one currently allowed shape so historical renders stay stable.
        let resolvedShape = CanvasShapeType.allowedByUser.randomElement() ?? .circle
        frozenShapeType = resolvedShape

        var rng = SeededRNG(seed: shapeSeed ?? 0)
        let base = rng.nextDouble(in: Self.baseSizeRange(for: resolvedShape))
        let multiplier = composition.archetype.sizeMultiplier(
            rank: rank, count: DayComposition.nominalDayCount)
        size = CGFloat(min(0.48, max(0.04, base * multiplier)))
        userSize = nil

        // Draw from 1..<palette.count, not 1...palette.count: the upper bound
        // wraps back to `rank` itself (mod count), which made roughly one
        // dice tap in 3-5 silently return the element's own current colour.
        // Guard palettes with fewer than 2 entries, where no other colour
        // exists to shift to.
        let shift = composition.palette.count > 1
            ? rng.nextInt(in: 1...(composition.palette.count - 1))
            : 0
        let shifted = rank + shift
        hexColor = composition.color(forRank: shifted)

        // Same ~60/40 two-colour split as `spawn`, so a dice tap can still
        // produce the single-colour element that split was reinstated to
        // preserve — previously `reroll` always assigned a second colour.
        hexColor2 = rng.nextDouble() < 0.6
            ? composition.color(forRank: shifted + 1)
            : nil

        // Phase + drift speed — give the element a fresh "personality" so it
        // doesn't synchronise with its old motion after the dice tap.
        // The snowflake derives its drift position from both (see
        // SnowflakeShapeRenderer.rawDriftState, multiplied by the huge
        // timeIntervalSinceReferenceDate clock), so re-rolling them would
        // teleport it. Preserve them there — the dice should change only the
        // shape, size, and color, not where the element sits.
        if resolvedShape != .snowflake {
            phaseOffset = Double.random(in: 0...(2 * .pi))
            driftSpeed = Double.random(in: 0.08...0.2)
        }

        lastEditedAt = .now
    }

    static func spawn(
        id: UUID = UUID(),
        optionId: String,
        label: String,
        existingElements: [CanvasElement],
        forcedVariant: Int? = nil,
        allowedShapeTypes: [CanvasShapeType] = CanvasShapeType.allowedByUser,
        dayKey: String? = nil,
        activityCount: Int? = nil,
        composition: DayComposition
    ) -> CanvasElement {
        // Arrival order within the day. Drives size, colour and texture.
        let rank = existingElements.count

        // The seed comes first: everything below derives from it, so the same
        // day + option + index reproduces the whole element, not just its
        // contour. Without a dayKey there is nothing stable to hash, so the
        // element gets a one-off random identity.
        let seed = dayKey.map { makeSeed(optionId: optionId, dayKey: $0, index: rank) }
            ?? UInt64.random(in: UInt64.min...UInt64.max)

        // `allowedByUser` returns its result in picker order, so indexing into
        // it is stable across launches. Never index into a Set here — Swift
        // randomises hash seeds per process.
        let choices = allowedShapeTypes.isEmpty ? [CanvasShapeType.circle] : allowedShapeTypes
        var shapeRng = SeededRNG.derived(from: seed, domain: "shape")
        let shapeType = choices[shapeRng.nextInt(in: 0...(choices.count - 1))]

        let kind: ElementKind = switch shapeType {
            case .blob, .organicBlob, .snowflake, .circle, .spirograph: .circle
            case .rays:                                                  .ray
        }

        // Placement follows the day's archetype field.
        var placementRng = SeededRNG.derived(from: seed, domain: "placement")
        let position = PoissonDiscSampler.nextPoint(
            existing: existingElements.map(\.basePosition),
            bounds: spawnBounds,
            minDistance: spawnMinDistance(existingCount: rank),
            weight: { composition.archetype.weight(at: $0) },
            using: &placementRng
        )

        // Size follows the archetype's curve, so a centred-mass day and a
        // constellation day do not share a skeleton.
        var sizeRng = SeededRNG.derived(from: seed, domain: "size")
        let base = sizeRng.nextDouble(in: baseSizeRange(for: shapeType))
        let multiplier = composition.archetype.sizeMultiplier(
            rank: rank, count: DayComposition.nominalDayCount)
        let size = CGFloat(min(0.48, max(0.04, base * multiplier)))

        // Colour comes from the day's palette, not from all 29 swatches.
        let color = composition.color(forRank: rank)

        // ~60% two-colour, ~40% single-colour — restores the variety the old
        // `randomSecondColor` (~50% nil) gave, deterministically. Every
        // element getting a gradient made the canvas busier than intended;
        // `hexColor2`'s own doc comment still says "Nil = solid single color".
        var secondColourRng = SeededRNG.derived(from: seed, domain: "secondColour")
        let hexColor2 = secondColourRng.nextDouble() < 0.6
            ? composition.color(forRank: rank + 1)
            : nil

        var motionRng = SeededRNG.derived(from: seed, domain: "motion")
        let opacityRange = composition.opacityRange(forRank: rank)
        let isGrounded = shapeType == .blob || shapeType == .circle || shapeType == .spirograph
        let pulseFrequency = isGrounded
            ? motionRng.nextDouble(in: 0.08...0.2)
            : motionRng.nextDouble(in: 0.3...0.8)

        return CanvasElement(
            id: id,
            kind: kind,
            optionId: optionId,
            label: label,
            hexColor: color,
            hexColor2: hexColor2,
            size: size,
            basePosition: position,
            phaseOffset: motionRng.nextDouble(in: 0...(2 * .pi)),
            driftSpeed: motionRng.nextDouble(in: 0.08...0.2),
            driftAmplitude: motionRng.nextCGFloat(in: 0.01...0.03),
            pulseFrequency: pulseFrequency,
            pulseAmplitude: motionRng.nextCGFloat(in: 0.01...0.03),
            rotationSpeed: motionRng.nextDouble(in: 3...10),
            opacity: motionRng.nextDouble(in: opacityRange),
            createdAt: .now,
            assetVariant: forcedVariant ?? 0,
            shapeSeed: seed,
            activityCount: activityCount,
            frozenShapeType: shapeType
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, category, optionId, hexColor, hexColor2, size, basePosition
        case phaseOffset, driftSpeed, driftAmplitude, pulseFrequency, pulseAmplitude, rotationSpeed, opacity, createdAt
        case label, assetVariant, userRotation
        case shapeSeed, userSize, activityCount
        case lastEditedAt, frozenShapeType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(ElementKind.self, forKey: .kind)
        let legacyCategory = try c.decodeIfPresent(LegacyCategory.self, forKey: .category)
        optionId = try c.decode(String.self, forKey: .optionId)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        let rawHex = try c.decode(String.self, forKey: .hexColor)
        hexColor = CanvasColorPalette.migrateLegacyColor(rawHex)

        let rawHex2 = try c.decodeIfPresent(String.self, forKey: .hexColor2)
        size = try c.decode(CGFloat.self, forKey: .size)
        basePosition = try c.decode(CGPoint.self, forKey: .basePosition)
        phaseOffset = try c.decode(Double.self, forKey: .phaseOffset)
        driftSpeed = try c.decode(Double.self, forKey: .driftSpeed)
        driftAmplitude = try c.decode(CGFloat.self, forKey: .driftAmplitude)
        pulseFrequency = try c.decode(Double.self, forKey: .pulseFrequency)
        pulseAmplitude = try c.decode(CGFloat.self, forKey: .pulseAmplitude)
        rotationSpeed = try c.decode(Double.self, forKey: .rotationSpeed)
        opacity = try c.decode(Double.self, forKey: .opacity)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        assetVariant = try c.decodeIfPresent(Int.self, forKey: .assetVariant)
        userRotation = try c.decodeIfPresent(Double.self, forKey: .userRotation) ?? 0
        shapeSeed = try c.decodeIfPresent(UInt64.self, forKey: .shapeSeed)
        userSize = try c.decodeIfPresent(CGFloat.self, forKey: .userSize)
        activityCount = try c.decodeIfPresent(Int.self, forKey: .activityCount)
        lastEditedAt = try c.decodeIfPresent(Date.self, forKey: .lastEditedAt)
        frozenShapeType = try c.decodeIfPresent(CanvasShapeType.self, forKey: .frozenShapeType)
            ?? legacyCategory?.frozenShapeType
            ?? .circle

        if let h2 = rawHex2 {
            hexColor2 = CanvasColorPalette.migrateLegacyColor(h2)
        } else if let seed = shapeSeed {
            hexColor2 = CanvasColorPalette.seededSecondColor(seed: seed, primary: hexColor)
        } else {
            hexColor2 = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(optionId, forKey: .optionId)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encode(hexColor, forKey: .hexColor)
        try c.encodeIfPresent(hexColor2, forKey: .hexColor2)
        try c.encode(size, forKey: .size)
        try c.encode(basePosition, forKey: .basePosition)
        try c.encode(phaseOffset, forKey: .phaseOffset)
        try c.encode(driftSpeed, forKey: .driftSpeed)
        try c.encode(driftAmplitude, forKey: .driftAmplitude)
        try c.encode(pulseFrequency, forKey: .pulseFrequency)
        try c.encode(pulseAmplitude, forKey: .pulseAmplitude)
        try c.encode(rotationSpeed, forKey: .rotationSpeed)
        try c.encode(opacity, forKey: .opacity)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(assetVariant, forKey: .assetVariant)
        try c.encode(userRotation, forKey: .userRotation)
        try c.encodeIfPresent(shapeSeed, forKey: .shapeSeed)
        try c.encodeIfPresent(userSize, forKey: .userSize)
        try c.encodeIfPresent(activityCount, forKey: .activityCount)
        try c.encodeIfPresent(lastEditedAt, forKey: .lastEditedAt)
        try c.encodeIfPresent(frozenShapeType, forKey: .frozenShapeType)
    }

}
