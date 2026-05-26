import Foundation
import SwiftUI

// MARK: - Element Kind (shape type per category)

enum ElementKind: String, Codable, CaseIterable {
    case circle    // Body → grounded, centered energy
    case ray       // Heart → angled beams pointing inward
}

// MARK: - Canvas Element

struct CanvasElement: Identifiable, Codable {
    let id: UUID
    var kind: ElementKind
    let category: EnergyCategory
    let optionId: String

    /// Display name shown on the canvas (e.g. "Running", "Reading"). Nil for older saved elements.
    var label: String?

    // Visual
    var hexColor: String
    /// Optional second color for radial gradient fill. Nil = solid single color.
    var hexColor2: String?
    /// Re-rolled by `reroll(availableCount:)` (dice tap), so `var` not `let`.
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
    /// otherwise falls back to the user's current preference for that category.
    /// Always migrates legacy `.blob` → `.circle`.
    var resolvedShapeType: CanvasShapeType {
        let shape = frozenShapeType ?? CanvasShapeType.resolved(for: category)
        return shape == .blob ? .circle : shape
    }

    init(id: UUID, kind: ElementKind, category: EnergyCategory, optionId: String, label: String?, hexColor: String, hexColor2: String? = nil, size: CGFloat, basePosition: CGPoint, phaseOffset: Double, driftSpeed: Double, driftAmplitude: CGFloat, pulseFrequency: Double, pulseAmplitude: CGFloat, rotationSpeed: Double, opacity: Double, createdAt: Date, assetVariant: Int? = nil, userRotation: Double = 0, shapeSeed: UInt64? = nil, userSize: CGFloat? = nil, activityCount: Int? = nil, lastEditedAt: Date? = nil, frozenShapeType: CanvasShapeType? = nil) {
        self.id = id
        self.kind = kind
        self.category = category
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

    /// Re-roll the visual variant of this element — randomises shape seed, size,
    /// phase, and drift speed. Color is re-rolled by the caller
    /// (`GalleryView.rerollElement`) since the entropy source is the
    /// `CanvasColorPalette`, which lives outside the model.
    mutating func reroll(availableCount: Int? = nil) {
        // All categories now use procedural rendering driven by shapeSeed.
        shapeSeed = UInt64.random(in: UInt64.min...UInt64.max)

        // Freeze current shape preference so historical renders stay stable.
        let resolvedShape = CanvasShapeType.resolved(for: category)
        frozenShapeType = resolvedShape
        let newSize: CGFloat = switch resolvedShape {
        case .blob:        .random(in: 0.16...0.32)
        case .organicBlob: .random(in: 0.16...0.34)
        case .snowflake:   .random(in: 0.04...0.48)
        case .rays:        .random(in: 0.20...0.28)
        case .circle, .spirograph: .random(in: 0.14...0.30)
        }
        size = newSize
        userSize = nil

        // Phase + drift speed — give the element a fresh "personality" so it
        // doesn't synchronise with its old motion after the dice tap.
        phaseOffset = Double.random(in: 0...(2 * .pi))
        driftSpeed = Double.random(in: 0.08...0.2)

        lastEditedAt = .now
    }

    static func spawn(
        optionId: String,
        category: EnergyCategory,
        color: String,
        color2: String? = nil,
        label: String,
        existingElements: [CanvasElement],
        forcedVariant: Int? = nil,
        dayKey: String? = nil,
        activityCount: Int? = nil
    ) -> CanvasElement {
        let shapeType = CanvasShapeType.resolved(for: category)

        let kind: ElementKind = switch shapeType {
            case .blob, .organicBlob, .snowflake, .circle, .spirograph: .circle
            case .rays:                                                  .ray
        }

        let position = findOpenPosition(existing: existingElements)

        let variant: Int = forcedVariant ?? 0

        let size: CGFloat = switch shapeType {
        case .blob:        .random(in: 0.16...0.32)
        case .organicBlob: .random(in: 0.16...0.34)
        case .snowflake:   .random(in: 0.04...0.48)
        case .rays:        .random(in: 0.20...0.28)
        case .circle, .spirograph: .random(in: 0.14...0.30)
        }
        let isGrounded = shapeType == .blob || shapeType == .circle || shapeType == .spirograph
        let pulseFreq = isGrounded
            ? Double.random(in: 0.08...0.2)
            : Double.random(in: 0.3...0.8)
        let opacity = isGrounded
            ? Double.random(in: 0.20...0.45)
            : Double.random(in: 0.35...0.75)

        let seed = dayKey.map { makeSeed(optionId: optionId, dayKey: $0, index: existingElements.count) }
            ?? UInt64.random(in: UInt64.min...UInt64.max)

        return CanvasElement(
            id: UUID(),
            kind: kind,
            category: category,
            optionId: optionId,
            label: label,
            hexColor: color,
            hexColor2: color2,
            size: size,
            basePosition: position,
            phaseOffset: Double.random(in: 0...(2 * .pi)),
            driftSpeed: Double.random(in: 0.08...0.2),
            driftAmplitude: CGFloat.random(in: 0.01...0.03),
            pulseFrequency: pulseFreq,
            pulseAmplitude: CGFloat.random(in: 0.01...0.03),
            rotationSpeed: Double.random(in: 3...10),
            opacity: opacity,
            createdAt: .now,
            assetVariant: variant,
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
        category = try c.decode(EnergyCategory.self, forKey: .category)
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
            ?? CanvasShapeType.defaultShape(for: category)

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
        try c.encode(category, forKey: .category)
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

    /// Find an open position avoiding overlap with existing elements.
    /// Uses progressive distance relaxation: starts strict, relaxes if space is tight.
    private static func findOpenPosition(existing: [CanvasElement]) -> CGPoint {
        let margin: CGFloat = 0.12
        let maxAttempts = 40
        let idealDistance: CGFloat = 0.15

        // Phase 1: strict spacing
        for _ in 0..<maxAttempts / 2 {
            let candidate = CGPoint(
                x: CGFloat.random(in: margin...(1.0 - margin)),
                y: CGFloat.random(in: margin...(1.0 - margin))
            )
            let tooClose = existing.contains { el in
                let dx = el.basePosition.x - candidate.x
                let dy = el.basePosition.y - candidate.y
                return sqrt(dx * dx + dy * dy) < idealDistance
            }
            if !tooClose { return candidate }
        }

        // Phase 2: relaxed spacing for crowded canvases
        let relaxedDistance: CGFloat = max(0.08, idealDistance - CGFloat(existing.count) * 0.01)
        for _ in 0..<maxAttempts / 2 {
            let candidate = CGPoint(
                x: CGFloat.random(in: margin...(1.0 - margin)),
                y: CGFloat.random(in: margin...(1.0 - margin))
            )
            let tooClose = existing.contains { el in
                let dx = el.basePosition.x - candidate.x
                let dy = el.basePosition.y - candidate.y
                return sqrt(dx * dx + dy * dy) < relaxedDistance
            }
            if !tooClose { return candidate }
        }

        // Fallback: pick the position that maximizes minimum distance to existing elements
        var bestCandidate = CGPoint(x: 0.5, y: 0.5)
        var bestMinDist: CGFloat = 0
        for _ in 0..<10 {
            let candidate = CGPoint(
                x: CGFloat.random(in: margin...(1.0 - margin)),
                y: CGFloat.random(in: margin...(1.0 - margin))
            )
            let minDist = existing.map { el -> CGFloat in
                let dx = el.basePosition.x - candidate.x
                let dy = el.basePosition.y - candidate.y
                return sqrt(dx * dx + dy * dy)
            }.min() ?? .greatestFiniteMagnitude

            if minDist > bestMinDist {
                bestMinDist = minDist
                bestCandidate = candidate
            }
        }
        return bestCandidate
    }
}
