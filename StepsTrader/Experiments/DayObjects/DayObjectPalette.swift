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

/// One shared static-radial art direction for every figure in a daily scene.
/// The palette subset and geometry remain stable for the day; individual
/// actors receive only a small deterministic phase variation in the shader.
enum DayObjectRadialPreset: UInt32, CaseIterable, Equatable {
    case `default`
    case radial
    case loFi
    case crossSections
}

struct DayObjectRadialFillStyle: Equatable {
    let colors: [SIMD3<Float>]
    let radius: Double
    let focalDistance: Double
    let focalAngle: Double
    let falloff: Double
    let mixing: Double
    let distortion: Double
    let distortionShift: Double
    let distortionFrequency: Int
    let rotation: Double
    let offset: SIMD2<Double>
    let preset: DayObjectRadialPreset
    let banding: Double

    init(
        colors: [SIMD3<Float>],
        radius: Double,
        focalDistance: Double,
        focalAngle: Double,
        falloff: Double,
        mixing: Double,
        distortion: Double,
        distortionShift: Double,
        distortionFrequency: Int,
        rotation: Double,
        offset: SIMD2<Double>,
        preset: DayObjectRadialPreset = .default,
        banding: Double = 0
    ) {
        self.colors = colors
        self.radius = radius
        self.focalDistance = focalDistance
        self.focalAngle = focalAngle
        self.falloff = falloff
        self.mixing = mixing
        self.distortion = distortion
        self.distortionShift = distortionShift
        self.distortionFrequency = distortionFrequency
        self.rotation = rotation
        self.offset = offset
        self.preset = preset
        self.banding = banding
    }

    static let fallback = DayObjectRadialFillStyle(
        colors: [SIMD3<Float>(repeating: 1)],
        radius: 0.9,
        focalDistance: 0,
        focalAngle: 0,
        falloff: 0,
        mixing: 0.6,
        distortion: 0,
        distortionShift: 0,
        distortionFrequency: 4,
        rotation: 0,
        offset: .zero
    )

    static func make(
        seed: UInt64,
        palette: DayObjectPalette,
        colorCount rawColorCount: Int
    ) -> DayObjectRadialFillStyle {
        var rng = SeededRNG.derived(from: seed, domain: "dayObjectRadialFill")
        var available = Array(palette.colors.indices)
        let colorCount = min(max(rawColorCount, 1), min(3, available.count))
        var colors = [SIMD3<Float>]()
        colors.reserveCapacity(colorCount)
        for _ in 0..<colorCount {
            let availableIndex = rng.nextInt(in: 0...(available.count - 1))
            colors.append(
                palette.colors[available.remove(at: availableIndex)]
                    .lightened(
                        toMinimumContrast: 1.35,
                        against: palette.backgroundBase
                    )
                    .linearRGB
            )
        }

        let preset = DayObjectRadialPreset.allCases[
            rng.nextInt(in: 0...(DayObjectRadialPreset.allCases.count - 1))
        ]
        let radius: ClosedRange<Double>
        let focalDistance: ClosedRange<Double>
        let falloff: ClosedRange<Double>
        let mixing: ClosedRange<Double>
        let distortion: ClosedRange<Double>
        let distortionShift: ClosedRange<Double>
        let distortionFrequency: ClosedRange<Int>
        let banding: ClosedRange<Double>
        switch preset {
        case .default:
            radius = 0.72...1.18
            focalDistance = 0.18...0.72
            falloff = -0.15...0.45
            mixing = 0.55...1
            distortion = 0.10...0.38
            distortionShift = -0.38...0.38
            distortionFrequency = 3...7
            banding = 0...0.08
        case .radial:
            radius = 0.68...1.12
            focalDistance = 0...0.28
            falloff = -0.10...0.35
            mixing = 0.70...1
            distortion = 0...0.16
            distortionShift = -0.24...0.24
            distortionFrequency = 2...5
            banding = 0...0.04
        case .loFi:
            radius = 0.60...1.15
            focalDistance = 0.05...0.55
            falloff = -0.15...0.35
            mixing = 0.65...1
            distortion = 0.08...0.32
            distortionShift = -0.40...0.40
            distortionFrequency = 2...6
            banding = 0.22...0.55
        case .crossSections:
            radius = 0.62...1.10
            focalDistance = 0.18...0.68
            falloff = -0.12...0.38
            mixing = 0.72...1
            distortion = 0.22...0.58
            distortionShift = -0.50...0.50
            distortionFrequency = 4...10
            banding = 0.08...0.28
        }

        return DayObjectRadialFillStyle(
            colors: colors,
            radius: rng.nextDouble(in: radius),
            focalDistance: rng.nextDouble(in: focalDistance),
            focalAngle: rng.nextDouble(in: 0...(2 * .pi - Double.ulpOfOne)),
            falloff: rng.nextDouble(in: falloff),
            mixing: rng.nextDouble(in: mixing),
            distortion: rng.nextDouble(in: distortion),
            distortionShift: rng.nextDouble(in: distortionShift),
            distortionFrequency: rng.nextInt(in: distortionFrequency),
            rotation: rng.nextDouble(in: 0...(2 * .pi - Double.ulpOfOne)),
            offset: SIMD2(
                rng.nextDouble(in: -0.24...0.24),
                rng.nextDouble(in: -0.24...0.24)
            ),
            preset: preset,
            banding: rng.nextDouble(in: banding)
        )
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
            distortion = rng.nextDouble(in: 0.12...0.32)
            swirl = rng.nextDouble(in: -0.05...0.05)
            speed = rng.nextDouble(in: 0.06...0.11)
            scale = rng.nextDouble(in: 0.82...1.20)
        case .orbit:
            distortion = rng.nextDouble(in: 0.42...0.82)
            swirl = direction * rng.nextDouble(in: 0.28...0.68)
            speed = rng.nextDouble(in: 0.07...0.13)
            scale = rng.nextDouble(in: 0.84...1.22)
        case .tide:
            distortion = rng.nextDouble(in: 0.45...0.85)
            swirl = rng.nextDouble(in: -0.12...0.12)
            speed = rng.nextDouble(in: 0.05...0.10)
            scale = rng.nextDouble(in: 0.78...1.18)
        case .islands:
            distortion = rng.nextDouble(in: 0.12...0.45)
            swirl = rng.nextDouble(in: -0.18...0.18)
            speed = rng.nextDouble(in: 0.08...0.16)
            scale = rng.nextDouble(in: 0.90...1.40)
        case .bloom:
            distortion = rng.nextDouble(in: 0.25...0.62)
            swirl = rng.nextDouble(in: -0.25...0.25)
            speed = rng.nextDouble(in: 0.045...0.09)
            scale = rng.nextDouble(in: 0.72...1.15)
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
