import Foundation
import SwiftUI

// MARK: - Element Kind (shape type per category)

enum ElementKind: String, Codable, CaseIterable {
    case circle    // Body → grounded, centered energy
    case softLine  // Heart → fluid, emotional
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
    let hexColor: String
    let size: CGFloat              // normalized 0…1 relative to canvas
    let basePosition: CGPoint      // normalized (0…1, 0…1)

    // Animation parameters (randomized on creation)
    let phaseOffset: Double        // 0…2π — desynchronizes from other elements
    let driftSpeed: Double         // 0.1…0.5 — how fast it moves
    let driftAmplitude: CGFloat    // 0.01…0.06 — how far it drifts (normalized)
    let pulseFrequency: Double     // 0.3…1.2 Hz
    let pulseAmplitude: CGFloat    // 0.02…0.08 — scale oscillation range
    let rotationSpeed: Double      // degrees/sec (rays only)
    let opacity: Double            // 0.3…0.8

    // Timestamps
    let createdAt: Date

    /// Title to draw on the canvas; falls back to optionId for legacy elements.
    var displayLabel: String { label ?? optionId }

    init(id: UUID, kind: ElementKind, category: EnergyCategory, optionId: String, label: String?, hexColor: String, size: CGFloat, basePosition: CGPoint, phaseOffset: Double, driftSpeed: Double, driftAmplitude: CGFloat, pulseFrequency: Double, pulseAmplitude: CGFloat, rotationSpeed: Double, opacity: Double, createdAt: Date) {
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
    }

    // MARK: - Factory

    static func spawn(
        optionId: String,
        category: EnergyCategory,
        color: String,
        label: String,
        existingElements: [CanvasElement]
    ) -> CanvasElement {
        let kind: ElementKind = switch category {
            case .body:  .circle   // body: floating circles
            case .mind:  .circle   // mind: floating circles (same behaviour as body)
            case .heart: .ray      // heart: angled rays
        }

        let position = (category == .heart)
            ? findEdgePosition(existing: existingElements)
            : findOpenPosition(existing: existingElements)

        // Body: M–L stable pulsing. Mind: S–M wandering. Heart: M rays.
        let size: CGFloat = switch category {
        case .body:  .random(in: 0.24...0.48)   // M–L
        case .mind:  .random(in: 0.12...0.26)   // S–M
        case .heart: .random(in: 0.20...0.28)   // M
        }
        let isBody = category == .body
        let pulseFreq = isBody
            ? Double.random(in: 0.08...0.2)     // very slow breath
            : Double.random(in: 0.3...0.8)
        let opacity = isBody
            ? Double.random(in: 0.20...0.45)    // almost invisible
            : Double.random(in: 0.35...0.75)

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
            createdAt: Date()
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, category, optionId, hexColor, size, basePosition
        case phaseOffset, driftSpeed, driftAmplitude, pulseFrequency, pulseAmplitude, rotationSpeed, opacity, createdAt
        case label
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
    }

    /// Place heart elements along edges / corners, biased toward the frame perimeter.
    /// They stay within 0.02…0.25 or 0.75…0.98 on each axis so they hug the border.
    private static func findEdgePosition(existing: [CanvasElement]) -> CGPoint {
        let maxAttempts = 20
        let minDistance: CGFloat = 0.15

        // 4 corners + 4 edge midpoints as anchor zones (normalized coords)
        let edgeZones: [(xRange: ClosedRange<CGFloat>, yRange: ClosedRange<CGFloat>)] = [
            // corners
            (0.02...0.22, 0.02...0.22),   // top-left
            (0.78...0.98, 0.02...0.22),   // top-right
            (0.02...0.22, 0.78...0.98),   // bottom-left
            (0.78...0.98, 0.78...0.98),   // bottom-right
            // edge midpoints
            (0.35...0.65, 0.02...0.15),   // top-center
            (0.35...0.65, 0.85...0.98),   // bottom-center
            (0.02...0.15, 0.35...0.65),   // left-center
            (0.85...0.98, 0.35...0.65),   // right-center
        ]

        for _ in 0..<maxAttempts {
            let zone = edgeZones.randomElement()!
            let candidate = CGPoint(
                x: CGFloat.random(in: zone.xRange),
                y: CGFloat.random(in: zone.yRange)
            )
            let tooClose = existing.contains { el in
                let dx = el.basePosition.x - candidate.x
                let dy = el.basePosition.y - candidate.y
                return sqrt(dx * dx + dy * dy) < minDistance
            }
            if !tooClose { return candidate }
        }
        // Fallback: random corner
        let zone = edgeZones[Int.random(in: 0...3)]
        return CGPoint(
            x: CGFloat.random(in: zone.xRange),
            y: CGFloat.random(in: zone.yRange)
        )
    }

    /// Find an open position avoiding overlap with existing elements
    private static func findOpenPosition(existing: [CanvasElement]) -> CGPoint {
        let margin: CGFloat = 0.12
        let maxAttempts = 20
        let minDistance: CGFloat = 0.15

        for _ in 0..<maxAttempts {
            let candidate = CGPoint(
                x: CGFloat.random(in: margin...(1.0 - margin)),
                y: CGFloat.random(in: margin...(1.0 - margin))
            )
            let tooClose = existing.contains { el in
                let dx = el.basePosition.x - candidate.x
                let dy = el.basePosition.y - candidate.y
                return sqrt(dx * dx + dy * dy) < minDistance
            }
            if !tooClose { return candidate }
        }
        // Fallback: random within safe area
        return CGPoint(
            x: CGFloat.random(in: margin...(1.0 - margin)),
            y: CGFloat.random(in: margin...(1.0 - margin))
        )
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
    var experienceEarned: Int
    var experienceSpent: Int
    let createdAt: Date
    var lastModified: Date

    /// 0.0 = pristine (nothing spent), 1.0 = fully degraded (all EXP spent)
    var decayNorm: Double {
        guard experienceEarned > 0 else { return 0 }
        return min(1.0, Double(experienceSpent) / Double(experienceEarned))
    }

    init(dayKey: String) {
        self.dayKey = dayKey
        self.elements = []
        self.sleepPoints = 0
        self.stepsPoints = 0
        self.sleepColorHex = "#8B5CF6"
        self.stepsColorHex = "#FED415"
        self.experienceEarned = 0
        self.experienceSpent = 0
        self.createdAt = Date()
        self.lastModified = Date()
    }
}

// MARK: - Color Palette

enum CanvasColorPalette {
    /// 16-color activity palette (4×4 grid)
    static let palette: [Color] = [
        Color(hex: "#C3143B"), Color(hex: "#9BB6E0"), Color(hex: "#A7BF50"), Color(hex: "#C3D7A3"),
        Color(hex: "#01B6C4"), Color(hex: "#7652AF"), Color(hex: "#F68D0C"), Color(hex: "#2C2E4D"),
        Color(hex: "#796C3C"), Color(hex: "#EBDF63"), Color(hex: "#49484D"), Color(hex: "#C7E0D8"),
        Color(hex: "#0F0D0E"), Color(hex: "#955530"), Color(hex: "#FEAAC2"), Color(hex: "#EBE4D7"),
    ]

    static let paletteHex: [String] = [
        "#C3143B", "#9BB6E0", "#A7BF50", "#C3D7A3",
        "#01B6C4", "#7652AF", "#F68D0C", "#2C2E4D",
        "#796C3C", "#EBDF63", "#49484D", "#C7E0D8",
        "#0F0D0E", "#955530", "#FEAAC2", "#EBE4D7",
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
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return "#FFFFFF"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
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
