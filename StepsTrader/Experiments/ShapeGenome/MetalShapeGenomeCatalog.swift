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

    private static let snowflake = MetalShapePreset(
        id: "genome.snowflake",
        title: "Snowflake · стоп-кадр",
        source: .genome,
        morphology: .snowflake,
        contour: .snowflake,
        compatibility: policy(
            preferred: [.sideLight, .proceduralContour, .eclipseGlow],
            allowed: [.sideLight, .contour, .radialTwo, .proceduralLight, .proceduralContour, .eclipseGlow],
            roles: [.accent],
            size: 0.16...0.48,
            maxInstances: 1,
            complexity: 0.78,
            mass: 0.30,
            halo: 0.15
        )
    )

    private static let windflower = MetalShapePreset(
        id: "genome.windflower",
        title: "Ветряной цветок",
        source: .genome,
        morphology: .windflower,
        contour: .windflower,
        compatibility: policy(
            preferred: [.sideLight, .proceduralLight, .proceduralContour],
            allowed: [.sideLight, .contour, .radialTwo, .proceduralLight, .proceduralContour, .eclipseGlow],
            roles: [.primary, .accent],
            size: 0.18...0.58,
            maxInstances: 1,
            complexity: 0.64,
            mass: 0.42,
            halo: 0.12
        )
    )

    private static let genomePresets: [MetalShapePreset] = [
        genome("genome.soft-drift", "Мягкий дрейф", morphology: .softRadial,
               m: 2, n: SIMD3(2.1, 2.5, 1.65),
               harmonics: [.init(frequency: 3, amplitude: 0.055, phase: 1.2)],
               anisotropy: SIMD2(0.92, 1.12), offset: SIMD2(-0.05, 0.025), rotation: 0.22,
               policy: policy(preferred: [.solid, .sideLight, .directionalBlur], roles: [.primary, .supporting], size: 0.22...0.68, maxInstances: 2, complexity: 0.22, mass: 0.76)),
        genome("genome.lobed-triad", "Трёхдольник", morphology: .lobed,
               m: 3, n: SIMD3(1.0, 1.35, 1.35),
               harmonics: [.init(frequency: 3, amplitude: 0.075, phase: 0.15)],
               rotation: -0.18,
               policy: policy(preferred: [.sideLight, .proceduralContour, .radialThree], roles: [.primary, .supporting], size: 0.22...0.66, maxInstances: 2, complexity: 0.44, mass: 0.63)),
        snowflake,
        windflower,
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
    ]
}
