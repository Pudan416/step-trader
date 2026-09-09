import Foundation

/// Stable event slots and placement. Keep RNG consumption order compatible with atlas-1.
extension NativeAtlasRecipe {
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
}
