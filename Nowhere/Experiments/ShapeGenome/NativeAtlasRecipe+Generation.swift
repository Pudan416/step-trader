import Foundation

extension NativeAtlasRecipe {
    static func make(
        dayKey: String,
        paletteCategories: Set<ModernPaletteCategory> = ModernPaletteSelection.all
    ) -> Self {
        return makeDaily(dayKey: dayKey, paletteCategories: paletteCategories)
    }

    /// Original generation remains available for historical reproduction.
    static func makeLegacy(dayKey: String, paletteCategories: Set<ModernPaletteCategory> = ModernPaletteSelection.all) -> Self {
        let seed = CanvasElement.makeSeed(optionId: "native-atlas", dayKey: dayKey, index: 0)
        var rng = SeededRNG(seed: seed)
        let trajectory = rng.nextInt(in: 0...7), rhythm = rng.nextInt(in: 0...5)
        let spacing = Float(rng.nextDouble(in: 0.38...0.78))
        let light = rng.nextInt(in: 0...1) == 0
        let base: Float = light ? 0.76 : 0.025
        let background = SIMD4<Float>(base + Float(rng.nextDouble(in: 0...0.12)), base + Float(rng.nextDouble(in: 0...0.12)), base + Float(rng.nextDouble(in: 0...0.12)), 1)
        return Self(schemaVersion: 1, generatorVersion: "atlas-1", catalogVersion: "2026-09-09", seedHex: String(seed, radix: 16), trajectory: trajectory, sizeRhythm: rhythm, spacing: spacing, background: background, glitchType: rng.nextInt(in: 0...8), intersectionType: rng.nextInt(in: 0...2), intersectionStrength: 0.5, actors: [], backgroundStyle: makeBackgroundStyle(dayKey: dayKey, recipeSeed: seed, paletteCategories: paletteCategories))
    }

    /// Older recipes never stored the selected palette. Use the original default
    /// selection, rather than reinterpreting them through today's preferences.
    func resolvedBackgroundStyle(dayKey: String) -> DayObjectMeshGradientStyle {
        backgroundStyle ?? Self.makeBackgroundStyle(
            dayKey: dayKey, recipeSeed: UInt64(seedHex, radix: 16) ?? 0,
            paletteCategories: ModernPaletteSelection.all, useLegacyStyle: true
        )
    }

    static func makeBackgroundStyle(
        dayKey: String, recipeSeed: UInt64,
        paletteCategories: Set<ModernPaletteCategory>,
        useLegacyStyle: Bool = false
    ) -> DayObjectMeshGradientStyle {
        let rootSeed = CanvasElement.makeSeed(
            optionId: "dayObjects:primary-canvas", dayKey: dayKey, index: 0
        )
        let palette = DayObjectPaletteSet.backgroundPalette(
            rootSeed: rootSeed, categories: paletteCategories,
            dayKey: dayKey, identity: "primary-canvas", useLegacyCatalog: useLegacyStyle
        )
        let colors = DayObjectPalette.make(modernPalette: palette)
        var style = useLegacyStyle
            ? DayObjectMeshGradientStyle.legacyPrimaryCanvas(seed: recipeSeed, palette: colors)
            : DayObjectMeshGradientStyle.primaryCanvas(seed: recipeSeed, palette: colors)
        if palette.categories.contains(.noir) { style.isNoir = true }
        return style
    }

    /// Explicit Remix uses the full recipe seed, rather than calendar routing.
    /// Compare numerical swatches without order: reversing the same palette is
    /// not a new color group. Keep every candidate inside the selected categories.
    static func makeRemixBackgroundStyle(
        recipeSeed: UInt64, palettes: [ModernPalette],
        excluding previousColors: [SIMD3<Float>],
        previousArchetype: DayObjectMeshGradientArchetype? = nil
    ) -> DayObjectMeshGradientStyle {
        precondition(!palettes.isEmpty, "Modern palette catalog must not be empty")
        let previous = Set(previousColors)
        var seen = Set<Set<SIMD3<Float>>>()
        let candidates = palettes.compactMap { palette -> (palette: ModernPalette, colors: Set<SIMD3<Float>>)? in
            let colors = Set(palette.hexes.map { DayObjectRGB(hex: $0).linearRGB })
            return seen.insert(colors).inserted ? (palette, colors) : nil
        }
        func makeStyle(_ palette: ModernPalette) -> DayObjectMeshGradientStyle {
            var style = DayObjectMeshGradientStyle.primaryCanvas(seed: recipeSeed,
                palette: DayObjectPalette.make(modernPalette: palette), excluding: previousArchetype)
            if palette.categories.contains(.noir) { style.isNoir = true }
            return style
        }
        // Saved backgrounds may contain only two or three stops. Exclude every
        // catalog palette containing those stops, so a new stop count cannot
        // disguise selecting the old palette again. The normal tap path creates
        // only the chosen mesh; ambiguous shared stops use the bounded fallback.
        let alternatives = candidates.filter { previous.isEmpty || !previous.isSubset(of: $0.colors) }
        var rng = SeededRNG.derived(from: recipeSeed, domain: "native-remix-background-palette")
        if !alternatives.isEmpty {
            return makeStyle(alternatives[rng.nextInt(in: 0...(alternatives.count - 1))].palette)
        }
        let styles = candidates.map { makeStyle($0.palette) }
        let different = styles.filter { Set($0.colors) != previous }
        let available = different.isEmpty ? styles : different
        // A single eligible palette is retained deterministically. Its mesh
        // still rerolls, and reversing swatches never creates another candidate.
        return available[rng.nextInt(in: 0...(available.count - 1))]
    }

    func remixed(
        seedKey: String, dayKey: String? = nil,
        paletteCategories: Set<ModernPaletteCategory> = ModernPaletteSelection.all
    ) -> Self {
        guard isSupported else { return self }
        let collection = NativeAtlasDailyStyle.remixCollection(seedKey: seedKey, excluding: dailyStyle?.resolvedCollection)
        var generated = Self.makeDaily(dayKey: seedKey, paletteCategories: paletteCategories, collection: collection)
        let previousBackground = backgroundStyle ?? dayKey.map { resolvedBackgroundStyle(dayKey: $0) }
        let background = Self.makeRemixBackgroundStyle(
            recipeSeed: UInt64(generated.seedHex, radix: 16) ?? 0,
            palettes: ModernPaletteCatalog.palettes(matching: paletteCategories),
            excluding: previousBackground?.colors ?? dailyStyle?.palette ?? [],
            previousArchetype: previousBackground?.archetype
        )
        generated = generated.coordinated(with: background, paletteCategories: paletteCategories)
            .reconciled(eventIDs: actors.map(\.eventID))
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
