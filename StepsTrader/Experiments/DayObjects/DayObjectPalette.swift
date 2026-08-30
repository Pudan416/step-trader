import Foundation

/// A colour represented in both display sRGB and the linear RGB space Metal
/// uses for blending.
struct DayObjectRGB: Equatable {
    let sRGB: SIMD3<Float>
    let linearRGB: SIMD3<Float>

    var perceptualOKLab: SIMD3<Float> {
        let color = DayObjectOKLab(linearRGB: linearRGB)
        return SIMD3(color.lightness, color.a, color.b)
    }

    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        precondition(value.count == 6, "DayObjectRGB requires a six-digit hex colour")

        let red = Float(Int(value.prefix(2), radix: 16) ?? 0) / 255
        let green = Float(Int(value.dropFirst(2).prefix(2), radix: 16) ?? 0) / 255
        let blue = Float(Int(value.dropFirst(4).prefix(2), radix: 16) ?? 0) / 255
        self.init(sRGB: SIMD3(red, green, blue))
    }

    init(sRGB: SIMD3<Float>) {
        self.sRGB = Self.clampedFinite(sRGB)
        linearRGB = SIMD3(
            Self.linearComponent(self.sRGB.x),
            Self.linearComponent(self.sRGB.y),
            Self.linearComponent(self.sRGB.z)
        )
    }

    private init(linearRGB: SIMD3<Float>) {
        self.linearRGB = Self.clampedFinite(linearRGB)
        sRGB = SIMD3(
            Self.sRGBComponent(self.linearRGB.x),
            Self.sRGBComponent(self.linearRGB.y),
            Self.sRGBComponent(self.linearRGB.z)
        )
    }

    func darkened(by factor: Float) -> DayObjectRGB {
        DayObjectRGB(sRGB: sRGB * min(max(factor, 0), 1))
    }

    func lightened(toMinimumContrast minimum: Double, against background: SIMD3<Float>) -> DayObjectRGB {
        let requiredLuminance = max(0, minimum * (relativeLuminance(background) + 0.05) - 0.05)
        let currentLuminance = relativeLuminance(linearRGB)
        guard currentLuminance < requiredLuminance else { return self }

        let whiteMix = Float((requiredLuminance - currentLuminance) / (1 - currentLuminance))
        return DayObjectRGB(linearRGB: linearRGB + (SIMD3(repeating: 1) - linearRGB) * min(max(whiteMix, 0), 1))
    }

    func shiftingPerceptualLightness(
        by shift: Float,
        minimumChromaFraction: Float = 0.55
    ) -> DayObjectRGB {
        let source = DayObjectOKLab(linearRGB: linearRGB)
        if abs(shift) < 0.000_001,
           (0.061...0.939).contains(source.lightness) {
            return self
        }
        var targetLightness = min(max(source.lightness + shift, 0.061), 0.939)
        let minimumScale = min(max(minimumChromaFraction, 0), 1)

        func candidate(chromaScale: Float, lightness: Float? = nil) -> SIMD3<Float> {
            DayObjectOKLab(
                lightness: lightness ?? targetLightness,
                a: source.a * chromaScale,
                b: source.b * chromaScale
            ).linearRGB
        }

        if DayObjectOKLab.isInDisplayGamut(candidate(chromaScale: 1)) {
            return DayObjectRGB(linearRGB: candidate(chromaScale: 1))
        }

        var lower = minimumScale
        var upper: Float = 1
        if !DayObjectOKLab.isInDisplayGamut(candidate(chromaScale: lower)) {
            // At the display-gamut boundary, retain the promised chroma and
            // give back only as much lightness shift as is necessary.
            let sourceBounded = min(max(source.lightness, 0.061), 0.939)
            var infeasible = targetLightness
            var feasible = sourceBounded
            guard DayObjectOKLab.isInDisplayGamut(
                candidate(chromaScale: lower, lightness: feasible)
            ) else {
                return self
            }
            for _ in 0..<12 {
                let midpoint = (infeasible + feasible) * 0.5
                if DayObjectOKLab.isInDisplayGamut(
                    candidate(chromaScale: lower, lightness: midpoint)
                ) {
                    feasible = midpoint
                } else {
                    infeasible = midpoint
                }
            }
            targetLightness = feasible
        }
        for _ in 0..<12 {
            let midpoint = (lower + upper) * 0.5
            if DayObjectOKLab.isInDisplayGamut(candidate(chromaScale: midpoint)) {
                lower = midpoint
            } else {
                upper = midpoint
            }
        }
        return DayObjectRGB(linearRGB: candidate(chromaScale: lower))
    }

    private static func linearComponent(_ value: Float) -> Float {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func sRGBComponent(_ value: Float) -> Float {
        value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    private static func clampedFinite(_ value: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(
            value.x.isFinite ? min(max(value.x, 0), 1) : 0,
            value.y.isFinite ? min(max(value.y, 0), 1) : 0,
            value.z.isFinite ? min(max(value.z, 0), 1) : 0
        )
    }
}

/// OKLab keeps hue and chroma perceptually stable while daily contrast moves
/// the whole actor family along one bounded lightness axis.
private struct DayObjectOKLab {
    let lightness: Float
    let a: Float
    let b: Float

    init(lightness: Float, a: Float, b: Float) {
        self.lightness = lightness
        self.a = a
        self.b = b
    }

    init(linearRGB: SIMD3<Float>) {
        let l = 0.412_221_46 * linearRGB.x
            + 0.536_332_55 * linearRGB.y
            + 0.051_445_995 * linearRGB.z
        let m = 0.211_903_5 * linearRGB.x
            + 0.680_699_5 * linearRGB.y
            + 0.107_396_96 * linearRGB.z
        let s = 0.088_302_46 * linearRGB.x
            + 0.281_718_85 * linearRGB.y
            + 0.629_978_7 * linearRGB.z
        let lRoot = cbrt(l)
        let mRoot = cbrt(m)
        let sRoot = cbrt(s)
        lightness = 0.210_454_26 * lRoot + 0.793_617_8 * mRoot - 0.004_072_047 * sRoot
        a = 1.977_998_5 * lRoot - 2.428_592_2 * mRoot + 0.450_593_7 * sRoot
        b = 0.025_904_037 * lRoot + 0.782_771_77 * mRoot - 0.808_675_77 * sRoot
    }

    var linearRGB: SIMD3<Float> {
        let lRoot = lightness + 0.396_337_78 * a + 0.215_803_76 * b
        let mRoot = lightness - 0.105_561_346 * a - 0.063_854_17 * b
        let sRoot = lightness - 0.089_484_18 * a - 1.291_485_5 * b
        let l = lRoot * lRoot * lRoot
        let m = mRoot * mRoot * mRoot
        let s = sRoot * sRoot * sRoot
        return SIMD3(
            4.076_741_7 * l - 3.307_711_6 * m + 0.230_969_94 * s,
            -1.268_438 * l + 2.609_757_4 * m - 0.341_319_38 * s,
            -0.004_196_086_3 * l - 0.703_418_6 * m + 1.707_614_7 * s
        )
    }

    static func isInDisplayGamut(_ color: SIMD3<Float>) -> Bool {
        color.x.isFinite && color.y.isFinite && color.z.isFinite
            && color.x >= 0 && color.x <= 1
            && color.y >= 0 && color.y <= 1
            && color.z >= 0 && color.z <= 1
    }
}

func relativeLuminance(_ linearRGB: SIMD3<Float>) -> Double {
    Double(linearRGB.x) * 0.2126
        + Double(linearRGB.y) * 0.7152
        + Double(linearRGB.z) * 0.0722
}

func contrastRatio(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Double {
    let lighter = max(relativeLuminance(lhs), relativeLuminance(rhs))
    let darker = min(relativeLuminance(lhs), relativeLuminance(rhs))
    return (lighter + 0.05) / (darker + 0.05)
}

struct DayObjectPalette: Equatable {
    let colors: [DayObjectRGB]
    let backgroundBase: SIMD3<Float>
    let backgroundFields: [SIMD3<Float>]
    let figurePrimary: SIMD3<Float>
    let figureSecondary: SIMD3<Float>
    let accent: SIMD3<Float>

    var minimumFigureContrast: Double {
        min(
            contrastRatio(figurePrimary, backgroundBase),
            contrastRatio(figureSecondary, backgroundBase),
            contrastRatio(accent, backgroundBase)
        )
    }

    static func make(
        seed: UInt64,
        categories: Set<ModernPaletteCategory> = []
    ) -> DayObjectPalette {
        let colors = selectedColors(seed: seed, categories: categories)
        return make(colors: colors)
    }

    static func make(modernPalette: ModernPalette) -> DayObjectPalette {
        make(colors: modernPalette.hexes.map(DayObjectRGB.init(hex:)))
    }

    private static func make(colors: [DayObjectRGB]) -> DayObjectPalette {
        precondition(colors.count >= 3, "Day Objects palettes require at least three colors")
        let baseIndex = colors.indices.min {
            relativeLuminance(colors[$0].linearRGB) < relativeLuminance(colors[$1].linearRGB)
        } ?? colors.startIndex
        let backgroundBase = colors[baseIndex].darkened(by: 0.08).linearRGB
        let backgroundFields = colors.indices
            .filter { $0 != baseIndex }
            .map { colors[$0].darkened(by: 0.30).linearRGB }

        let figures = colors
            .map { $0.lightened(toMinimumContrast: 1.35, against: backgroundBase).linearRGB }
            .sorted { contrastRatio($0, backgroundBase) > contrastRatio($1, backgroundBase) }

        return DayObjectPalette(
            colors: colors,
            backgroundBase: backgroundBase,
            backgroundFields: backgroundFields,
            figurePrimary: figures[0],
            figureSecondary: figures[1],
            accent: figures[2]
        )
    }

    private static func selectedColors(
        seed: UInt64,
        categories: Set<ModernPaletteCategory>
    ) -> [DayObjectRGB] {
        var rng = SeededRNG.derived(from: seed, domain: "dayObjectPalette")
        let palettes = ModernPaletteCatalog.palettes(matching: categories)
        let palette = palettes[rng.nextInt(in: 0...(palettes.count - 1))]
        return palette.hexes.map(DayObjectRGB.init(hex:))
    }
}

enum DayObjectMeshGradientArchetype: UInt32, CaseIterable, Equatable {
    case drift
    case orbit
    case tide
    case islands
    case bloom
}

/// The daily background's moving mesh-gradient art direction. A day retains
/// one curated topology and one direction; continuous values vary inside
/// bounded ranges so seeds feel related without collapsing into one vortex.
struct DayObjectMeshGradientStyle: Equatable {
    let colors: [SIMD3<Float>]
    let archetype: DayObjectMeshGradientArchetype
    let offset: SIMD2<Double>
    let distortion: Double
    let swirl: Double
    let speed: Double
    let scale: Double
    let phase: Double
    let motionDirection: Double

    init(
        colors: [SIMD3<Float>],
        archetype: DayObjectMeshGradientArchetype = .orbit,
        offset: SIMD2<Double> = .zero,
        distortion: Double,
        swirl: Double,
        speed: Double,
        scale: Double,
        phase: Double,
        motionDirection: Double = 1
    ) {
        self.colors = colors
        self.archetype = archetype
        self.offset = offset
        self.distortion = distortion
        self.swirl = swirl
        self.speed = speed
        self.scale = scale
        self.phase = phase
        self.motionDirection = motionDirection < 0 ? -1 : 1
    }

    static func make(seed: UInt64, palette: DayObjectPalette) -> DayObjectMeshGradientStyle {
        var rng = SeededRNG.derived(from: seed, domain: "dayObjectMeshGradient")
        let archetype = DayObjectMeshGradientArchetype.allCases[
            rng.nextInt(in: 0...(DayObjectMeshGradientArchetype.allCases.count - 1))
        ]
        let direction = rng.nextInt(in: 0...1) == 0 ? -1.0 : 1.0
        let offset = SIMD2(
            rng.nextDouble(in: -0.18...0.18),
            rng.nextDouble(in: -0.18...0.18)
        )
        let distortion: Double
        let swirl: Double
        let speed: Double
        let scale: Double
        switch archetype {
        case .drift:
            distortion = rng.nextDouble(in: 0.08...0.24)
            swirl = rng.nextDouble(in: -0.04...0.04)
            speed = rng.nextDouble(in: 0.045...0.085)
            scale = rng.nextDouble(in: 0.90...1.24)
        case .orbit:
            distortion = rng.nextDouble(in: 0.20...0.48)
            swirl = direction * rng.nextDouble(in: 0.00...0.42)
            speed = rng.nextDouble(in: 0.045...0.090)
            scale = rng.nextDouble(in: 0.92...1.26)
        case .tide:
            distortion = rng.nextDouble(in: 0.20...0.50)
            swirl = rng.nextDouble(in: -0.08...0.08)
            speed = rng.nextDouble(in: 0.040...0.080)
            scale = rng.nextDouble(in: 0.88...1.22)
        case .islands:
            distortion = rng.nextDouble(in: 0.08...0.30)
            swirl = rng.nextDouble(in: -0.12...0.12)
            speed = rng.nextDouble(in: 0.050...0.100)
            scale = rng.nextDouble(in: 0.96...1.34)
        case .bloom:
            distortion = rng.nextDouble(in: 0.14...0.38)
            swirl = rng.nextDouble(in: -0.16...0.16)
            speed = rng.nextDouble(in: 0.035...0.070)
            scale = rng.nextDouble(in: 0.86...1.18)
        }
        return DayObjectMeshGradientStyle(
            colors: palette.colors.map(\.linearRGB),
            archetype: archetype,
            offset: offset,
            distortion: distortion,
            swirl: swirl,
            speed: speed,
            scale: scale,
            phase: rng.nextDouble(in: 0...(2 * .pi - Double.ulpOfOne)),
            motionDirection: direction
        )
    }
}
