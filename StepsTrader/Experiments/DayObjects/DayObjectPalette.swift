import Foundation

/// A colour represented in both display sRGB and the linear RGB space Metal
/// uses for blending.
struct DayObjectRGB: Equatable {
    let sRGB: SIMD3<Float>
    let linearRGB: SIMD3<Float>

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
