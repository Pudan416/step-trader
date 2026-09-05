import Foundation
import simd

/// Lab-only neutral backgrounds used by the approved Editorial Field review corpus.
enum DayObjectEditorialBackground: String, CaseIterable, Equatable, Identifiable {
    case light
    case dark
    case lowContrast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .lowContrast: "Low contrast"
        }
    }

    var linearRGB: SIMD3<Float> {
        let sRGB: SIMD3<Float> = switch self {
        case .light: SIMD3(0.94, 0.92, 0.88)
        case .dark: SIMD3(0.045, 0.060, 0.105)
        case .lowContrast: SIMD3(0.49, 0.50, 0.47)
        }
        return DayObjectRGB(sRGB: sRGB).linearRGB
    }
}

enum DayObjectEditorialMaterialFamily: UInt32, CaseIterable, Equatable {
    case gradient
    case solid
    case sphere
    case glass
    case mist
    case halo
    case luminous
    case outline
    case counterform

    var gpuFamily: DayObjectMaterialFamily {
        DayObjectMaterialFamily(rawValue: rawValue) ?? .gradient
    }
}

struct DayObjectEditorialRadialFieldV1: Equatable {
    let focus: SIMD2<Double>
    let radius: Double
    let softness: Double
    let opacity: Double
}

struct DayObjectEditorialMaterialV1: Equatable {
    let family: DayObjectEditorialMaterialFamily
    let mechanism: DayObjectMaterialMechanism
    let colors: [SIMD3<Float>]
    let fields: [DayObjectEditorialRadialFieldV1]
    let baseOpacity: Double
    let edgeSoftness: Double
    let contourWidth: Double
    let contourCount: Int
    let counterformRadius: Double?
    let counterformSoftness: Double
    let structuralParameters: SIMD4<Float>

    var gpuAppearance: DayObjectGPUAppearance {
        var packedColors = colors.prefix(3).map { color in
            let linear = DayObjectRGB(sRGB: color).linearRGB
            return SIMD4(linear, 1)
        }
        let colorCount = packedColors.count
        while packedColors.count < 3 {
            packedColors.append(packedColors.last ?? SIMD4(1, 1, 1, 1))
        }

        let packedFields = (0..<3).map { index -> SIMD4<Float> in
            guard fields.indices.contains(index) else {
                return SIMD4(0, 0, 0.72, 0.54)
            }
            let field = fields[index]
            return SIMD4(
                Float((field.focus.x - 0.5) * 1.7),
                Float((field.focus.y - 0.5) * 1.7),
                Float(field.radius * 1.2),
                Float(field.softness * 0.88)
            )
        }
        let fieldOpacities = (0..<3).map { index in
            fields.indices.contains(index) ? Float(fields[index].opacity) : 0
        }

        let optics: (SIMD4<Float>, SIMD4<Float>, Float)
        switch family {
        case .gradient:
            optics = (SIMD4(0.18, 0.08, Float(baseOpacity), 1), SIMD4(0.08, 0, 0, 0), 0.76)
        case .solid:
            optics = (
                SIMD4(0, 0, Float(baseOpacity), 1),
                SIMD4(0, 0, 0, 0),
                Float(min(baseOpacity, 0.88))
            )
        case .sphere:
            optics = (SIMD4(0.58, 0.14, Float(baseOpacity), 1), SIMD4(0.42, 0, 0, 0), 0.78)
        case .glass:
            optics = (SIMD4(0.20, 0.24, Float(baseOpacity), 0.88), SIMD4(0.62, 0.018, 0.7, 0), 0.64)
        case .mist:
            optics = (SIMD4(0.16, 0.52, Float(baseOpacity), 0.90), SIMD4(0.14, 0, 0, 0.18), 0.60)
        case .halo:
            optics = (SIMD4(0.18, 0.72, Float(baseOpacity), 0.90), SIMD4(0.34, 0, 0, 0.08), 0.72)
        case .luminous:
            optics = (SIMD4(0.92, 0.46, Float(baseOpacity), 1), SIMD4(0.32, 0, 0, 0), 0.74)
        case .outline:
            optics = (SIMD4(0.08, 0.20, Float(baseOpacity), 1), SIMD4(0.18, 0, 0, 0), 0.82)
        case .counterform:
            optics = (SIMD4(0.22, 0.28, Float(baseOpacity), 1), SIMD4(0.24, 0, 0, 0), 0.78)
        }

        let recipe1: SIMD4<Float>
        switch mechanism {
        case .radialFibers, .harmonicPath:
            recipe1 = structuralParameters
        default:
            recipe1 = switch family {
            case .outline:
                SIMD4(Float(max(contourCount, 1)), Float(contourWidth), 0.035, 0.025)
            case .counterform:
                SIMD4(
                    Float(max(counterformRadius ?? 0.48, 0.44)),
                    Float(max(counterformSoftness, 0.045)),
                    0.22,
                    0.74
                )
            default:
                .zero
            }
        }

        return DayObjectGPUAppearance(
            color0: packedColors[0],
            color1: packedColors[1],
            color2: packedColors[2],
            radial0: packedFields[0],
            radial1: packedFields[1],
            radial2: packedFields[2],
            field: SIMD4(0.015, 1.25, 0, Float(edgeSoftness)),
            optical0: optics.0,
            optical1: optics.1,
            light: SIMD4(
                family == .solid ? 0 : 0.62,
                fieldOpacities[0],
                fieldOpacities[1],
                fieldOpacities[2]
            ),
            metadata: SIMD4(mechanism.gpuFamily.rawValue, UInt32(max(colorCount, 1)), UInt32(max(fields.count, 1)), 0),
            recipe0: SIMD4(0.34, 0.68, Float(edgeSoftness), optics.2),
            recipe1: recipe1
        )
    }
}

struct DayObjectEditorialMotionV1: Equatable {
    let period: Double
    let phase: Double
    let directionBias: Double
    let amplitude: Double
    let speedRatio: Double
    let breathingAmplitude: Double
    let depthParallax: Double

    struct Pose: Equatable {
        let positionOffset: SIMD2<Double>
        let depthOffset: Double
        let scale: Double
        let rotation: Double
    }

    func pose(elapsedTime rawElapsed: Double, energy: Double, reduceMotion: Bool) -> Pose {
        guard !reduceMotion else { return .neutral }
        let elapsed = rawElapsed.isFinite ? max(rawElapsed, 0) : 0
        let boundedEnergy = min(max(energy.isFinite ? energy : 0, 0), 1)
        let energyTempo = 0.18 + 0.82 * boundedEnergy
        let cycle = canonicalPhase(elapsed / period * speedRatio * energyTempo)
        guard cycle != 0 else { return .neutral }

        let baseline = canonicalPhase(phase)
        let sample = canonicalPhase(baseline + cycle)
        let raw = flow(sample) - flow(baseline)
        let cosine = cos(directionBias)
        let sine = sin(directionBias)
        let translation = SIMD2(
            raw.x * cosine - raw.y * sine,
            raw.x * sine + raw.y * cosine
        ) * amplitude * 0.35
        let depth = (depthWave(sample) - depthWave(baseline)) * 0.5 * depthParallax
        let breath = 1 + (breathingWave(sample) - breathingWave(baseline))
            * 0.5 * breathingAmplitude
        let rotation = (rotationWave(sample) - rotationWave(baseline)) * 0.003
        return Pose(positionOffset: translation, depthOffset: depth, scale: breath, rotation: rotation)
    }

    private func canonicalPhase(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return remainder >= 0 ? remainder : remainder + 1
    }

    private func flow(_ value: Double) -> SIMD2<Double> {
        let angle = 2 * Double.pi * value
        return SIMD2(
            0.90 * sin(angle) + 0.07 * sin(2 * angle) + 0.03 * cos(3 * angle),
            0.86 * cos(angle) - 0.09 * cos(2 * angle) + 0.05 * sin(3 * angle)
        )
    }

    private func depthWave(_ value: Double) -> Double {
        let angle = 2 * Double.pi * value
        return 0.62 * sin(angle) + 0.25 * cos(2 * angle) + 0.13 * sin(3 * angle)
    }

    private func breathingWave(_ value: Double) -> Double {
        let angle = 2 * Double.pi * value
        return 0.58 * sin(angle + 0.35) + 0.27 * cos(2 * angle - 0.50)
            + 0.15 * sin(3 * angle + 0.80)
    }

    private func rotationWave(_ value: Double) -> Double {
        let angle = 2 * Double.pi * value
        return 0.55 * sin(angle - 0.20) + 0.30 * cos(2 * angle + 0.45)
            + 0.15 * sin(3 * angle - 0.70)
    }
}

private extension DayObjectEditorialMotionV1.Pose {
    static let neutral = DayObjectEditorialMotionV1.Pose(
        positionOffset: .zero,
        depthOffset: 0,
        scale: 1,
        rotation: 0
    )
}

struct DayObjectSceneRecipeActorV1: Equatable {
    let eventID: String
    let slot: Int
    let shape: DayObjectShape
    let geometryRegion: DayObjectGeometryRegion
    let position: SIMD2<Double>
    let diameter: Double
    let depth: Double
    let localBlur: Double
    let cropAllowance: Double
    let drawOrder: Int
    let material: DayObjectEditorialMaterialV1
    let motion: DayObjectEditorialMotionV1
}

/// Minimal Lab MVP recipe frozen from the approved visible continuity corpus.
/// The composition is immutable; material and motion values remain deterministic
/// functions of an approved visible seed and stable actor identity.
struct DayObjectSceneRecipeV1: Equatable {
    static let version = "scene-recipe-v1-lab-mvp"
    static let compositionSourceSeed: UInt64 = 5_211_325_511_773_202_532

    let version: String
    let compositionSourceSeed: UInt64
    let materialSeed: UInt64
    let background: DayObjectEditorialBackground
    let lowSleep: Bool
    let actors: [DayObjectSceneRecipeActorV1]
    let backgroundStyle: DayObjectMeshGradientStyle
    let preview: DayObjectEditorialPreviewSpec?
    let previewPaletteSet: DayObjectPaletteSet?
    let editorialLabConfiguration: DayObjectEditorialLabConfiguration?
    let artDirection: DayObjectArtDirection?

    var artDirectionSummary: String? {
        guard let artDirection else { return nil }
        let fingerprint = artDirection.fingerprint
        let accent = artDirection.accentMaterial.map { " + \($0.label)" } ?? ""
        return "DNA \(fingerprint.primaryFamily.label) · "
            + "\(artDirection.primaryGeometry.label) · "
            + "\(artDirection.primaryMaterial.label)\(accent) · "
            + fingerprint.composition.label
    }

    func actor(_ eventID: String) -> DayObjectSceneRecipeActorV1? {
        actors.first { $0.eventID == eventID }
    }

    static func make(
        rootSeed: UInt64,
        dayKey: String,
        identity: String,
        actors: [DayObjectActor],
        background: DayObjectEditorialBackground,
        lowSleep: Bool,
        paletteSet: DayObjectPaletteSet? = nil,
        preview: DayObjectEditorialPreviewSpec? = nil,
        editorialLabConfiguration: DayObjectEditorialLabConfiguration? = nil
    ) -> DayObjectSceneRecipeV1 {
        if let preview, let paletteSet {
            return makePreview(
                rootSeed: rootSeed,
                actors: actors,
                background: background,
                lowSleep: lowSleep,
                paletteSet: paletteSet,
                preview: preview
            )
        }
        if let editorialLabConfiguration, let paletteSet {
            return makeEditorialLabVariant(
                rootSeed: rootSeed,
                actors: actors,
                background: background,
                lowSleep: lowSleep,
                paletteSet: paletteSet,
                configuration: editorialLabConfiguration,
                artDirection: editorialLabConfiguration.materialMode == .generativeDNA
                    ? DayObjectArtDirectionScheduler.make(dayKey: dayKey, identity: identity)
                    : nil
            )
        }
        let materialSeed = approvedMaterialSeeds[Int(rootSeed % UInt64(approvedMaterialSeeds.count))]
        return make(
            materialSeed: materialSeed,
            actors: actors,
            background: background,
            lowSleep: lowSleep
        )
    }

    private static func make(
        materialSeed: UInt64,
        actors: [DayObjectActor],
        background: DayObjectEditorialBackground,
        lowSleep: Bool
    ) -> DayObjectSceneRecipeV1 {
        let recipeActors = Array(actors.prefix(template.count)).enumerated().map { index, actor in
            let geometry = template[index]
            return DayObjectSceneRecipeActorV1(
                eventID: actor.eventID,
                slot: index,
                shape: .sphere,
                geometryRegion: .circle,
                position: geometry.position,
                diameter: geometry.diameter,
                depth: geometry.depth,
                localBlur: geometry.localBlur,
                cropAllowance: geometry.cropAllowance,
                drawOrder: geometry.drawOrder,
                material: makeMaterial(daySeed: materialSeed, eventID: actor.eventID),
                motion: makeMotion(daySeed: materialSeed, eventID: actor.eventID)
            )
        }
        return DayObjectSceneRecipeV1(
            version: version,
            compositionSourceSeed: compositionSourceSeed,
            materialSeed: materialSeed,
            background: background,
            lowSleep: lowSleep,
            actors: recipeActors,
            backgroundStyle: neutralBackgroundStyle(background),
            preview: nil,
            previewPaletteSet: nil,
            editorialLabConfiguration: nil,
            artDirection: nil
        )
    }

    func replacingActors(_ actors: [DayObjectActor]) -> DayObjectSceneRecipeV1 {
        if let preview, let previewPaletteSet {
            return Self.makePreview(
                rootSeed: materialSeed,
                actors: actors,
                background: background,
                lowSleep: lowSleep,
                paletteSet: previewPaletteSet,
                preview: preview
            )
        }
        if let editorialLabConfiguration, let previewPaletteSet {
            return Self.makeEditorialLabVariant(
                rootSeed: materialSeed,
                actors: actors,
                background: background,
                lowSleep: lowSleep,
                paletteSet: previewPaletteSet,
                configuration: editorialLabConfiguration,
                artDirection: artDirection
            )
        }
        return Self.make(
            materialSeed: materialSeed,
            actors: actors,
            background: background,
            lowSleep: lowSleep
        )
    }

    private static func makePreview(
        rootSeed: UInt64,
        actors: [DayObjectActor],
        background: DayObjectEditorialBackground,
        lowSleep: Bool,
        paletteSet: DayObjectPaletteSet,
        preview: DayObjectEditorialPreviewSpec
    ) -> DayObjectSceneRecipeV1 {
        let planned = CompositionPlanner.make(
            daySeed: rootSeed,
            eventIDs: CorpusManifest.canonicalEventIDs,
            viewport: .phone
        )
        let geometries = planned.actors.enumerated().map { index, actor in
            previewGeometry(
                Geometry(
                    position: SIMD2(actor.position.x, actor.position.y),
                    diameter: actor.diameter,
                    depth: actor.depth,
                    localBlur: actor.localBlur,
                    cropAllowance: actor.cropAllowance,
                    drawOrder: actor.drawOrder
                ),
                slot: index,
                rootSeed: rootSeed,
                placement: preview.placement
            )
        }
        let recipeActors = Array(actors.prefix(geometries.count)).enumerated().map { index, actor in
            let geometry = geometries[index]
            return DayObjectSceneRecipeActorV1(
                eventID: actor.eventID,
                slot: index,
                shape: .sphere,
                geometryRegion: .circle,
                position: geometry.position,
                diameter: geometry.diameter,
                depth: geometry.depth,
                localBlur: geometry.localBlur,
                cropAllowance: geometry.cropAllowance,
                drawOrder: geometry.drawOrder,
                material: makePreviewMaterial(
                    daySeed: rootSeed,
                    eventID: actor.eventID,
                    slot: index,
                    material: preview.material,
                    paletteSet: paletteSet
                ),
                motion: makeMotion(daySeed: rootSeed, eventID: actor.eventID)
            )
        }
        return DayObjectSceneRecipeV1(
            version: version,
            compositionSourceSeed: rootSeed,
            materialSeed: rootSeed,
            background: background,
            lowSleep: lowSleep,
            actors: recipeActors,
            backgroundStyle: vividPreviewBackgroundStyle(
                seed: rootSeed,
                palette: DayObjectPalette.make(modernPalette: paletteSet.background)
            ),
            preview: preview,
            previewPaletteSet: paletteSet,
            editorialLabConfiguration: nil,
            artDirection: nil
        )
    }

    private static func makeEditorialLabVariant(
        rootSeed: UInt64,
        actors: [DayObjectActor],
        background: DayObjectEditorialBackground,
        lowSleep: Bool,
        paletteSet: DayObjectPaletteSet,
        configuration: DayObjectEditorialLabConfiguration,
        artDirection: DayObjectArtDirection?
    ) -> DayObjectSceneRecipeV1 {
        let planned = CompositionPlanner.make(
            daySeed: rootSeed,
            eventIDs: CorpusManifest.canonicalEventIDs,
            viewport: .phone
        )
        let geometries = planned.actors.enumerated().map { index, actor in
            previewGeometry(
                Geometry(
                    position: SIMD2(actor.position.x, actor.position.y),
                    diameter: actor.diameter,
                    depth: actor.depth,
                    localBlur: actor.localBlur,
                    cropAllowance: actor.cropAllowance,
                    drawOrder: actor.drawOrder
                ),
                slot: index,
                rootSeed: rootSeed,
                placement: configuration.placement
            )
        }
        let recipeActors = Array(actors.prefix(geometries.count)).enumerated().map { index, actor in
            let geometry = geometries[index]
            let resolution = artDirection?.resolution(eventID: actor.eventID)
            let previewMaterial = configuration.materialMode.singleMaterial
                ?? mixedMaterial(eventID: actor.eventID)
            let material = resolution.map {
                makeGenerativeMaterial(
                    daySeed: rootSeed,
                    eventID: actor.eventID,
                    mechanism: $0.material,
                    direction: artDirection!,
                    paletteSet: paletteSet
                )
            } ?? makePreviewMaterial(
                daySeed: rootSeed,
                eventID: actor.eventID,
                slot: index,
                material: previewMaterial,
                paletteSet: paletteSet
            )
            let geometryRegion = resolution?.geometry ?? .circle
            return DayObjectSceneRecipeActorV1(
                eventID: actor.eventID,
                slot: index,
                shape: geometryRegion.shape(actorSeed: stableHash(actor.eventID)),
                geometryRegion: geometryRegion,
                position: geometry.position,
                diameter: geometry.diameter,
                depth: geometry.depth,
                localBlur: geometry.localBlur,
                cropAllowance: geometry.cropAllowance,
                drawOrder: geometry.drawOrder,
                material: material,
                motion: makeMotion(daySeed: rootSeed, eventID: actor.eventID)
            )
        }
        return DayObjectSceneRecipeV1(
            version: version,
            compositionSourceSeed: rootSeed,
            materialSeed: rootSeed,
            background: background,
            lowSleep: lowSleep,
            actors: recipeActors,
            backgroundStyle: vividPreviewBackgroundStyle(
                seed: rootSeed,
                palette: DayObjectPalette.make(modernPalette: paletteSet.background)
            ),
            preview: nil,
            previewPaletteSet: paletteSet,
            editorialLabConfiguration: configuration,
            artDirection: artDirection
        )
    }

    private static func mixedMaterial(eventID: String) -> DayObjectEditorialPreviewMaterial {
        let materials = DayObjectEditorialPreviewMaterial.allCases
        let index = min(
            Int(unit(stableHash(eventID) ^ 0x84) * Double(materials.count)),
            materials.count - 1
        )
        return materials[index]
    }

    private static func makeGenerativeMaterial(
        daySeed: UInt64,
        eventID: String,
        mechanism: DayObjectMaterialMechanism,
        direction: DayObjectArtDirection,
        paletteSet: DayObjectPaletteSet
    ) -> DayObjectEditorialMaterialV1 {
        let actorSeed = daySeed ^ stableHash(eventID)
        let lightnessShift = paletteSet.actorLightnessShift ?? 0
        func displayColors(_ palette: ModernPalette) -> [SIMD3<Float>] {
            palette.hexes.map {
                DayObjectRGB(hex: $0)
                    .shiftingPerceptualLightness(by: lightnessShift)
                    .sRGB
            }
        }
        let primary = displayColors(paletteSet.primaryObjects)
        let secondary = displayColors(paletteSet.secondaryObjects)
        let fallback = SIMD3<Float>(0.82, 0.32, 0.56)
        let preferred = actorUnit(actorSeed, salt: 0xDA11_C010) < 0.78
            ? primary
            : secondary
        let actorColorPool = preferred.isEmpty ? (primary + secondary) : preferred
        let actorStart = Int(actorSeed % UInt64(max(actorColorPool.count, 1)))
        let gradientTopology = ComplexGradientTopology.make(daySeed: daySeed)
        let colors: [SIMD3<Float>]
        if mechanism == .smoothRadial {
            // A day chooses one coherent gradient grammar. Actors may move and
            // deform independently, but they keep the same approved colour
            // relationship instead of each rolling a different gradient.
            colors = makeComplexGradientColors(
                pool: primary + secondary,
                requestedCount: gradientTopology.colorCount,
                daySeed: daySeed,
                fallback: fallback
            )
        } else {
            let colorCount: Int = switch mechanism {
            case .solid, .boundary, .radialFibers: 1
            case .smoothRadial: 2
            case .layeredMembrane, .harmonicPath: 2
            }
            colors = (0..<colorCount).map { offset in
                actorColorPool.isEmpty
                    ? fallback
                    : actorColorPool[(actorStart + offset) % actorColorPool.count]
            }
        }
        let fields: [DayObjectEditorialRadialFieldV1]
        switch mechanism {
        case .smoothRadial:
            fields = makeComplexGradientFields(
                topology: gradientTopology,
                actorSeed: actorSeed,
                count: colors.count
            )
        case .layeredMembrane, .harmonicPath:
            fields = makeGenerativeFields(actorSeed: actorSeed, count: colors.count)
        default:
            fields = []
        }

        let family: DayObjectEditorialMaterialFamily = switch mechanism {
        case .solid: .solid
        case .smoothRadial: .gradient
        case .layeredMembrane: .glass
        case .boundary, .radialFibers, .harmonicPath: .outline
        }
        let contourWidth: Double = switch direction.fingerprint.edgeMood {
        case .hairline: 0.005
        case .cleanSoft: 0.022
        case .feathered: 0.050
        }
        let construction: (opacity: Double, edge: Double) = switch mechanism {
        case .solid: (1, 0.004)
        case .smoothRadial: (0.98, 0.040)
        case .layeredMembrane: (0.62, 0.026)
        case .boundary: (0.90, direction.fingerprint.edgeMood == .feathered ? 0.040 : 0.012)
        case .radialFibers: (0.88, 0.010)
        case .harmonicPath: (0.90, 0.010)
        }
        return DayObjectEditorialMaterialV1(
            family: family,
            mechanism: mechanism,
            colors: colors,
            fields: fields,
            baseOpacity: construction.opacity,
            edgeSoftness: construction.edge,
            contourWidth: mechanism == .boundary ? contourWidth : 0,
            contourCount: mechanism == .boundary ? 1 : 0,
            counterformRadius: nil,
            counterformSoftness: 0,
            structuralParameters: structuralParameters(
                mechanism: mechanism,
                actorSeed: actorSeed
            )
        )
    }

    private enum ComplexGradientTopology: Int {
        case dualSweep
        case dualBloom
        case asymmetricTriad
        case airyTriad

        static func make(daySeed: UInt64) -> Self {
            let index = Int((daySeed ^ 0xC011_0F13_1D5) % 4)
            return Self(rawValue: index) ?? .dualSweep
        }

        var colorCount: Int {
            switch self {
            case .dualSweep, .dualBloom: 2
            case .asymmetricTriad, .airyTriad: 3
            }
        }
    }

    private static func makeComplexGradientColors(
        pool: [SIMD3<Float>],
        requestedCount: Int,
        daySeed: UInt64,
        fallback: SIMD3<Float>
    ) -> [SIMD3<Float>] {
        let unique = pool.reduce(into: [SIMD3<Float>]()) { result, color in
            guard !result.contains(where: { simd_distance($0, color) < 0.001 }) else {
                return
            }
            result.append(color)
        }
        guard !unique.isEmpty else { return [fallback, fallback] }

        let start = Int((daySeed ^ 0xC010_A11C_E) % UInt64(unique.count))
        let ordered = unique.indices.map { unique[(start + $0) % unique.count] }
        if requestedCount >= 3, ordered.count >= 3 {
            var bestTriple: ([SIMD3<Float>], Float)?
            for first in 0..<(ordered.count - 2) {
                for second in (first + 1)..<(ordered.count - 1) {
                    for third in (second + 1)..<ordered.count {
                        let candidate = [ordered[first], ordered[second], ordered[third]]
                        guard let score = complexGradientScore(candidate) else { continue }
                        if bestTriple == nil || score > bestTriple!.1 {
                            bestTriple = (candidate, score)
                        }
                    }
                }
            }
            if let bestTriple { return bestTriple.0 }
        }

        var bestPair: ([SIMD3<Float>], Float)?
        if ordered.count >= 2 {
            for first in 0..<(ordered.count - 1) {
                for second in (first + 1)..<ordered.count {
                    let candidate = [ordered[first], ordered[second]]
                    guard let score = complexGradientScore(candidate) else { continue }
                    if bestPair == nil || score > bestPair!.1 {
                        bestPair = (candidate, score)
                    }
                }
            }
        }
        return bestPair?.0 ?? [ordered[0], ordered.count > 1 ? ordered[1] : fallback]
    }

    private static func complexGradientScore(_ colors: [SIMD3<Float>]) -> Float? {
        let labs = colors.map { DayObjectRGB(sRGB: $0).perceptualOKLab }
        var perceptualDistances = [Float]()
        var chromaticDistances = [Float]()
        for lhs in labs.indices {
            for rhs in labs.indices where rhs > lhs {
                perceptualDistances.append(simd_distance(labs[lhs], labs[rhs]))
                chromaticDistances.append(
                    simd_distance(
                        SIMD2(labs[lhs].y, labs[lhs].z),
                        SIMD2(labs[rhs].y, labs[rhs].z)
                    )
                )
            }
        }
        guard let minimumPerceptual = perceptualDistances.min(),
              let minimumChromatic = chromaticDistances.min(),
              minimumPerceptual >= 0.065,
              minimumChromatic >= 0.045 else {
            return nil
        }
        return minimumChromatic * 2 + minimumPerceptual
    }

    private static func makeComplexGradientFields(
        topology: ComplexGradientTopology,
        actorSeed: UInt64,
        count: Int
    ) -> [DayObjectEditorialRadialFieldV1] {
        let baseAngle = actorUnit(actorSeed, salt: 0xC011_F13D) * 2 * Double.pi
        let angularJitter = (actorUnit(actorSeed, salt: 0xC011_0177) - 0.5) * 0.04
        let distanceJitter = (actorUnit(actorSeed, salt: 0xC011_D157) - 0.5) * 0.025
        let specification: [(angle: Double, distance: Double, radius: Double, opacity: Double)]
        switch topology {
        case .dualSweep:
            specification = [(0, 0.64, 1.06, 1), (.pi, 0.64, 1.06, 1)]
        case .dualBloom:
            specification = [(0, 0.56, 1.28, 0.96), (.pi, 0.78, 0.90, 1)]
        case .asymmetricTriad:
            specification = [
                (0, 0.72, 1.10, 1),
                (2.10, 0.70, 0.96, 0.98),
                (4.22, 0.74, 1.04, 0.98),
            ]
        case .airyTriad:
            specification = [
                (0, 0.60, 1.30, 0.94),
                (2.15, 0.74, 1.00, 1),
                (4.25, 0.68, 1.14, 0.98),
            ]
        }

        return specification.prefix(count).enumerated().map { index, field in
            let angle = baseAngle + field.angle + angularJitter * (index == 1 ? -1 : 1)
            let distance = field.distance + distanceJitter * (index == 2 ? -1 : 1)
            return DayObjectEditorialRadialFieldV1(
                focus: SIMD2(
                    0.5 + cos(angle) * distance,
                    0.5 + sin(angle) * distance
                ),
                radius: field.radius,
                softness: 0.98 + Double(index) * 0.01,
                opacity: field.opacity
            )
        }
    }

    private static func makeGenerativeFields(
        actorSeed: UInt64,
        count: Int
    ) -> [DayObjectEditorialRadialFieldV1] {
        let baseAngle = actorUnit(actorSeed, salt: 0xF13D_0001) * 2 * Double.pi
        return (0..<count).map { index in
            let angle = baseAngle + Double(index) * (2 * Double.pi / Double(max(count, 2)))
            let distance = 0.34 + actorUnit(
                actorSeed,
                salt: UInt64(0xF13D_0010 + index)
            ) * 0.08
            return DayObjectEditorialRadialFieldV1(
                focus: SIMD2(
                    0.5 + cos(angle) * distance,
                    0.5 + sin(angle) * distance
                ),
                radius: 1.08 + actorUnit(
                    actorSeed,
                    salt: UInt64(0xF13D_0020 + index)
                ) * 0.34,
                softness: 0.92 + actorUnit(
                    actorSeed,
                    salt: UInt64(0xF13D_0030 + index)
                ) * 0.08,
                opacity: index == 0 ? 1 : 0.78 + actorUnit(
                    actorSeed,
                    salt: UInt64(0xF13D_0040 + index)
                ) * 0.16
            )
        }
    }

    private static func structuralParameters(
        mechanism: DayObjectMaterialMechanism,
        actorSeed: UInt64
    ) -> SIMD4<Float> {
        switch mechanism {
        case .radialFibers:
            return SIMD4(
                Float(56 + Int(actorUnit(actorSeed, salt: 0xF1B3_0001) * 49)),
                Float(0.007 + actorUnit(actorSeed, salt: 0xF1B3_0002) * 0.009),
                Float(actorUnit(actorSeed, salt: 0xF1B3_0003)),
                Float(0.46 + actorUnit(actorSeed, salt: 0xF1B3_0004) * 0.28)
            )
        case .harmonicPath:
            return SIMD4(
                Float(2 + Int(actorUnit(actorSeed, salt: 0xA4A0_0001) * 6)),
                Float(0.055 + actorUnit(actorSeed, salt: 0xA4A0_0002) * 0.095),
                Float(0.10 + actorUnit(actorSeed, salt: 0xA4A0_0003) * 0.16),
                Float(1 + Int(actorUnit(actorSeed, salt: 0xA4A0_0004) * 3))
            )
        default:
            return .zero
        }
    }

    private static func vividPreviewBackgroundStyle(
        seed: UInt64,
        palette: DayObjectPalette
    ) -> DayObjectMeshGradientStyle {
        let base = DayObjectMeshGradientStyle.make(seed: seed, palette: palette)
        return DayObjectMeshGradientStyle(
            colors: base.colors,
            archetype: base.archetype,
            offset: base.offset,
            distortion: max(base.distortion, 0.24),
            swirl: base.swirl,
            speed: base.speed,
            scale: min(base.scale, 0.90),
            phase: base.phase,
            motionDirection: base.motionDirection
        )
    }

    private static func neutralBackgroundStyle(
        _ background: DayObjectEditorialBackground
    ) -> DayObjectMeshGradientStyle {
        DayObjectMeshGradientStyle(
            colors: Array(repeating: background.linearRGB, count: 3),
            archetype: .drift,
            distortion: 0,
            swirl: 0,
            speed: 0,
            scale: 1,
            phase: 0
        )
    }

    private struct Geometry {
        let position: SIMD2<Double>
        let diameter: Double
        let depth: Double
        let localBlur: Double
        let cropAllowance: Double
        let drawOrder: Int
    }

    private static func previewGeometry(
        _ geometry: Geometry,
        slot: Int,
        rootSeed: UInt64,
        placement: DayObjectEditorialPreviewPlacement
    ) -> Geometry {
        let scaleUnit = actorUnit(
            rootSeed ^ UInt64(slot),
            salt: 0x5CA1_EF13_1D5E_ED01
        )
        let focusUnit = actorUnit(
            rootSeed ^ UInt64(slot),
            salt: 0xF0C0_5B4D_5EED_0002
        )

        let diameter: Double
        let depth: Double
        let localBlur: Double
        switch placement {
        case .depthField:
            let ranges: [ClosedRange<Double>] = [
                0.50...0.66, 0.065...0.10, 0.22...0.31, 0.11...0.17,
                0.38...0.52, 0.20...0.29, 0.06...0.095, 0.54...0.72,
                0.25...0.35, 0.10...0.16,
            ]
            let range = ranges[slot % ranges.count]
            diameter = range.lowerBound + (range.upperBound - range.lowerBound) * scaleUnit
            let normalizedScale = min(max((diameter - 0.06) / 0.66, 0), 1)
            depth = 0.05 + normalizedScale * 0.90
            localBlur = 0.001 + pow(normalizedScale, 1.55) * 0.066
        case .equalMedium:
            diameter = 0.258 + scaleUnit * 0.012
            depth = 0.485 + focusUnit * 0.020
            localBlur = 0.006 + focusUnit * 0.002
        }

        return Geometry(
            position: geometry.position,
            diameter: diameter,
            depth: depth,
            localBlur: localBlur,
            cropAllowance: geometry.cropAllowance,
            drawOrder: geometry.drawOrder
        )
    }

    private static let template: [Geometry] = [
        .init(position: SIMD2(0.21781887822291068, 0.407402342486317), diameter: 0.4529606876683834, depth: 0.7447809894359582, localBlur: 0.03995057806884035, cropAllowance: 0.038243785154362636, drawOrder: 8),
        .init(position: SIMD2(0.7950869297605773, 0.6863687540121265), diameter: 0.09141544160589446, depth: 0.05754381348230938, localBlur: 0.018328645432228882, cropAllowance: 0, drawOrder: 0),
        .init(position: SIMD2(0.4240536877568102, 0.46751327104985363), diameter: 0.22782352609729875, depth: 0.3405299051972333, localBlur: 0.00935092994871958, cropAllowance: 0, drawOrder: 4),
        .init(position: SIMD2(0.5616919768112651, 0.024857140001912314), diameter: 0.12434083638018183, depth: 0.279406016005036, localBlur: 0.020988195916876107, cropAllowance: 0.13320895854207973, drawOrder: 3),
        .init(position: SIMD2(0.16921557133976606, 0.76390166646506), diameter: 0.4261638337135372, depth: 0.6795837417699352, localBlur: 0.007720221353936505, cropAllowance: 0.20586611085580314, drawOrder: 7),
        .init(position: SIMD2(0.6235253882521937, 0.571873725276926), diameter: 0.252872942878724, depth: 0.3446606123100864, localBlur: 0.009771855063285154, cropAllowance: 0, drawOrder: 5),
        .init(position: SIMD2(0.47470121187263437, 0.9846435241877131), diameter: 0.07580157068610613, depth: 0.10596916927980105, localBlur: 0.02019660844036761, cropAllowance: 0.12160390715780009, drawOrder: 1),
        .init(position: SIMD2(0.8367443147791106, 0.3438137935297031), diameter: 0.46553333078056114, depth: 0.8961104791148418, localBlur: 0.047511165983022866, cropAllowance: 0.29862944529811386, drawOrder: 9),
        .init(position: SIMD2(0.5818827916568251, 0.3911022066261193), diameter: 0.30126178193753816, depth: 0.447887750661914, localBlur: 0.006126946591598845, cropAllowance: 0, drawOrder: 6),
        .init(position: SIMD2(0.8729267644627416, 0.7400361285862982), diameter: 0.13312510068382838, depth: 0.24581811362128853, localBlur: 0.025182970775807098, cropAllowance: 0, drawOrder: 2),
    ]

    private static let approvedMaterialSeeds: [UInt64] = [
        1_612_052_424_515_492_083, 11_154_729_244_141_354_478,
        2_440_890_826_682_767_589, 4_252_333_746_721_226_202,
        18_373_866_469_865_252_394, 7_479_491_137_834_673_588,
        13_055_084_160_803_594_050, 15_575_039_812_687_928_232,
        13_549_638_178_566_396_628, 10_204_364_386_044_217_361,
        8_218_615_278_489_109_398, 1_939_359_117_579_385_755,
    ]

    private static func makeMaterial(daySeed: UInt64, eventID: String) -> DayObjectEditorialMaterialV1 {
        let family = DayObjectEditorialMaterialFamily(
            rawValue: UInt32(daySeed % UInt64(DayObjectEditorialMaterialFamily.allCases.count))
        ) ?? .gradient
        let requestedColorCount = family == .solid
            ? 1
            : Int(unit(daySeed ^ 0xC01A_5EED) * 3) + 1
        let actorSeed = daySeed ^ stableHash(eventID)
        let colors = makeColors(
            daySeed: daySeed,
            actorSeed: actorSeed,
            count: requestedColorCount,
            family: family
        )
        let fields = makeFields(
            actorSeed: actorSeed,
            colorCount: requestedColorCount,
            family: family
        )
        let accent = !daySeed.isMultiple(of: 4) && actorUnit(actorSeed, salt: 0xACC3_1700) > 0.46
        let construction: (Double, Double, Double, Int, Double?, Double) = switch family {
        case .gradient: (0.96, accent ? 0.035 : 0.018, 0, 0, nil, 0)
        case .solid: (1, 0.008, 0, 0, nil, 0)
        case .sphere: (0.98, 0.02, 0, 0, nil, 0)
        case .glass: (accent ? 0.72 : 0.64, 0.026, 0, 0, nil, 0)
        case .mist: (0.70, accent ? 0.095 : 0.075, 0, 0, nil, 0)
        case .halo: (accent ? 0.84 : 0.78, 0.072, 0, 0, nil, 0)
        case .luminous: (accent ? 0.94 : 0.87, 0.046, 0, 0, nil, 0)
        case .outline:
            (0.98, 0.014, 0.050 + actorUnit(actorSeed, salt: 0x0A72) * 0.012, accent ? 2 + Int(actorUnit(actorSeed, salt: 0x0A71) * 2) : 1, nil, 0)
        case .counterform:
            (0.93, 0.024, 0, 0, accent ? 0.44 : 0.36, 0.055)
        }
        return DayObjectEditorialMaterialV1(
            family: family,
            mechanism: mechanism(for: family),
            colors: colors,
            fields: fields,
            baseOpacity: construction.0,
            edgeSoftness: construction.1,
            contourWidth: construction.2,
            contourCount: construction.3,
            counterformRadius: construction.4,
            counterformSoftness: construction.5,
            structuralParameters: .zero
        )
    }

    private static func makePreviewMaterial(
        daySeed: UInt64,
        eventID: String,
        slot: Int,
        material: DayObjectEditorialPreviewMaterial,
        paletteSet: DayObjectPaletteSet
    ) -> DayObjectEditorialMaterialV1 {
        let actorSeed = daySeed ^ stableHash(eventID)
        let lightnessShift = paletteSet.actorLightnessShift ?? 0
        func displayColors(_ palette: ModernPalette) -> [SIMD3<Float>] {
            palette.hexes.map {
                DayObjectRGB(hex: $0)
                    .shiftingPerceptualLightness(by: lightnessShift)
                    .sRGB
            }
        }

        let primary = displayColors(paletteSet.primaryObjects)
        let secondary = displayColors(paletteSet.secondaryObjects)
        let actorPalette = (slot + Int(actorSeed % 3)).isMultiple(of: 3)
            ? secondary
            : primary
        let colorPool = actorPalette
        let start: Int
        if material == .wideGradient {
            let cleanCandidates = colorPool.indices.sorted {
                perceptualChroma(colorPool[$0]) > perceptualChroma(colorPool[$1])
            }.prefix(2)
            let candidates = Array(cleanCandidates)
            start = candidates[Int(actorSeed % UInt64(max(candidates.count, 1)))]
        } else {
            start = Int(actorSeed % UInt64(max(colorPool.count, 1)))
        }
        let colors: [SIMD3<Float>]
        if material == .wideGradient, colorPool.count > 1 {
            let base = colorPool[start]
            let baseColour = DayObjectRGB(sRGB: base)
            let lightnessShift: Float = baseColour.perceptualOKLab.x < 0.65 ? 0.075 : -0.075
            let tonalVariation = baseColour.shiftingPerceptualLightness(
                by: lightnessShift,
                minimumChromaFraction: 0.80
            )
            colors = [base, tonalVariation.sRGB]
        } else {
            colors = (0..<material.colorCount).map {
                colorPool[(start + $0) % colorPool.count]
            }
        }
        let fields = makePreviewFields(
            actorSeed: actorSeed,
            material: material,
            colorCount: colors.count
        )
        let accent = actorUnit(actorSeed, salt: 0xACC3_1700) > 0.54
        let construction: (Double, Double, Double, Int) = switch material {
        case .solid: (1, 0.004, 0, 0)
        case .translucentSolid: (0.58, 0.006, 0, 0)
        case .softMist: (0.64, accent ? 0.13 : 0.11, 0, 0)
        case .wideGradient: (1, 0.055, 0, 0)
        case .softOutline:
            (0.98, 0.020, 0.052 + actorUnit(actorSeed, salt: 0x0A72) * 0.010, 1)
        case .hairlineOutline:
            (0.82, 0.003, 0.0045 + actorUnit(actorSeed, salt: 0x0A73) * 0.0015, 1)
        }
        return DayObjectEditorialMaterialV1(
            family: material.family,
            mechanism: mechanism(for: material.family),
            colors: colors,
            fields: fields,
            baseOpacity: construction.0,
            edgeSoftness: construction.1,
            contourWidth: construction.2,
            contourCount: construction.3,
            counterformRadius: nil,
            counterformSoftness: 0,
            structuralParameters: .zero
        )
    }

    private static func mechanism(
        for family: DayObjectEditorialMaterialFamily
    ) -> DayObjectMaterialMechanism {
        switch family {
        case .solid: .solid
        case .gradient, .sphere, .luminous: .smoothRadial
        case .glass, .mist: .layeredMembrane
        case .halo, .outline, .counterform: .boundary
        }
    }

    private static func makePreviewFields(
        actorSeed: UInt64,
        material: DayObjectEditorialPreviewMaterial,
        colorCount: Int
    ) -> [DayObjectEditorialRadialFieldV1] {
        guard material.family != .solid, material.family != .outline else { return [] }

        if material == .wideGradient {
            let flip = actorUnit(actorSeed, salt: 0xED63) > 0.5 ? 1.0 : -1.0
            return [
                .init(
                    focus: SIMD2(0.5 - flip * 0.72, 0.22),
                    radius: 1.65,
                    softness: 0.96,
                    opacity: 1
                ),
                .init(
                    focus: SIMD2(0.5 + flip * 0.66, 0.78),
                    radius: 1.45,
                    softness: 0.94,
                    opacity: 0.88
                ),
            ]
        }

        return makeFields(
            actorSeed: actorSeed,
            colorCount: colorCount,
            family: material.family
        )
    }

    private static func perceptualChroma(_ color: SIMD3<Float>) -> Float {
        let lab = DayObjectRGB(sRGB: color).perceptualOKLab
        return hypot(lab.y, lab.z)
    }

    private static func makeColors(
        daySeed: UInt64,
        actorSeed: UInt64,
        count: Int,
        family: DayObjectEditorialMaterialFamily
    ) -> [SIMD3<Float>] {
        let baseHue = unit(daySeed ^ 0xB453_C010) * 360
        let actorHueShift = (actorUnit(actorSeed, salt: 0x48E) - 0.5) * 18
        let hueOffsets = [0.0, 68.0, 154.0]
        return (0..<count).map { index in
            let hue = baseHue + actorHueShift + hueOffsets[index]
                + (actorUnit(actorSeed, salt: UInt64(0xC01 + index)) - 0.5) * 16
            let saturationBase = family == .glass ? 0.70 : 0.80
            let saturation = saturationBase
                + actorUnit(actorSeed, salt: UInt64(0x5A7 + index)) * (0.96 - saturationBase)
            let lightnessBase = family == .glass ? 0.54 : 0.43
            let lightnessSpan = family == .glass ? 0.18 : 0.23
            let lightness = lightnessBase
                + actorUnit(actorSeed, salt: UInt64(0x119 + index)) * lightnessSpan
            return hsl(hue: hue, saturation: saturation, lightness: lightness)
        }
    }

    private static func makeFields(
        actorSeed: UInt64,
        colorCount: Int,
        family: DayObjectEditorialMaterialFamily
    ) -> [DayObjectEditorialRadialFieldV1] {
        guard family != .solid else { return [] }
        let rotation = actorUnit(actorSeed, salt: 0xF0C0_5001) * Double.pi * 2
        let focusOffsets: [(Double, Double)] = switch colorCount {
        case 1: [(0.02, -0.03)]
        case 2: [(-0.18, -0.12), (0.19, 0.13)]
        default: [(-0.23, -0.16), (0.25, -0.11), (-0.04, 0.29)]
        }
        return (0..<colorCount).map { index in
            let offset = focusOffsets[index]
            let rotatedX = offset.0 * cos(rotation) - offset.1 * sin(rotation)
            let rotatedY = offset.0 * sin(rotation) + offset.1 * cos(rotation)
            let jitterX = (actorUnit(actorSeed, salt: UInt64(0x100 + index * 7)) - 0.5) * 0.055
            let jitterY = (actorUnit(actorSeed, salt: UInt64(0x101 + index * 7)) - 0.5) * 0.055
            let radius = index == 0
                ? 0.82 + actorUnit(actorSeed, salt: UInt64(0x102 + index * 7)) * 0.13
                : 0.55 + actorUnit(actorSeed, salt: UInt64(0x102 + index * 7)) * 0.06
            return DayObjectEditorialRadialFieldV1(
                focus: SIMD2(
                    min(0.84, max(0.16, 0.5 + rotatedX + jitterX)),
                    min(0.84, max(0.16, 0.5 + rotatedY + jitterY))
                ),
                radius: radius,
                softness: 0.68 + actorUnit(actorSeed, salt: UInt64(0x103 + index * 7)) * 0.09,
                opacity: index == 0 ? 1 : 0.92 + actorUnit(actorSeed, salt: UInt64(0x104 + index * 7)) * 0.06
            )
        }
    }

    private static func makeMotion(daySeed: UInt64, eventID: String) -> DayObjectEditorialMotionV1 {
        let identity = stableHash(eventID)
        let dayDirection = -Double.pi + 2 * Double.pi * unit(daySeed ^ 0xD1CE_C710_5A11_F10F)
        let localDirection = interpolate(-0.42...0.42, unit(daySeed ^ identity ^ 0xA11C_E5D1_4EC7_10A1))
        return DayObjectEditorialMotionV1(
            period: interpolate(90...220, unit(daySeed ^ identity ^ 0x90EE_2200_4D07_10F1)),
            phase: unit(daySeed ^ identity ^ 0x0F45_EA11_10CA_1A51),
            directionBias: dayDirection + localDirection,
            amplitude: interpolate(0.045...0.115, unit(daySeed ^ identity ^ 0xA4A5_0115_5A07_10F1)),
            speedRatio: interpolate(0.82...1.18, unit(daySeed ^ identity ^ 0x5EED_8211_8A71_0F11)),
            breathingAmplitude: interpolate(0.02...0.05, unit(daySeed ^ identity ^ 0xB4EA_7050_2005_E111)),
            depthParallax: interpolate(0.018...0.060, unit(daySeed ^ identity ^ 0xDE07_0180_060A_11A1))
        )
    }

    private static func hsl(hue: Double, saturation: Double, lightness: Double) -> SIMD3<Float> {
        let normalized = ((hue.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360) / 60
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let x = chroma * (1 - abs(normalized.truncatingRemainder(dividingBy: 2) - 1))
        let channels: (Double, Double, Double) = switch normalized {
        case 0..<1: (chroma, x, 0)
        case 1..<2: (x, chroma, 0)
        case 2..<3: (0, chroma, x)
        case 3..<4: (0, x, chroma)
        case 4..<5: (x, 0, chroma)
        default: (chroma, 0, x)
        }
        let match = lightness - chroma * 0.5
        return SIMD3(Float(channels.0 + match), Float(channels.1 + match), Float(channels.2 + match))
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(0xCBF29CE484222325) { partial, byte in
            (partial ^ UInt64(byte)) &* 0x100000001B3
        }
    }

    private static func actorUnit(_ actorSeed: UInt64, salt: UInt64) -> Double {
        unit(actorSeed ^ (salt &* 0x9E3779B97F4A7C15))
    }

    private static func unit(_ seed: UInt64) -> Double {
        var state = seed &+ 0x9E3779B97F4A7C15
        state = (state ^ (state >> 30)) &* 0xBF58476D1CE4E5B9
        state = (state ^ (state >> 27)) &* 0x94D049BB133111EB
        state ^= state >> 31
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }

    private static func interpolate(_ range: ClosedRange<Double>, _ unit: Double) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}
