import Foundation
import simd

/// The day's art direction, frozen independently of actor count and catalog edits.
struct NativeAtlasDailyStyle: Codable, Equatable {
    enum Family: String, Codable, CaseIterable {
        case circles, blobs, squares, clovers, flowers, rays
    }

    let family: Family
    let presetID: String
    let materialID: MetalShapeMaterial
    var palette: [SIMD3<Float>]
    let shape: MetalShapeGenomeUniforms
    var material: MetalShapeMaterialUniforms
    let orientation: Float
    /// Missing in saved atlas-2 artwork; preserve its original color policy.
    var sharesPaletteOrder: Bool? = nil
    /// Missing in historical artwork; opt in without changing its frozen policy.
    var softGradients: Bool? = nil
    /// Opt-in actor diversity and perceptible idle motion; archives keep their policy.
    var livingVariation: Bool? = nil

    /// Shuffle each calendar block of six. Repair only the first two entries,
    /// leaving the last entry stable so the preceding block needs no recursion.
    static func family(dayKey: String) -> Family {
        let datePart = String(dayKey.prefix(10))
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let ordinal: Int
        if let date = formatter.date(from: datePart) {
            ordinal = Int(floor(date.timeIntervalSince1970 / 86400))
        } else {
            ordinal = Int(CanvasElement.makeSeed(optionId: "daily-family", dayKey: dayKey, index: 0) % 100_000)
        }
        let block = Int(floor(Double(ordinal) / 6))
        let offset = ordinal - block * 6
        func shuffled(_ cycle: Int) -> [Family] {
            var values = Family.allCases
            var rng = SeededRNG(seed: CanvasElement.makeSeed(optionId: "daily-family-cycle", dayKey: String(cycle), index: 0))
            for i in stride(from: values.count - 1, through: 1, by: -1) {
                values.swapAt(i, rng.nextInt(in: 0...i))
            }
            return values
        }
        var values = shuffled(block)
        if values[0] == shuffled(block - 1).last { values.swapAt(0, 1) }
        return values[offset]
    }

    /// Called explicitly by today's unlocked Canvas adoption, never decoding.
    func adoptingLivingVariation(seed: UInt64) -> Self {
        var result = self
        if family == .rays, livingVariation != true,
           let beam = MetalShapeGenomeCatalog.presets.first(where: { $0.id == "legacy.rounded-triangle" }) {
            // The existing directional-blur branch opens this contour into a
            // diffuse directed beam. Fresh uniforms cannot inherit a light flag.
            let frame = MetalShapeGenomeFrame.make(preset: beam, material: .directionalBlur, seed: seed)
            result = Self(family: family, presetID: beam.id, materialID: .directionalBlur,
                          palette: palette, shape: frame.geometry, material: frame.material,
                          orientation: orientation, sharesPaletteOrder: true,
                          softGradients: true, livingVariation: true)
        }
        result.livingVariation = true
        return result
    }

    func recolored(_ source: MetalShapeMaterialUniforms, seed: UInt64) -> MetalShapeMaterialUniforms {
        // Frozen background colors are already linear RGB, matching the shader.
        let colors = palette.isEmpty ? [SIMD3<Float>(repeating: 0.5)] : palette
        // Keep the same dominant hues across the day's figures. Picker variants
        // include an identity hash even before a reroll, so neither that hash
        // nor an actor seed may rotate the shared palette.
        let ordered = sharesPaletteOrder == true
        let offset = ordered ? 0 : Int(seed % UInt64(colors.count))
        let meanLightness = colors.reduce(Float(0)) {
            $0 + DayObjectRGB(linearRGB: $1).perceptualOKLab.x
        } / Float(colors.count)
        let separation: Float = meanLightness > 0.6 ? -0.07 : 0.07
        var rng = SeededRNG(seed: seed ^ 0x5049_474D_454E_5453)
        let living = livingVariation == true
        let variation = ordered ? Float(rng.nextDouble(in: living ? -0.055...0.055 : -0.018...0.018))
            : (Float((seed >> 12) % 7) / 6 - 0.5) * 0.036
        if softGradients == true {
            // Bias the whole ordered gradient toward a member of the day's
            // palette. Absolute palette/seed input prevents cumulative tint
            // when the current day is adopted again or its colors are edited.
            let emphasis = living ? Float(rng.nextDouble(in: 0.12...0.32)) : 0
            let anchor = colors[living ? rng.nextInt(in: 0...(colors.count - 1)) : 0]
            let chroma = living ? Float(rng.nextDouble(in: 0.68...0.88)) : 0.75
            let pigments = colors.map { $0 + (anchor - $0) * emphasis }
            let perceptualColors = pigments.map { DayObjectRGB(linearRGB: $0).perceptualOKLab }
            let minimum = perceptualColors.map(\.x).min() ?? meanLightness
            let maximum = perceptualColors.map(\.x).max() ?? meanLightness
            let midpoint = (minimum + maximum) * 0.5
            let lightnessScale = min(1, 0.19 / max(maximum - minimum, 0.000_001))
            // Keep palette context, while moving extreme palettes toward a
            // moderate field. All stops share the actor's small seed variation.
            let center = min(max(meanLightness * 0.70 + 0.60 * 0.30, 0.32), 0.80)
            func softColor(_ index: Int) -> SIMD4<Float> {
                let paletteIndex = (offset + index) % colors.count
                let target = center + (perceptualColors[paletteIndex].x - midpoint) * lightnessScale + variation
                let rgb = DayObjectRGB(linearRGB: pigments[paletteIndex])
                    .fittingPerceptualLightness(to: target, chromaFraction: chroma).linearRGB
                return SIMD4(rgb, 1)
            }
            var metadata = source.metadata
            if source.materialIndex == 6 {
                metadata.y |= 0x8000_0000
            }
            var firstColor = softColor(0)
            if living, family == .rays, source.materialIndex == 3, source.metadata.y == 0 {
                // The diffuse beam's mode 0 uses only color0. A dark shared
                // endpoint vanishes at its soft edge, so give this light role
                // a muted tone from the brighter half of the same pigments.
                let ranked = pigments.indices.sorted {
                    let left = perceptualColors[$0].x, right = perceptualColors[$1].x
                    return left == right ? $0 < $1 : left > right
                }
                var beamRNG = SeededRNG(seed: seed ^ 0x4245_414D_544F_4E45)
                let count = max(1, (ranked.count + 1) / 2)
                let selected = ranked[beamRNG.nextInt(in: 0...(count - 1))]
                let target = min(max(perceptualColors[selected].x + 0.08 + variation * 0.4, 0.72), 0.82)
                firstColor = SIMD4(DayObjectRGB(linearRGB: pigments[selected])
                    .fittingPerceptualLightness(to: target, chromaFraction: min(chroma, 0.75)).linearRGB, 1)
            }
            return .init(color0: firstColor, color1: softColor(1), color2: materialID == .sideLight ? softColor(1) : softColor(2), params0: source.params0, params1: source.params1, params2: source.params2, params3: source.params3, metadata: metadata)
        }
        func color(_ index: Int) -> SIMD4<Float> {
            let rgb = DayObjectRGB(linearRGB: colors[(offset + index) % colors.count])
                .shiftingPerceptualLightness(by: separation + variation).linearRGB
            return SIMD4(rgb, 1)
        }
        return .init(color0: color(0), color1: color(1), color2: materialID == .sideLight ? color(1) : color(2), params0: source.params0, params1: source.params1, params2: source.params2, params3: source.params3, metadata: source.metadata)
    }

    func actorSize(base: Float, slot: Int, seed: UInt64, legacyScale: Float) -> Float {
        guard livingVariation == true else { return base * legacyScale }
        // Stable slots alternate large, small and medium figures immediately,
        // even on a sparse day. Event additions/removals never rescale survivors.
        let tiers: [Float] = [1.18, 0.70, 0.96, 0.65, 1.10, 0.82, 1.25, 0.72, 1.02, 0.90]
        var rng = SeededRNG(seed: seed ^ 0x5349_5A45_5449_4552)
        let tier = tiers[min(max(slot, 0), tiers.count - 1)]
        let scale = min(max(tier + Float(rng.nextDouble(in: -0.03...0.03)), 0.65), 1.25)
        return base * scale
    }

    func variedMaterial(_ source: MetalShapeMaterialUniforms, seed: UInt64) -> MetalShapeMaterialUniforms {
        guard livingVariation == true else { return source }
        var rng = SeededRNG(seed: seed ^ 0x4D41_5445_5249_414C)
        var params1 = source.params1, params2 = source.params2
        // Directed beams keep their local axis; the frozen actor rotation owns
        // their aim. Other fills can share a material with different light paths.
        if materialID != .directionalBlur {
            let angle = Float(rng.nextDouble(in: -0.22...0.22))
            let direction = source.direction
            params1.x = direction.x * cos(angle) - direction.y * sin(angle)
            params1.y = direction.x * sin(angle) + direction.y * cos(angle)
        }
        if materialID == .proceduralLight {
            for index in 0..<4 {
                params2[index] = min(max(params2[index] + Float(rng.nextDouble(in: -0.10...0.10)), 0), 1)
            }
        }
        return .init(color0: source.color0, color1: source.color1, color2: source.color2,
                     params0: source.params0, params1: params1, params2: params2,
                     params3: source.params3, metadata: source.metadata)
    }
}
