import Foundation

struct DayCanvas: Codable {
    var dayKey: String                          // "2026-02-12"
    var elements: [CanvasElement] {             // spawned from activities
        didSet {
            artworkRecipe = artworkRecipe?.reconciled(eventIDs: elements.map { $0.id.uuidString.lowercased() })
        }
    }
    var sleepPoints: Int
    var stepsPoints: Int
    var sleepColorHex: String
    var stepsColorHex: String
    var inkEarned: Int
    var inkSpent: Int
    let createdAt: Date
    var lastModified: Date
    var gradientStyle: String?
    var gradientPalette: String?
    var overlayStyle: String?
    var textureRaw: String?
    var visualStyleRaw: String?
    var hasStepsData: Bool?
    var hasSleepData: Bool?
    /// Absent in historical artwork. Never synthesize during decoding.
    var artworkRecipe: NativeAtlasRecipe?

    /// 0.0 = pristine (nothing spent), 1.0 = fully degraded (all colors spent)
    var decayNorm: Double {
        guard inkEarned > 0 else { return 0 }
        return min(1.0, Double(inkSpent) / Double(inkEarned))
    }

    /// Resolved flag: prefers stored boolean, falls back to points > 0 for legacy canvases.
    var resolvedHasStepsData: Bool {
        hasStepsData ?? (stepsPoints > 0)
    }

    /// Resolved flag: prefers stored boolean, falls back to points > 0 for legacy canvases.
    var resolvedHasSleepData: Bool {
        hasSleepData ?? (sleepPoints > 0)
    }

    /// Canvases written before the Editorial promotion are historical Legacy
    /// canvases. Only the one-time active-day migration may promote a missing
    /// value; ordinary decoding never changes old artwork retroactively.
    var resolvedVisualStyle: CanvasVisualStyle {
        CanvasVisualStyle(rawValue: visualStyleRaw ?? "") ?? .legacy
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
        self.createdAt = .now
        self.lastModified = .now
        self.gradientStyle = nil
        self.gradientPalette = nil
        self.overlayStyle = nil
        self.textureRaw = nil
        self.visualStyleRaw = nil
        self.hasStepsData = nil
        self.hasSleepData = nil
        self.artworkRecipe = nil
    }

    static func newDailyCanvas(dayKey: String) -> Self {
        var canvas = Self(dayKey: dayKey)
        canvas.visualStyleRaw = CanvasVisualStyle.editorial.rawValue
        canvas.artworkRecipe = .make(dayKey: dayKey)
        return canvas
    }
}

/// Frozen native parameters rather than references to an evolving palette.
/// This model is deliberately opt-in until the shared Metal path is validated.
struct NativeAtlasRecipe: Codable, Equatable {
    struct Actor: Codable, Equatable {
        let eventID: String
        let presetID: String
        let materialID: MetalShapeMaterial
        let seedHex: String
        let geometry: MetalShapeGenomeUniforms
        let material: MetalShapeMaterialUniforms
        let position: SIMD2<Float>
        let size: Float
        let rotation: Float
        let slot: Int
    }

    var schemaVersion: Int
    let generatorVersion: String
    let catalogVersion: String
    let seedHex: String
    let trajectory: Int
    let sizeRhythm: Int
    let spacing: Float
    let background: SIMD4<Float>
    var glitchType: Int
    var intersectionType: Int
    var intersectionStrength: Float
    var glitchStrength: Float? = nil
    var locks: Set<String> = []
    var actors: [Actor]

    var isSupported: Bool {
        schemaVersion == 1 && generatorVersion == "atlas-1" && catalogVersion == "2026-09-09"
    }

    static func make(dayKey: String) -> Self {
        let seed = CanvasElement.makeSeed(optionId: "native-atlas", dayKey: dayKey, index: 0)
        var rng = SeededRNG(seed: seed)
        let trajectory = rng.nextInt(in: 0...7), rhythm = rng.nextInt(in: 0...5)
        let spacing = Float(rng.nextDouble(in: 0.38...0.78))
        let light = rng.nextInt(in: 0...1) == 0
        let base: Float = light ? 0.76 : 0.025
        let background = SIMD4<Float>(base + Float(rng.nextDouble(in: 0...0.12)), base + Float(rng.nextDouble(in: 0...0.12)), base + Float(rng.nextDouble(in: 0...0.12)), 1)
        return Self(schemaVersion: 1, generatorVersion: "atlas-1", catalogVersion: "2026-09-09", seedHex: String(seed, radix: 16), trajectory: trajectory, sizeRhythm: rhythm, spacing: spacing, background: background, glitchType: rng.nextInt(in: 0...4), intersectionType: rng.nextInt(in: 0...2), intersectionStrength: 0.5, actors: [])
    }

    func reconciled(eventIDs: [String]) -> Self {
        guard isSupported, let rootSeed = UInt64(seedHex, radix: 16) else { return self }
        var result = self, seen = Set<String>()
        let ids = Array(eventIDs.filter { seen.insert($0).inserted }.prefix(10))
        let retained = Dictionary(actors.map { ($0.eventID, $0) }, uniquingKeysWith: { first, _ in first })
        var usedSlots = Set(actors.filter { ids.contains($0.eventID) }.map(\.slot))
        result.actors = ids.enumerated().map { index, id in
            if let existing = retained[id] { return existing }
            let slot = (0..<10).first { !usedSlots.contains($0) } ?? index
            usedSlots.insert(slot)
            let seed = CanvasElement.makeSeed(optionId: id, dayKey: seedHex, index: 0)
            var rng = SeededRNG(seed: seed)
            let catalog = MetalShapeGenomeCatalog.presets
            // A scene may contain one family, two families, or the whole catalog.
            let mode = rootSeed % 3
            let familyIndex = Int(rootSeed % UInt64(catalog.count))
            let pool = mode == 0 ? [catalog[familyIndex]] : mode == 1 ? [catalog[familyIndex], catalog[(familyIndex + 3) % catalog.count]] : catalog
            let preset = pool[rng.nextInt(in: 0...(pool.count - 1))]
            let allowed = MetalShapeMaterial.allCases.filter {
                $0 != .proceduralContour && preset.compatibility.allowed.contains($0)
            }
            let material = allowed[rng.nextInt(in: 0...(allowed.count - 1))]
            let frame = MetalShapeGenomeFrame.make(preset: preset, material: material, seed: seed)
            // Progressive slot order spreads a sparse day across the same stable path.
            let slots: [Float] = [0.5, 0.05, 0.95, 0.25, 0.75, 0.15, 0.85, 0.35, 0.65, 0.45]
            let t = slots[slot], u = (t - 0.5) * spacing
            var p = SIMD2<Float>(0.5, 0.5)
            switch trajectory {
            case 0: p.y += u
            case 1: p.x += u
            case 2: p += SIMD2(u, u)
            case 3: p += SIMD2(u, -u)
            case 4: p += SIMD2(u, sin(t * 2 * .pi) * spacing * 0.28)
            case 5: p += SIMD2(cos(t * .pi * 1.4), sin(t * .pi * 1.4)) * spacing * 0.45
            case 6: p += SIMD2(cos(t * 2 * .pi), sin(t * 2 * .pi)) * spacing * 0.45
            default: p += SIMD2(Float(rng.nextDouble(in: -0.4...0.4)), Float(rng.nextDouble(in: -0.4...0.4)))
            }
            var size: Float = 0.34
            switch sizeRhythm {
            case 1: size *= Float(rng.nextDouble(in: 0.5...1.7))
            case 2: size *= 0.5 + t * 1.4
            case 3: size *= 1.9 - t * 1.4
            case 4: size *= 0.5 + 1.4 * sin(t * .pi)
            case 5: size *= index.isMultiple(of: 2) ? 1.4 : 0.65
            default: break
            }
            return Actor(eventID: id, presetID: preset.id, materialID: material, seedHex: String(seed, radix: 16), geometry: frame.geometry, material: frame.material, position: p, size: size, rotation: material == .sunset ? 0 : Float(rng.nextDouble(in: 0...(2 * .pi))), slot: slot)
        }
        return result
    }

    func remixed(seedKey: String) -> Self {
        guard isSupported else { return self }
        let generated = Self.make(dayKey: seedKey).reconciled(eventIDs: actors.map(\.eventID))
        var next = locks.contains("artwork") ? self : generated
        next.locks = locks
        let effects = locks.contains("effects") ? self : generated
        next.glitchType = effects.glitchType
        next.glitchStrength = effects.glitchStrength
        next.intersectionType = effects.intersectionType
        next.intersectionStrength = effects.intersectionStrength
        return next
    }
}
