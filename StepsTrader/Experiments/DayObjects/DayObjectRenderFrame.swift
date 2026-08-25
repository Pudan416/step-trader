import Foundation
import simd

struct DayObjectEnvironment: Equatable {
    let motionEnergy: Double
    let visualClarity: Double
    let reduceMotion: Bool

    init(motionEnergy: Double, visualClarity: Double, reduceMotion: Bool) {
        self.motionEnergy = Self.clampedUnit(motionEnergy)
        self.visualClarity = Self.clampedUnit(visualClarity)
        self.reduceMotion = reduceMotion
    }

    var tempoScale: Double {
        guard !reduceMotion else { return 0.02 }
        let progress = motionEnergy * motionEnergy * (3 - 2 * motionEnergy)
        return 0.035 + (1.25 - 0.035) * progress
    }

    private static func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

struct DayObjectInsertionState: Equatable {
    let startedAt: Double
    let duration: Double

    init(startedAt rawStartedAt: Double, duration rawDuration: Double) {
        startedAt = rawStartedAt.isFinite ? rawStartedAt : 0
        duration = min(max(rawDuration.isFinite ? rawDuration : 0.8, 0.8), 1.4)
    }

    func envelope(at rawElapsed: Double) -> DayObjectInsertionEnvelope {
        let elapsed = rawElapsed.isFinite ? rawElapsed : 0
        let progress = min(max((elapsed - startedAt) / duration, 0), 1)
        let eased = progress * progress * (3 - 2 * progress)
        return DayObjectInsertionEnvelope(
            opacity: eased,
            scale: 0.7 + 0.3 * eased
        )
    }
}

struct DayObjectInsertionEnvelope: Equatable {
    let opacity: Double
    let scale: Double
}

struct DayObjectPostProcess: Equatable {
    let blurRadius: Double
    let contrast: Double
    let saturation: Double
    let grainIntensity: Double
    let grainPhase: Double

    init(visualClarity rawVisualClarity: Double, reduceMotion: Bool, grainSeed _: UInt64, elapsed rawElapsed: Double = 0) {
        let visualClarity = Self.clampedUnit(rawVisualClarity)
        blurRadius = pow(1 - visualClarity, 1.4) * 18
        contrast = 0.84 + 0.16 * visualClarity
        saturation = 0.88 + 0.12 * visualClarity
        grainIntensity = 0.05

        let elapsed = rawElapsed.isFinite ? max(rawElapsed, 0) : 0
        grainPhase = reduceMotion ? 0 : floor(elapsed * 12) / 12
    }

    private static func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

}

/// Compact per-frame pose data. Stable material parameters live in the
/// one-to-one `DayObjectGPUAppearance` buffer.
@_alignment(16)
struct DayObjectGPUActor: Equatable {
    static let metalAlignment = 16
    static let metalStride = 64

    let position: SIMD2<Float>       // bytes 0...7
    let direction: SIMD2<Float>      // bytes 8...15
    let halfSize: SIMD2<Float>       // bytes 16...23
    private let quadPadding: SIMD2<Float> // bytes 24...31
    let opacity: Float               // bytes 32...35
    let trailLength: Float           // bytes 36...39
    let shape: UInt32                // bytes 40...43
    let appearanceIndex: UInt32      // bytes 44...47
    let depth: Float                 // bytes 48...51
    let materialPhase: Float         // bytes 52...55
    let localDepthSoftness: Float    // bytes 56...59
    private let tailPadding: Float   // bytes 60...63

    init(
        position: SIMD2<Float>,
        direction: SIMD2<Float>,
        halfSize: SIMD2<Float>,
        opacity: Float,
        trailLength: Float,
        shape: UInt32,
        appearanceIndex: UInt32,
        depth: Float,
        materialPhase: Float,
        localDepthSoftness: Float
    ) {
        self.position = Self.finite(position)
        self.direction = Self.normalized(direction)
        self.halfSize = Self.nonnegativeFinite(halfSize)
        quadPadding = .zero
        self.opacity = Self.clampedUnit(opacity)
        self.trailLength = max(0, trailLength.isFinite ? trailLength : 0)
        self.shape = min(shape, UInt32(DayObjectShape.allCases.count - 1))
        self.appearanceIndex = appearanceIndex
        self.depth = Self.clampedUnit(depth)
        self.materialPhase = Self.normalizedPhase(materialPhase)
        self.localDepthSoftness = min(
            max(localDepthSoftness.isFinite ? localDepthSoftness : 0, 0),
            1
        )
        tailPadding = 0
    }

    /// Compatibility initializer for focused legacy mask tests while their
    /// shared-radial fixtures are replaced by material fixtures in Task 8.
    init(
        position: SIMD2<Float>,
        direction: SIMD2<Float>,
        halfSize: SIMD2<Float>,
        color _: SIMD4<Float>,
        opacity: Float,
        trailLength: Float,
        shape: UInt32,
        fill _: UInt32,
        depth: Float,
        radialVariation: Float = 0
    ) {
        self.init(
            position: position,
            direction: direction,
            halfSize: halfSize,
            opacity: opacity,
            trailLength: trailLength,
            shape: shape,
            appearanceIndex: 0,
            depth: depth,
            materialPhase: (radialVariation + 1) * 0.5,
            localDepthSoftness: 0
        )
    }

    var color: SIMD4<Float> { SIMD4(repeating: 1) }
    var fill: UInt32 { 2 }
    var radialVariation: Float { materialPhase * 2 - 1 }

    func withAppearanceIndex(_ index: UInt32) -> DayObjectGPUActor {
        DayObjectGPUActor(
            position: position,
            direction: direction,
            halfSize: halfSize,
            opacity: opacity,
            trailLength: trailLength,
            shape: shape,
            appearanceIndex: index,
            depth: depth,
            materialPhase: materialPhase,
            localDepthSoftness: localDepthSoftness
        )
    }

    private static func finite(_ value: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(value.x.isFinite ? value.x : 0, value.y.isFinite ? value.y : 0)
    }

    private static func nonnegativeFinite(_ value: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(
            value.x.isFinite ? max(value.x, 0) : 0,
            value.y.isFinite ? max(value.y, 0) : 0
        )
    }

    private static func normalized(_ value: SIMD2<Float>) -> SIMD2<Float> {
        let finite = Self.finite(value)
        let length = simd_length(finite)
        return length > 0.000_001 ? finite / length : SIMD2(1, 0)
    }

    private static func clampedUnit(_ value: Float) -> Float {
        value.isFinite ? min(max(value, 0), 1) : 0
    }

    private static func normalizedPhase(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return remainder >= 0 ? remainder : remainder + 1
    }
}

/// Stable material data uploaded once per rendered actor record.
struct DayObjectGPUAppearance: Equatable {
    static let metalAlignment = 16
    static let metalStride = 160

    let color0: SIMD4<Float>
    let color1: SIMD4<Float>
    let color2: SIMD4<Float>
    let radial0: SIMD4<Float>
    let radial1: SIMD4<Float>
    let optical0: SIMD4<Float>
    let optical1: SIMD4<Float>
    let membrane: SIMD4<Float>
    let light: SIMD4<Float>
    let metadata: SIMD4<UInt32>

    static let fallback = DayObjectGPUAppearance(
        color0: SIMD4(1, 1, 1, 1),
        color1: SIMD4(1, 1, 1, 1),
        color2: SIMD4(1, 1, 1, 1),
        radial0: SIMD4(0, 0, 1, 0),
        radial1: SIMD4(0.7, 0, 0, 2),
        optical0: SIMD4(0, 0, 1, 1),
        optical1: SIMD4(0.1, 0, 0, 0),
        membrane: .zero,
        light: SIMD4(0.7, 0, 0, 0),
        metadata: SIMD4(DayObjectMaterialFamily.satin.rawValue, 1, 1, 0)
    )

    init(
        appearance: DayObjectAppearance,
        materialRawValue: UInt32? = nil
    ) {
        var colors = appearance.colorAssignment.colors.prefix(3).map {
            SIMD4(Self.clamped($0.linearRGB), 1)
        }
        let colorCount = colors.count
        let fallbackColor = colors.last ?? SIMD4<Float>(1, 1, 1, 1)
        while colors.count < 3 { colors.append(fallbackColor) }
        let radial0 = SIMD4(
            Float(appearance.focalDistance), Float(appearance.focalAngle),
            Float(appearance.radius), Float(appearance.falloff)
        )
        let radial1 = SIMD4(
            Float(appearance.mixing), Float(appearance.distortion),
            Float(appearance.distortionShift), Float(appearance.distortionFrequency)
        )
        let optical0 = SIMD4(
            Float(appearance.innerGlow), Float(appearance.outerGlow),
            Float(appearance.bodyOpacity), Float(appearance.centerOpacity)
        )
        let optical1 = SIMD4(
            Float(appearance.rimOpacity), Float(appearance.refractionStrength),
            Float(appearance.refractionAngle), Float(appearance.localDepthSoftness)
        )
        let membrane = SIMD4(
            Float(appearance.membraneOffsets.x), Float(appearance.membraneOffsets.y),
            0, 0
        )
        let light = SIMD4(Float(appearance.lightResponse), 0, 0, 0)
        let requestedMaterial = materialRawValue ?? appearance.material.rawValue
        let material = DayObjectMaterialFamily(rawValue: requestedMaterial) ?? .satin
        self.init(
            color0: colors[0], color1: colors[1], color2: colors[2],
            radial0: radial0, radial1: radial1,
            optical0: optical0, optical1: optical1,
            membrane: membrane, light: light,
            metadata: SIMD4(
                material.rawValue,
                UInt32(min(max(colorCount, 1), 3)),
                UInt32(min(max(appearance.membraneLayerCount, 1), 3)),
                0
            )
        )
    }

    init(
        color0: SIMD4<Float>, color1: SIMD4<Float>, color2: SIMD4<Float>,
        radial0: SIMD4<Float>, radial1: SIMD4<Float>, optical0: SIMD4<Float>,
        optical1: SIMD4<Float>, membrane: SIMD4<Float>, light: SIMD4<Float>,
        metadata: SIMD4<UInt32>
    ) {
        self.color0 = Self.clampedColor(color0)
        self.color1 = Self.clampedColor(color1)
        self.color2 = Self.clampedColor(color2)
        self.radial0 = SIMD4(
            Self.bounded(radial0.x, 0...0.95),
            Self.bounded(radial0.y, -2 * .pi...2 * .pi),
            Self.bounded(radial0.z, 0.05...2),
            Self.bounded(radial0.w, -0.5...0.8)
        )
        self.radial1 = SIMD4(
            Self.bounded(radial1.x, 0...1),
            Self.bounded(radial1.y, 0...0.7),
            Self.bounded(radial1.z, -1...1),
            Self.bounded(radial1.w, 2...12)
        )
        self.optical0 = Self.clampedColor(optical0)
        self.optical1 = SIMD4(
            Self.bounded(optical1.x, 0...1),
            Self.bounded(optical1.y, 0...0.08),
            Self.bounded(optical1.z, -2 * .pi...2 * .pi),
            Self.bounded(optical1.w, 0...1)
        )
        self.membrane = SIMD4(
            Self.bounded(membrane.x, -0.2...0.2),
            Self.bounded(membrane.y, -0.2...0.2),
            Self.bounded(membrane.z, -0.2...0.2),
            Self.bounded(membrane.w, -0.2...0.2)
        )
        self.light = SIMD4(
            Self.bounded(light.x, 0...1),
            Self.bounded(light.y, -1...1),
            Self.bounded(light.z, -1...1),
            Self.bounded(light.w, -1...1)
        )
        let material = DayObjectMaterialFamily(rawValue: metadata.x) ?? .satin
        self.metadata = SIMD4(
            material.rawValue,
            min(max(metadata.y, 1), 3),
            min(max(metadata.z, 1), 3),
            metadata.w
        )
    }

    private static func finite(_ value: SIMD4<Float>) -> SIMD4<Float> {
        SIMD4(
            value.x.isFinite ? value.x : 0,
            value.y.isFinite ? value.y : 0,
            value.z.isFinite ? value.z : 0,
            value.w.isFinite ? value.w : 0
        )
    }

    private static func clampedColor(_ value: SIMD4<Float>) -> SIMD4<Float> {
        SIMD4(
            bounded(value.x, 0...1), bounded(value.y, 0...1),
            bounded(value.z, 0...1), bounded(value.w, 0...1)
        )
    }

    private static func bounded(_ value: Float, _ range: ClosedRange<Float>) -> Float {
        guard value.isFinite else { return min(max(0, range.lowerBound), range.upperBound) }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func clamped(_ value: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(
            value.x.isFinite ? min(max(value.x, 0), 1) : 0,
            value.y.isFinite ? min(max(value.y, 0), 1) : 0,
            value.z.isFinite ? min(max(value.z, 0), 1) : 0
        )
    }
}

struct DayObjectRenderActor: Equatable {
    let actorID: DayObjectActorID
    let eventID: String
    let gpuActor: DayObjectGPUActor
    let gpuAppearance: DayObjectGPUAppearance

    init(
        actorID: DayObjectActorID,
        eventID: String,
        gpuActor: DayObjectGPUActor,
        gpuAppearance: DayObjectGPUAppearance = .fallback
    ) {
        self.actorID = actorID
        self.eventID = eventID
        self.gpuActor = gpuActor
        self.gpuAppearance = gpuAppearance
    }

    var halfSize: SIMD2<Float> { gpuActor.halfSize }
    var opacity: Float { gpuActor.opacity }
    var trailLength: Float { gpuActor.trailLength }
    var depth: Float { gpuActor.depth }
}

struct DayObjectRenderFrame: Equatable {
    static let baseTempo = 0.8

    let choreographyTime: Double
    let actors: [DayObjectRenderActor]
    let postProcess: DayObjectPostProcess

    static func make(
        scene: DayObjectScene,
        environment: DayObjectEnvironment,
        elapsed rawElapsed: Double,
        insertions: [String: Double],
        removals: [String: Double] = [:],
        actorInsertions: [DayObjectActorID: Double] = [:],
        actorRemovals: [DayObjectActorID: Double] = [:],
        canvasAspect rawCanvasAspect: Double = 1
    ) -> DayObjectRenderFrame {
        let elapsed = rawElapsed.isFinite ? max(rawElapsed, 0) : 0
        let canvasAspect = rawCanvasAspect.isFinite && rawCanvasAspect > 0 ? rawCanvasAspect : 1
        let choreographyTime = environment.reduceMotion
            ? 0
            : elapsed * baseTempo * environment.tempoScale
        let postProcess = DayObjectPostProcess(
            visualClarity: environment.visualClarity,
            reduceMotion: environment.reduceMotion,
            grainSeed: scene.rootSeed,
            elapsed: elapsed
        )
        var actors = [DayObjectRenderActor]()
        actors.reserveCapacity(scene.actors.count)
        for actor in scene.actors {
            let pose = scene.score.pose(
                for: actor,
                at: choreographyTime,
                canvasAspect: canvasAspect,
                compositionPlan: scene.compositionPlan
            )
            let insertion: DayObjectInsertionEnvelope
            if let startedAt = actorInsertions[actor.id] ?? insertions[actor.eventID] {
                insertion = DayObjectInsertionState(
                    startedAt: startedAt,
                    duration: transitionDuration(for: actor)
                ).envelope(at: elapsed)
            } else {
                insertion = DayObjectInsertionEnvelope(opacity: 1, scale: 1)
            }
            let removal: DayObjectInsertionEnvelope
            if let startedAt = actorRemovals[actor.id] ?? removals[actor.eventID] {
                let forward = DayObjectInsertionState(
                    startedAt: startedAt,
                    duration: transitionDuration(for: actor)
                ).envelope(at: elapsed)
                removal = DayObjectInsertionEnvelope(
                    opacity: 1 - forward.opacity,
                    scale: 1 - 0.3 * forward.opacity
                )
            } else {
                removal = DayObjectInsertionEnvelope(opacity: 1, scale: 1)
            }
            let envelopeScale = environment.reduceMotion
                ? 1
                : insertion.scale * removal.scale
            let halfSize = bodyHalfSize(
                for: actor,
                pose: pose,
                leadership: 0,
                envelopeScale: envelopeScale
            )
            let depth = Float(pose.depth)
            let position = SIMD2<Float>(Float(pose.position.x), Float(pose.position.y))
            let direction = SIMD2<Float>(Float(pose.tangent.x), Float(pose.tangent.y))
            let gpuActor = DayObjectGPUActor(
                position: position,
                direction: direction,
                halfSize: halfSize,
                opacity: Float(pose.opacity * insertion.opacity * removal.opacity),
                trailLength: environment.reduceMotion ? 0 : Float(pose.trailReach),
                shape: numericShape(actor.appearance.shape),
                appearanceIndex: 0,
                depth: depth,
                materialPhase: environment.reduceMotion ? 0 : Float(pose.materialPhase),
                localDepthSoftness: Float(pose.localDepthSoftness)
            )
            actors.append(DayObjectRenderActor(
                actorID: actor.id,
                eventID: actor.eventID,
                gpuActor: gpuActor,
                gpuAppearance: DayObjectGPUAppearance(appearance: actor.appearance)
            ))
        }
        actors.sort { lhs, rhs in
            lhs.depth == rhs.depth ? lhs.actorID < rhs.actorID : lhs.depth < rhs.depth
        }
        actors = actors.enumerated().map { index, actor in
            DayObjectRenderActor(
                actorID: actor.actorID,
                eventID: actor.eventID,
                gpuActor: actor.gpuActor.withAppearanceIndex(UInt32(index)),
                gpuAppearance: actor.gpuAppearance
            )
        }

        return DayObjectRenderFrame(
            choreographyTime: choreographyTime,
            actors: actors,
            postProcess: postProcess
        )
    }

    static func transitionDuration(for actor: DayObjectActor) -> Double {
        0.8 + 0.6 * stableUnit(actor.seed, salt: 0xC6BC_2796_92B5_CC83)
    }

    static func leadershipEnvelopes(
        for actors: [DayObjectActor],
        at rawTime: Double,
        duration rawDuration: Double
    ) -> [DayObjectActorID: Double] {
        guard !actors.isEmpty else { return [:] }
        let duration = rawDuration.isFinite && rawDuration > 0 ? rawDuration : 1
        let time = rawTime.isFinite ? rawTime : 0
        let progress = time / duration
        let candidates = actors.map { actor -> (DayObjectActorID, Double) in
            let phase = 2 * Double.pi * stableUnit(
                actor.seed,
                salt: 0x243F_6A88_85A3_08D3
            )
            let value = 0.5 + 0.5 * cos(2 * Double.pi * progress - phase)
            return (actor.id, value)
        }
        let maximum = max(candidates.map(\.1).max() ?? 1, 0.000_001)
        return Dictionary(uniqueKeysWithValues: candidates.map {
            ($0.0, min(max($0.1 / maximum, 0), 1))
        })
    }

    private static func bodyHalfSize(
        for actor: DayObjectActor,
        pose: DayObjectPose,
        leadership: Double,
        envelopeScale: Double
    ) -> SIMD2<Float> {
        let aspect = DayObjectActorGeometry.aspectRatio(for: actor)
        _ = leadership
        let renderedDiameter = pose.scale
        let major = renderedDiameter * 0.5
        let baseHalfSize = SIMD2<Float>(Float(major), Float(major * aspect))
        return baseHalfSize * Float(envelopeScale)
    }

    private static func color(for actor: DayObjectActor, palette: DayObjectPalette) -> SIMD3<Float> {
        switch actor.role {
        case .focal, .satellite:
            return palette.figurePrimary
        case .support, .bridge:
            return palette.figureSecondary
        case .accent:
            return palette.accent
        }
    }

    private static func numericShape(_ shape: DayObjectShape) -> UInt32 {
        shape.numericValue
    }

    private static func numericFill(_ fill: DayObjectFill) -> UInt32 {
        UInt32(DayObjectFill.allCases.firstIndex(of: fill) ?? 0)
    }

    private static func stableUnit(_ seed: UInt64, salt: UInt64) -> Double {
        var value = seed ^ salt
        value &+= 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) / Double(UInt64(1) << 53)
    }
}
