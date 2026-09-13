import Foundation

extension NativeAtlasRecipe {
    static func make(
        dayKey: String,
        paletteCategories: Set<ModernPaletteCategory> = ModernPaletteSelection.all
    ) -> Self {
        let seed = CanvasElement.makeSeed(optionId: "native-atlas", dayKey: dayKey, index: 0)
        var rng = SeededRNG(seed: seed)
        let trajectory = rng.nextInt(in: 0...7), rhythm = rng.nextInt(in: 0...5)
        let spacing = Float(rng.nextDouble(in: 0.38...0.78))
        let light = rng.nextInt(in: 0...1) == 0
        let base: Float = light ? 0.76 : 0.025
        let background = SIMD4<Float>(base + Float(rng.nextDouble(in: 0...0.12)), base + Float(rng.nextDouble(in: 0...0.12)), base + Float(rng.nextDouble(in: 0...0.12)), 1)
        return Self(schemaVersion: 1, generatorVersion: "atlas-1", catalogVersion: "2026-09-09", seedHex: String(seed, radix: 16), trajectory: trajectory, sizeRhythm: rhythm, spacing: spacing, background: background, glitchType: rng.nextInt(in: 0...4), intersectionType: rng.nextInt(in: 0...2), intersectionStrength: 0.5, actors: [], backgroundStyle: makeBackgroundStyle(dayKey: dayKey, recipeSeed: seed, paletteCategories: paletteCategories))
    }

    /// Older recipes never stored the selected palette. Use the original default
    /// selection, rather than reinterpreting them through today's preferences.
    func resolvedBackgroundStyle(dayKey: String) -> DayObjectMeshGradientStyle {
        backgroundStyle ?? Self.makeBackgroundStyle(
            dayKey: dayKey, recipeSeed: UInt64(seedHex, radix: 16) ?? 0,
            paletteCategories: ModernPaletteSelection.all
        )
    }

    static func makeBackgroundStyle(
        dayKey: String, recipeSeed: UInt64,
        paletteCategories: Set<ModernPaletteCategory>
    ) -> DayObjectMeshGradientStyle {
        let rootSeed = CanvasElement.makeSeed(
            optionId: "dayObjects:primary-canvas", dayKey: dayKey, index: 0
        )
        let palette = DayObjectPaletteSet.backgroundPalette(
            rootSeed: rootSeed, categories: paletteCategories,
            dayKey: dayKey, identity: "primary-canvas"
        )
        return .primaryCanvas(seed: recipeSeed, palette: .make(modernPalette: palette))
    }

    func remixed(
        seedKey: String, dayKey: String? = nil,
        paletteCategories: Set<ModernPaletteCategory> = ModernPaletteSelection.all
    ) -> Self {
        guard isSupported else { return self }
        var generated = Self.make(dayKey: seedKey, paletteCategories: paletteCategories)
            .reconciled(eventIDs: actors.map(\.eventID))
        if let dayKey {
            generated.backgroundStyle = Self.makeBackgroundStyle(
                dayKey: dayKey, recipeSeed: UInt64(generated.seedHex, radix: 16) ?? 0,
                paletteCategories: paletteCategories
            )
        }
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
