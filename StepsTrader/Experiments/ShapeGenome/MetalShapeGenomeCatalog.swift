import Foundation

enum MetalShapeGenomeCatalog {
    static let presets: [MetalShapePreset] = genomePresets + legacyPresets

    private static let broadMaterials = Set(MetalShapeMaterial.allCases)
    private static let lightMaterials: Set<MetalShapeMaterial> = [
        .sideLight, .contour, .radialTwo, .radialThree, .proceduralLight,
        .proceduralFlow, .proceduralContour, .eclipseGlow,
    ]

    private static func policy(
        preferred: Set<MetalShapeMaterial>,
        allowed: Set<MetalShapeMaterial> = broadMaterials,
        roles: Set<MetalShapeRole>,
        size: ClosedRange<Float>,
        maxInstances: Int,
        complexity: Float,
        mass: Float,
        halo: Float = 0.08,
        blur: Float = 0.14
    ) -> MetalShapeCompatibility {
        MetalShapeCompatibility(
            preferred: preferred,
            allowed: allowed,
            roles: roles,
            minimumSize: size.lowerBound,
            maximumSize: size.upperBound,
            maxInstances: maxInstances,
            complexity: complexity,
            visualMass: mass,
            haloFootprint: halo,
            blurFootprint: blur
        )
    }

    private static func genome(
        _ id: String,
        _ title: String,
        morphology: MetalShapeMorphology,
        m: Float,
        n: SIMD3<Float>,
        harmonics: [MetalShapeHarmonic],
        anisotropy: SIMD2<Float> = SIMD2(1, 1),
        offset: SIMD2<Float> = .zero,
        rotation: Float = 0,
        policy: MetalShapeCompatibility
    ) -> MetalShapePreset {
        let value = MetalShapeGenome(
            morphology: morphology,
            superformula: SIMD4(m, n.x, n.y, n.z),
            harmonics: harmonics,
            anisotropy: anisotropy,
            centerOffset: offset,
            rotation: rotation
        )
        return MetalShapePreset(
            id: id,
            title: title,
            source: .genome,
            morphology: morphology,
            contour: .genome(value),
            compatibility: policy
        )
    }

    private static let genomePresets: [MetalShapePreset] = [
        genome("genome.soft-orbit", "Мягкая орбита", morphology: .softRadial,
               m: 2, n: SIMD3(1.7, 1.8, 1.8),
               harmonics: [.init(frequency: 2, amplitude: 0.045, phase: 0.4)],
               anisotropy: SIMD2(1.08, 0.94), offset: SIMD2(0.035, -0.02),
               policy: policy(preferred: [.sideLight, .radialThree, .proceduralLight], roles: [.primary, .supporting], size: 0.24...0.72, maxInstances: 2, complexity: 0.18, mass: 0.72)),
        genome("genome.soft-drift", "Мягкий дрейф", morphology: .softRadial,
               m: 2, n: SIMD3(2.1, 2.5, 1.65),
               harmonics: [.init(frequency: 3, amplitude: 0.055, phase: 1.2)],
               anisotropy: SIMD2(0.92, 1.12), offset: SIMD2(-0.05, 0.025), rotation: 0.22,
               policy: policy(preferred: [.solid, .sideLight, .directionalBlur], roles: [.primary, .supporting], size: 0.22...0.68, maxInstances: 2, complexity: 0.22, mass: 0.76)),
        genome("genome.soft-cell", "Мягкая клетка", morphology: .softRadial,
               m: 4, n: SIMD3(2.6, 2.8, 2.8),
               harmonics: [.init(frequency: 2, amplitude: 0.035, phase: 2.1)],
               anisotropy: SIMD2(1.04, 0.97),
               policy: policy(preferred: [.radialTwo, .proceduralFlow, .contour], roles: [.primary, .supporting], size: 0.20...0.64, maxInstances: 2, complexity: 0.26, mass: 0.68)),

        genome("genome.lobed-triad", "Трёхдольник", morphology: .lobed,
               m: 3, n: SIMD3(1.0, 1.35, 1.35),
               harmonics: [.init(frequency: 3, amplitude: 0.075, phase: 0.15)],
               rotation: -0.18,
               policy: policy(preferred: [.sideLight, .proceduralContour, .radialThree], roles: [.primary, .supporting], size: 0.22...0.66, maxInstances: 2, complexity: 0.44, mass: 0.63)),
        genome("genome.lobed-quartet", "Четырёхдольник", morphology: .lobed,
               m: 4, n: SIMD3(0.95, 1.4, 1.4),
               harmonics: [.init(frequency: 4, amplitude: 0.065, phase: 0.7)],
               anisotropy: SIMD2(1.06, 0.96), rotation: 0.12,
               policy: policy(preferred: [.contour, .proceduralLight, .eclipseGlow], roles: [.primary, .supporting, .accent], size: 0.18...0.60, maxInstances: 2, complexity: 0.50, mass: 0.58)),
        genome("genome.lobed-penta", "Пятидольник", morphology: .lobed,
               m: 5, n: SIMD3(0.92, 1.45, 1.45),
               harmonics: [.init(frequency: 5, amplitude: 0.06, phase: 1.4)],
               offset: SIMD2(0.02, -0.025),
               policy: policy(preferred: [.proceduralFlow, .proceduralContour, .sideLight], allowed: lightMaterials, roles: [.supporting, .accent], size: 0.16...0.48, maxInstances: 1, complexity: 0.58, mass: 0.52)),

        genome("genome.folded-rosette-5", "Складчатая розетка 5", morphology: .foldedRosette,
               m: 5, n: SIMD3(0.62, 1.05, 1.05),
               harmonics: [.init(frequency: 10, amplitude: 0.045, phase: 0.25)],
               policy: policy(preferred: [.proceduralContour, .eclipseGlow, .radialThree], allowed: lightMaterials, roles: [.primary, .accent], size: 0.20...0.58, maxInstances: 1, complexity: 0.72, mass: 0.55)),
        genome("genome.folded-rosette-7", "Складчатая розетка 7", morphology: .foldedRosette,
               m: 7, n: SIMD3(0.66, 1.08, 1.08),
               harmonics: [.init(frequency: 7, amplitude: 0.035, phase: 0.9)],
               rotation: 0.16,
               policy: policy(preferred: [.contour, .proceduralLight, .proceduralContour], allowed: lightMaterials, roles: [.primary, .accent], size: 0.18...0.52, maxInstances: 1, complexity: 0.80, mass: 0.50)),
        genome("genome.folded-rosette-9", "Складчатая розетка 9", morphology: .foldedRosette,
               m: 9, n: SIMD3(0.70, 1.10, 1.10),
               harmonics: [.init(frequency: 9, amplitude: 0.03, phase: 1.75)],
               policy: policy(preferred: [.proceduralContour, .eclipseGlow], allowed: [.contour, .proceduralLight, .proceduralFlow, .proceduralContour, .eclipseGlow], roles: [.accent], size: 0.14...0.38, maxInstances: 1, complexity: 0.90, mass: 0.42)),

        genome("genome.crystal-4", "Кристалл 4", morphology: .crystalline,
               m: 4, n: SIMD3(0.38, 0.72, 0.72),
               harmonics: [.init(frequency: 8, amplitude: 0.025, phase: 0.3)],
               rotation: 0.39,
               policy: policy(preferred: [.solid, .sideLight, .eclipseGlow], roles: [.primary, .accent], size: 0.18...0.58, maxInstances: 1, complexity: 0.62, mass: 0.70)),
        genome("genome.crystal-6", "Кристалл 6", morphology: .crystalline,
               m: 6, n: SIMD3(0.42, 0.76, 0.76),
               harmonics: [.init(frequency: 6, amplitude: 0.03, phase: 1.1)],
               policy: policy(preferred: [.contour, .radialThree, .proceduralLight], allowed: lightMaterials, roles: [.primary, .supporting, .accent], size: 0.16...0.52, maxInstances: 1, complexity: 0.70, mass: 0.60)),
        genome("genome.crystal-8", "Кристалл 8", morphology: .crystalline,
               m: 8, n: SIMD3(0.48, 0.80, 0.80),
               harmonics: [.init(frequency: 8, amplitude: 0.025, phase: 2.0)],
               rotation: 0.20,
               policy: policy(preferred: [.proceduralContour, .eclipseGlow], allowed: [.contour, .radialThree, .proceduralLight, .proceduralContour, .eclipseGlow], roles: [.accent], size: 0.13...0.36, maxInstances: 1, complexity: 0.84, mass: 0.45)),
    ]

    private static func legacy(
        _ id: String,
        _ title: String,
        shape: UInt32,
        variant: UInt32,
        morphology: MetalShapeMorphology,
        preferred: Set<MetalShapeMaterial>,
        roles: Set<MetalShapeRole>
    ) -> MetalShapePreset {
        MetalShapePreset(
            id: id,
            title: title,
            source: .legacy,
            morphology: morphology,
            contour: .legacy(shape: shape, variant: variant),
            compatibility: policy(
                preferred: preferred,
                roles: roles,
                size: roles.contains(.primary) ? 0.20...0.72 : 0.14...0.48,
                maxInstances: 2,
                complexity: morphology == .legacyStar ? 0.58 : 0.30,
                mass: morphology == .legacyRound ? 0.76 : 0.62
            )
        )
    }

    private static let legacyPresets: [MetalShapePreset] = [
        legacy("legacy.circle", "Круг", shape: 0, variant: 1, morphology: .legacyRound, preferred: [.solid, .sideLight, .radialThree, .directionalBlur], roles: [.primary, .supporting]),
        legacy("legacy.soft-square", "Мягкий квадрат", shape: 6, variant: 17, morphology: .legacyPolygon, preferred: [.sideLight, .directionalBlur, .proceduralFlow], roles: [.primary, .supporting]),
        legacy("legacy.rounded-triangle", "Скруглённый треугольник", shape: 5, variant: 5, morphology: .legacyPolygon, preferred: [.sideLight, .contour, .directionalBlur], roles: [.primary, .supporting, .accent]),
        legacy("legacy.rounded-pentagon", "Сдержанный пятиугольник", shape: 5, variant: 7, morphology: .legacyPolygon, preferred: [.radialTwo, .proceduralLight, .contour], roles: [.supporting, .accent]),
        legacy("legacy.rounded-hexagon", "Сдержанный шестиугольник", shape: 5, variant: 8, morphology: .legacyPolygon, preferred: [.solid, .sideLight, .radialThree], roles: [.primary, .supporting]),
        legacy("legacy.star-3-shallow", "Мелкая трёхлучевая звезда", shape: 4, variant: 1, morphology: .legacyStar, preferred: [.proceduralContour, .sideLight, .eclipseGlow], roles: [.supporting, .accent]),
        legacy("legacy.star-4-moderate", "Умеренная четырёхлучевая звезда", shape: 4, variant: 6, morphology: .legacyStar, preferred: [.contour, .proceduralLight, .eclipseGlow], roles: [.primary, .accent]),
        legacy("legacy.star-5-restrained", "Сдержанная пятилучевая звезда", shape: 4, variant: 3, morphology: .legacyStar, preferred: [.proceduralContour, .radialThree, .eclipseGlow], roles: [.accent]),
    ]
}
