import Foundation
import simd

extension NativeAtlasRecipe {
    static func makeDaily(dayKey: String, paletteCategories: Set<ModernPaletteCategory>) -> Self {
        var recipe = makeLegacy(dayKey: dayKey, paletteCategories: paletteCategories)
        let seed = UInt64(recipe.seedHex, radix: 16) ?? 0
        var rng = SeededRNG(seed: seed ^ 0x4441_494C_5953_5459)
        let family = NativeAtlasDailyStyle.family(dayKey: dayKey)
        let presetID: String
        switch family {
        case .circles: presetID = "legacy.circle"
        case .blobs: presetID = "genome.soft-drift"
        case .squares: presetID = rng.nextInt(in: 0...1) == 0 ? "legacy.soft-square" : "genome.concave-square"
        case .clovers: presetID = "genome.soft-clover"
        case .flowers: presetID = "genome.windflower"
        case .rays: presetID = "genome.snowflake"
        }
        // Stable IDs, never global catalog order, define the v2 family mapping.
        guard let preset = MetalShapeGenomeCatalog.presets.first(where: { $0.id == presetID }) else { return recipe }
        let candidates: [MetalShapeMaterial] = [.sideLight, .radialTwo, .proceduralLight, .contour, .eclipseGlow]
        let allowed = candidates.filter { preset.compatibility.allowed.contains($0) }
        let materialID = allowed[rng.nextInt(in: 0...(allowed.count - 1))]
        let frame = MetalShapeGenomeFrame.make(preset: preset, material: materialID, seed: seed)
        let geometry: MetalShapeGenomeUniforms
        if family == .rays {
            // A single folded harmonic gives clear rounded rays, with no branches
            // or notches. Uses the unchanged Snowflake CPU/GPU packing contract.
            let folds = [5, 6, 8][rng.nextInt(in: 0...2)]
            let amplitude = Float(rng.nextDouble(in: 0.32...0.43))
            geometry = .init(superformula: SIMD4(Float(folds), 1, 0, 0), harmonic0: SIMD4(1, amplitude, 0, 0), harmonic1: .zero, harmonic2: .zero, anisotropyOffset: SIMD4(1, 1, 0, 0), transform: SIMD4(0, 1 / (1 + amplitude), 0, 0.5), metadata: SIMD4(2, UInt32(truncatingIfNeeded: seed), UInt32(folds), 1), reserved: .zero)
        } else { geometry = frame.geometry }
        var style = NativeAtlasDailyStyle(family: family, presetID: presetID, materialID: materialID, palette: recipe.backgroundStyle?.colors ?? [], shape: geometry, material: frame.material, orientation: Float(rng.nextDouble(in: 0...(2 * .pi))), sharesPaletteOrder: true, softGradients: true)
        style.material = style.recolored(frame.material, seed: seed)
        recipe = Self(schemaVersion: 1, generatorVersion: "atlas-2", catalogVersion: recipe.catalogVersion, seedHex: recipe.seedHex, trajectory: recipe.trajectory, sizeRhythm: recipe.sizeRhythm, spacing: recipe.spacing, background: recipe.background, glitchType: recipe.glitchType, intersectionType: recipe.intersectionType, intersectionStrength: recipe.intersectionStrength, actors: [], backgroundStyle: recipe.backgroundStyle, dailyStyle: style)
        return recipe
    }

    /// Explicit palette edits coordinate current actors and future additions.
    /// atlas-1 retains its original frozen materials.
    func coordinated(with background: DayObjectMeshGradientStyle) -> Self {
        var result = self
        result.backgroundStyle = background
        guard var style = dailyStyle, generatorVersion == "atlas-2" else { return result }
        style.palette = background.colors
        style.material = style.recolored(style.material, seed: UInt64(seedHex, radix: 16) ?? 0)
        result.dailyStyle = style
        result.actors = actors.map { actor in
            Actor(eventID: actor.eventID, presetID: actor.presetID, materialID: actor.materialID, seedHex: actor.seedHex, geometry: actor.geometry, material: style.recolored(actor.material, seed: UInt64(actor.seedHex, radix: 16) ?? 0), position: actor.position, size: actor.size, rotation: actor.rotation, slot: actor.slot)
        }
        return result
    }

    func reconciledDaily(eventIDs: [String]) -> Self {
        guard isSupported, let style = dailyStyle else { return self }
        var result = self, seen = Set<String>()
        let ids = Array(eventIDs.filter { seen.insert($0).inserted }.prefix(10))
        let retained = Dictionary(actors.map { ($0.eventID, $0) }, uniquingKeysWith: { first, _ in first })
        var used = Set(actors.filter { ids.contains($0.eventID) }.map(\.slot))
        // Progressive occupancy covers the canvas at sparse and dense counts.
        // Each slot is independent of event count; removal never moves actors.
        let slots: [SIMD2<Float>] = [SIMD2(0.50, 0.50), SIMD2(0.29, 0.30), SIMD2(0.71, 0.70), SIMD2(0.72, 0.29), SIMD2(0.28, 0.71), SIMD2(0.50, 0.20), SIMD2(0.50, 0.80), SIMD2(0.20, 0.49), SIMD2(0.80, 0.51), SIMD2(0.51, 0.62)]
        result.actors = ids.map { id in
            if let existing = retained[id] { return existing }
            let slot = (0..<10).first { !used.contains($0) } ?? 0
            used.insert(slot)
            let seed = CanvasElement.makeSeed(optionId: id, dayKey: seedHex, index: 0)
            var rng = SeededRNG(seed: seed)
            let airy = style.family == .rays || style.family == .flowers || style.family == .clovers
            let baseSize: Float = style.family == .rays ? 0.22 : airy ? 0.27 : 0.34
            let size = baseSize * Float(rng.nextDouble(in: 0.85...1.12))
            var position = slots[slot]
            if style.family == .squares {
                // A tighter grid and common orientation lend squares order.
                position = SIMD2(0.5, 0.5) + (position - SIMD2(0.5, 0.5)) * 0.9
            } else {
                let jitter: Float = airy ? 0.012 : 0.025
                position += SIMD2(Float(rng.nextDouble(in: Double(-jitter)...Double(jitter))), Float(rng.nextDouble(in: Double(-jitter)...Double(jitter))))
            }
            let angleRange: Double = style.family == .squares ? 0.06 : 0.18
            let rotation = style.orientation + Float(rng.nextDouble(in: -angleRange...angleRange))
            var params0 = style.material.params0
            params0.x += Float(rng.nextDouble(in: -0.025...0.025))
            let material = MetalShapeMaterialUniforms(color0: style.material.color0, color1: style.material.color1, color2: style.material.color2, params0: params0, params1: style.material.params1, params2: style.material.params2, params3: style.material.params3, metadata: style.material.metadata)
            return Actor(eventID: id, presetID: style.presetID, materialID: style.materialID, seedHex: String(seed, radix: 16), geometry: style.shape, material: style.recolored(material, seed: seed), position: position, size: size, rotation: rotation, slot: slot)
        }
        return result
    }
}
