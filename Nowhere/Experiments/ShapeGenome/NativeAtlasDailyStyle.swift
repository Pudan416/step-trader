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
        let offset = Int(seed % UInt64(colors.count))
        let meanLightness = colors.reduce(Float(0)) {
            $0 + DayObjectRGB(linearRGB: $1).perceptualOKLab.x
        } / Float(colors.count)
        let separation: Float = meanLightness > 0.6 ? -0.07 : 0.07
        let variation = (Float((seed >> 12) % 7) / 6 - 0.5) * 0.036
        func color(_ index: Int) -> SIMD4<Float> {
            let rgb = DayObjectRGB(linearRGB: colors[(offset + index) % colors.count])
                .shiftingPerceptualLightness(by: separation + variation).linearRGB
            return SIMD4(rgb, 1)
        }
        return .init(color0: color(0), color1: color(1), color2: materialID == .sideLight ? color(1) : color(2), params0: source.params0, params1: source.params1, params2: source.params2, params3: source.params3, metadata: source.metadata)
    }
}
