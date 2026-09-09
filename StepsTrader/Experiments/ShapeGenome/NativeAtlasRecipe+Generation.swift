import Foundation

extension NativeAtlasRecipe {
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
