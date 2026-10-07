import Foundation
import simd

extension NativeAtlasRecipe {
    static func makeDaily(
        dayKey: String, paletteCategories: Set<ModernPaletteCategory>,
        family selectedFamily: NativeAtlasDailyStyle.Family? = nil,
        collection selectedCollection: NativeAtlasDailyStyle.Collection? = nil
    ) -> Self {
        var recipe = makeLegacy(dayKey: dayKey, paletteCategories: paletteCategories)
        let seed = UInt64(recipe.seedHex, radix: 16) ?? 0
        var rng = SeededRNG(seed: seed ^ 0x4441_494C_5953_5459)
        let collection = selectedCollection ?? selectedFamily.map { .regular(for: $0) }
            ?? NativeAtlasDailyStyle.collection(dayKey: dayKey)
        let family = collection.family
        let presetID: String
        switch collection {
        case .circles, .blurredCircles, .glowingContours: presetID = "legacy.circle"
        case .blobs: presetID = "genome.soft-drift"
        case .squares: presetID = rng.nextInt(in: 0...1) == 0 ? "legacy.soft-square" : "genome.concave-square"
        case .blurredSquares: presetID = "legacy.soft-square"
        case .clovers: presetID = "genome.soft-clover"
        case .flowers: presetID = rng.nextInt(in: 0...1) == 0 ? "genome.windflower" : "genome.snowflake"
        case .rays: presetID = "legacy.rounded-triangle"
        case .waterRipples: presetID = "genome.concentric-ripple"
        case .dimpledSpheres: presetID = "reference.dimpled-sphere"
        case .spiralRays: presetID = "reference.spiral-rays"
        }
        // Stable IDs, never global catalog order, define the v2 family mapping.
        guard let preset = MetalShapeGenomeCatalog.presets.first(where: { $0.id == presetID }) else { return recipe }
        // Blur is a complete collection, never a fill mixed into another look.
        let candidates: [MetalShapeMaterial] = collection.isGlowingContour ? [.eclipseGlow]
            : collection.isBlurred ? [.directionalBlur]
            : NativeAtlasDailyStyle.referenceMaterials(for: preset).filter { $0 != .directionalBlur }
        let allowed = candidates.filter { preset.compatibility.allowed.contains($0) }
        let materialID = allowed[rng.nextInt(in: 0...(allowed.count - 1))]
        let frame = MetalShapeGenomeFrame.make(preset: preset, material: materialID, seed: seed)
        var style = NativeAtlasDailyStyle(family: family, presetID: presetID, materialID: materialID, palette: recipe.backgroundStyle?.colors ?? [], shape: frame.geometry, material: frame.material, orientation: Float(rng.nextDouble(in: 0...(2 * .pi))), sharesPaletteOrder: true, softGradients: true, livingVariation: true)
        if let background = recipe.backgroundStyle {
            style.freezeApprovedAppearance(background: background, categories: paletteCategories, seed: seed)
        }
        style.silhouettePolicyVersion = 1
        style.collection = collection
        style.freezeReferenceMaterials(seed: seed)
        style.material = style.recolored(frame.material, seed: seed)
        recipe = Self(schemaVersion: 1, generatorVersion: "atlas-4", catalogVersion: recipe.catalogVersion, seedHex: recipe.seedHex, trajectory: recipe.trajectory, sizeRhythm: recipe.sizeRhythm, spacing: recipe.spacing, background: recipe.background, glitchType: recipe.glitchType, intersectionType: recipe.intersectionType, intersectionStrength: recipe.intersectionStrength, actors: [], backgroundStyle: recipe.backgroundStyle, dailyStyle: style)
        return recipe
    }

    /// Explicit palette edits coordinate current actors and future additions.
    /// atlas-1 retains its original frozen materials.
    func coordinated(with background: DayObjectMeshGradientStyle, paletteCategories: Set<ModernPaletteCategory>? = nil) -> Self {
        var result = self
        result.backgroundStyle = background
        guard var style = dailyStyle, generatorVersion == "atlas-2" || generatorVersion == "atlas-3" || generatorVersion == "atlas-4" else { return result }
        let paletteChanged = style.palette != background.colors || backgroundStyle?.isNoir != background.isNoir
        style.palette = background.colors
        if style.usesApprovedAppearance, paletteChanged {
            style.freezeApprovedAppearance(background: background,
                categories: paletteCategories ?? Set(style.neighboringPaletteCategories ?? ModernPaletteCategory.allCases),
                seed: UInt64(seedHex, radix: 16) ?? 0)
        }
        style.material = style.recolored(style.material, seed: UInt64(seedHex, radix: 16) ?? 0)
        result.dailyStyle = style
        result.actors = actors.map { actor in
            Actor(eventID: actor.eventID, presetID: actor.presetID, materialID: actor.materialID, seedHex: actor.seedHex, geometry: actor.geometry, material: style.recolored(actor.material, seed: UInt64(actor.seedHex, radix: 16) ?? 0, slot: actor.slot), position: actor.position, size: actor.size, rotation: actor.rotation, slot: actor.slot)
        }
        return result
    }

    func reconciledDaily(eventIDs: [String]) -> Self {
        guard isSupported, dailyStyle != nil else { return self }
        var result = self, seen = Set<String>()
        let ids = Array(eventIDs.filter { seen.insert($0).inserted }.prefix(10))
        let retained = Dictionary(actors.map { ($0.eventID, $0) }, uniquingKeysWith: { first, _ in first })
        var used = Set(actors.filter { ids.contains($0.eventID) }.map(\.slot))
        // Progressive occupancy covers the canvas at sparse and dense counts.
        // Each slot is independent of event count; removal never moves actors.
        result.actors = ids.compactMap { id -> Actor? in
            if let existing = retained[id] { return existing }
            let slot = (0..<10).first { !used.contains($0) } ?? 0
            used.insert(slot)
            return dailyActor(eventID: id, slot: slot)
        }
        return result
    }

    /// Resolve a specific stable slot, including a recovered actor's saved slot.
    /// Archived styles consume the same original RNG draws and keep their sizes.
    func dailyActor(eventID id: String, slot: Int) -> Actor? {
        guard let style = dailyStyle else { return nil }
        let slots: [SIMD2<Float>] = [SIMD2(0.50, 0.50), SIMD2(0.29, 0.30), SIMD2(0.71, 0.70), SIMD2(0.72, 0.29), SIMD2(0.28, 0.71), SIMD2(0.50, 0.20), SIMD2(0.50, 0.80), SIMD2(0.20, 0.49), SIMD2(0.80, 0.51), SIMD2(0.51, 0.62)]
        let seed = CanvasElement.makeSeed(optionId: id, dayKey: seedHex, index: 0)
        var rng = SeededRNG(seed: seed)
        var actorStyle = style
        let look = style.catalogLookOrder.flatMap { $0.indices.contains(slot) ? $0[slot] : nil }
        if let look {
            actorStyle.presetID = look.presetID
            actorStyle.materialID = look.materialID
            actorStyle.family = NativeAtlasDailyStyle.family(forPresetID: look.presetID)
            actorStyle.collection = .regular(for: actorStyle.family)
            if let preset = MetalShapeGenomeCatalog.presets.first(where: { $0.id == look.presetID }) {
                let frame = MetalShapeGenomeFrame.make(preset: preset, material: look.materialID, seed: seed)
                actorStyle.shape = frame.geometry
                actorStyle.material = frame.material
            }
        }
        let airy = actorStyle.family == .rays || actorStyle.family == .flowers || actorStyle.family == .clovers
        let baseSize: Float = actorStyle.family == .rays ? (style.livingVariation == true ? 0.34 : 0.22) : airy ? 0.27 : 0.34
        let legacyScale = Float(rng.nextDouble(in: 0.85...1.12))
        let size = actorStyle.actorSize(base: baseSize, slot: slot, seed: seed, legacyScale: legacyScale)
        var position = slots[min(max(slot, 0), slots.count - 1)]
        if actorStyle.family == .squares {
            // Preserve the tighter square grid independently of silhouette policy.
            position = SIMD2(0.5, 0.5) + (position - SIMD2(0.5, 0.5)) * 0.9
        } else {
            let jitter: Float = airy ? 0.012 : 0.025
            position += SIMD2(Float(rng.nextDouble(in: Double(-jitter)...Double(jitter))), Float(rng.nextDouble(in: Double(-jitter)...Double(jitter))))
        }
        let angleRange: Double = actorStyle.family == .squares ? 0.06 : (actorStyle.family == .rays && style.livingVariation == true ? 0.38 : 0.18)
        // Consume the archived draw even when the opt-in policy owns rotation.
        let legacyRotation = actorStyle.orientation + Float(rng.nextDouble(in: -angleRange...angleRange))
        let rotation = actorStyle.actorRotation(seed: seed, slot: slot, legacyRotation: legacyRotation)
        let actorMaterialID = look?.materialID ?? actorStyle.actorMaterialID(slot: slot)
        let actorMaterial: MetalShapeMaterialUniforms
        if style.usesApprovedAppearance,
           let preset = MetalShapeGenomeCatalog.presets.first(where: { $0.id == actorStyle.presetID }) {
            actorMaterial = MetalShapeGenomeFrame.make(preset: preset, material: actorMaterialID, seed: seed,
                blurMode: actorStyle.family == .rays && actorStyle.presetID != "legacy.rounded-triangle" ? 2 : 0).material
        } else { actorMaterial = actorStyle.material }
        var params0 = actorMaterial.params0
        params0.x += Float(rng.nextDouble(in: -0.025...0.025))
        let material = MetalShapeMaterialUniforms(color0: actorMaterial.color0, color1: actorMaterial.color1, color2: actorMaterial.color2, params0: params0, params1: actorMaterial.params1, params2: actorMaterial.params2, params3: actorMaterial.params3, metadata: actorMaterial.metadata)
        return Actor(eventID: id, presetID: actorStyle.presetID, materialID: actorMaterialID, seedHex: String(seed, radix: 16), geometry: actorStyle.actorGeometry(seed: seed, slot: slot), material: actorStyle.recolored(actorStyle.variedMaterial(material, seed: seed), seed: seed, slot: slot), position: position, size: size, rotation: rotation, slot: slot)
    }
}
