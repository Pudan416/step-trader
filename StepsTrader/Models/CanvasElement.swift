import Foundation
import SwiftUI

// MARK: - Element Kind (shape type per category)

enum ElementKind: String, Codable, CaseIterable {
    case circle    // Body → grounded, centered energy
    case ray       // Mind → directional, focused
}

// MARK: - Canvas Element

struct CanvasElement: Identifiable, Codable {
    let id: UUID
    let kind: ElementKind
    let category: EnergyCategory
    let optionId: String

    /// Display name shown on the canvas (e.g. "Running", "Reading"). Nil for older saved elements.
    var label: String?

    // Visual
    var hexColor: String
    let size: CGFloat              // normalized 0…1 relative to canvas
    var basePosition: CGPoint      // normalized (0…1, 0…1)

    // Animation parameters (randomized on creation)
    let phaseOffset: Double        // 0…2π — desynchronizes from other elements
    let driftSpeed: Double         // 0.1…0.5 — how fast it moves
    let driftAmplitude: CGFloat    // 0.01…0.06 — how far it drifts (normalized)
    let pulseFrequency: Double     // 0.3…1.2 Hz
    let pulseAmplitude: CGFloat    // 0.02…0.08 — scale oscillation range
    let rotationSpeed: Double      // degrees/sec (rays only)
    let opacity: Double            // 0.3…0.8

    /// Which asset variant to use (0-based index into the category's asset array).
    /// Assigned at spawn time via round-robin so consecutive elements get different shapes.
    /// Legacy elements (saved before this field existed) fall back to UUID-based selection.
    var assetVariant: Int?

    /// User-applied rotation in radians (from move mode). 0 = default orientation.
    var userRotation: Double

    /// Deterministic seed for procedural shape generation.
    /// Nil for legacy elements saved before procedural shapes existed.
    var shapeSeed: UInt64?

    /// User-overridden size from pinch gesture. Nil = use the random `size`.
    var userSize: CGFloat?

    /// How many times this activity has been logged historically (drives shape complexity).
    var activityCount: Int?

    // Timestamps
    let createdAt: Date

    /// Title to draw on the canvas; falls back to optionId for legacy elements.
    var displayLabel: String { label ?? optionId }

    init(id: UUID, kind: ElementKind, category: EnergyCategory, optionId: String, label: String?, hexColor: String, size: CGFloat, basePosition: CGPoint, phaseOffset: Double, driftSpeed: Double, driftAmplitude: CGFloat, pulseFrequency: Double, pulseAmplitude: CGFloat, rotationSpeed: Double, opacity: Double, createdAt: Date, assetVariant: Int? = nil, userRotation: Double = 0, shapeSeed: UInt64? = nil, userSize: CGFloat? = nil, activityCount: Int? = nil) {
        self.id = id
        self.kind = kind
        self.category = category
        self.optionId = optionId
        self.label = label
        self.hexColor = hexColor
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
    }

    // MARK: - Factory

    /// Generates a deterministic seed from the element's identity.
    static func makeSeed(optionId: String, dayKey: String, index: Int) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(optionId)
        hasher.combine(dayKey)
        hasher.combine(index)
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }

    mutating func reroll() {
        let current = assetVariant ?? 0
        let count = CanvasImageCatalog.imageNames(for: category).count
        switch category {
        case .mind, .heart:
            guard count > 1 else { return }
            var next = Int.random(in: 0..<count)
            while next == current { next = Int.random(in: 0..<count) }
            assetVariant = next
        case .body:
            shapeSeed = UInt64.random(in: UInt64.min...UInt64.max)
        }
    }

    static func spawn(
        optionId: String,
        category: EnergyCategory,
        color: String,
        label: String,
        existingElements: [CanvasElement],
        forcedVariant: Int? = nil,
        dayKey: String? = nil,
        activityCount: Int? = nil
    ) -> CanvasElement {
        let kind: ElementKind = switch category {
            case .body:  .circle   // body: floating circles
            case .mind:  .circle   // mind: floating circles (same behaviour as body)
            case .heart: .ray      // heart: angled rays
        }

        let position = findOpenPosition(existing: existingElements)

        let assetCount = CanvasImageCatalog.imageNames(for: category).count
        let variant: Int
        if let forced = forcedVariant, forced >= 0, forced < assetCount {
            variant = forced
        } else {
            let sameCategoryCount = existingElements.filter { $0.category == category }.count
            variant = sameCategoryCount % assetCount
        }

        // Body: M–L stable pulsing. Mind: S–M wandering. Heart: M rays.
        let size: CGFloat = switch category {
        case .body:  .random(in: 0.16...0.32)   // M–L (1.5× smaller)
        case .mind:  .random(in: 0.10...0.18)   // S — drifting stars
        case .heart: .random(in: 0.20...0.28)   // M
        }
        let isBody = category == .body
        let pulseFreq = isBody
            ? Double.random(in: 0.08...0.2)     // very slow breath
            : Double.random(in: 0.3...0.8)
        let opacity = isBody
            ? Double.random(in: 0.20...0.45)    // almost invisible
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
            size: size,
            basePosition: position,
            phaseOffset: Double.random(in: 0...(2 * .pi)),
            driftSpeed: Double.random(in: 0.08...0.2),
            driftAmplitude: CGFloat.random(in: 0.01...0.03),
            pulseFrequency: pulseFreq,
            pulseAmplitude: CGFloat.random(in: 0.01...0.03),
            rotationSpeed: Double.random(in: 3...10),
            opacity: opacity,
            createdAt: Date(),
            assetVariant: variant,
            shapeSeed: seed,
            activityCount: activityCount
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, category, optionId, hexColor, size, basePosition
        case phaseOffset, driftSpeed, driftAmplitude, pulseFrequency, pulseAmplitude, rotationSpeed, opacity, createdAt
        case label, assetVariant, userRotation
        case shapeSeed, userSize, activityCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(ElementKind.self, forKey: .kind)
        category = try c.decode(EnergyCategory.self, forKey: .category)
        optionId = try c.decode(String.self, forKey: .optionId)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        hexColor = try c.decode(String.self, forKey: .hexColor)
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
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(category, forKey: .category)
        try c.encode(optionId, forKey: .optionId)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encode(hexColor, forKey: .hexColor)
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

// MARK: - Day Canvas (today's live state)

struct DayCanvas: Codable {
    let dayKey: String                          // "2026-02-12"
    var elements: [CanvasElement]               // spawned from activities
    var sleepPoints: Int
    var stepsPoints: Int
    var sleepColorHex: String
    var stepsColorHex: String
    var inkEarned: Int
    var inkSpent: Int
    let createdAt: Date
    var lastModified: Date

    /// 0.0 = pristine (nothing spent), 1.0 = fully degraded (all colors spent)
    var decayNorm: Double {
        guard inkEarned > 0 else { return 0 }
        return min(1.0, Double(inkSpent) / Double(inkEarned))
    }

    init(dayKey: String) {
        self.dayKey = dayKey
        self.elements = []
        self.sleepPoints = 0
        self.stepsPoints = 0
        self.sleepColorHex = "#000000"
        self.stepsColorHex = "#FED415"
        self.inkEarned = 0
        self.inkSpent = 0
        self.createdAt = Date()
        self.lastModified = Date()
    }
}

// MARK: - Color Palette

enum CanvasColorPalette {
    /// 16-color activity palette (4×4 grid)
    static let paletteHex: [String] = [
        "#C3143B", "#9BB6E0", "#A7BF50", "#C3D7A3",
        "#01B6C4", "#7652AF", "#F68D0C", "#2C2E4D",
        "#796C3C", "#FFD369", "#49484D", "#C7E0D8",
        "#222831", "#955530", "#FEAAC2", "#EBE4D7",
    ]
}

// MARK: - Color + Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b, a) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17, 255)
        case 6: // RGB (24-bit)
            (r, g, b, a) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8: // ARGB (32-bit)
            (r, g, b, a) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF, int >> 24)
        default:
            (r, g, b, a) = (255, 255, 255, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func toHex() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    /// Desaturate toward gray by a factor 0…1
    func desaturated(by factor: Double) -> Color {
        let uiColor = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let newSat = s * CGFloat(1.0 - factor)
        return Color(hue: Double(h), saturation: Double(newSat), brightness: Double(b))
            .opacity(Double(a))
    }
}
