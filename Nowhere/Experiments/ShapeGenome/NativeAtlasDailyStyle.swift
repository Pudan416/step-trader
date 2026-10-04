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
        let variation = ordered ? Float(rng.nextDouble(in: -0.018...0.018))
            : (Float((seed >> 12) % 7) / 6 - 0.5) * 0.036
        if softGradients == true {
            let perceptualColors = colors.map { DayObjectRGB(linearRGB: $0).perceptualOKLab }
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
                let rgb = DayObjectRGB(linearRGB: colors[paletteIndex])
                    .fittingPerceptualLightness(to: target, chromaFraction: 0.75).linearRGB
                return SIMD4(rgb, 1)
            }
            var metadata = source.metadata
            if source.materialIndex == 6 {
                metadata.y |= 0x8000_0000
            }
            return .init(color0: softColor(0), color1: softColor(1), color2: materialID == .sideLight ? softColor(1) : softColor(2), params0: source.params0, params1: source.params1, params2: source.params2, params3: source.params3, metadata: metadata)
        }
        func color(_ index: Int) -> SIMD4<Float> {
            let rgb = DayObjectRGB(linearRGB: colors[(offset + index) % colors.count])
                .shiftingPerceptualLightness(by: separation + variation).linearRGB
            return SIMD4(rgb, 1)
        }
        return .init(color0: color(0), color1: color(1), color2: materialID == .sideLight ? color(1) : color(2), params0: source.params0, params1: source.params1, params2: source.params2, params3: source.params3, metadata: source.metadata)
    }
}
