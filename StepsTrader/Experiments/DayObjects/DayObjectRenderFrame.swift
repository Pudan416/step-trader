import Foundation
import simd

struct DayObjectsSoundPulseEvent: Equatable, Sendable {
    let sequence: UInt64
    let eventID: String
}

final class DayObjectsSoundPulseBus: @unchecked Sendable {
    private static let capacity = 32
    private let lock = NSLock()
    private var sequence: UInt64 = 0
    private var bufferedEvents = [DayObjectsSoundPulseEvent]()

    func emit(eventID: String) {
        lock.lock()
        defer { lock.unlock() }
        sequence &+= 1
        bufferedEvents.append(.init(sequence: sequence, eventID: eventID))
        if bufferedEvents.count > Self.capacity {
            bufferedEvents.removeFirst(bufferedEvents.count - Self.capacity)
        }
    }

    func events(after consumedSequence: UInt64) -> [DayObjectsSoundPulseEvent] {
        lock.lock()
        defer { lock.unlock() }
        return bufferedEvents.filter { $0.sequence > consumedSequence }
    }

    var latestSequence: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return sequence
    }
}

struct DayObjectsSoundPulseTimeline {
    private(set) var lastConsumedSequence: UInt64 = 0
    private(set) var timestamps: [String: Double] = [:]

    init(startingAfter bus: DayObjectsSoundPulseBus? = nil) {
        lastConsumedSequence = bus?.latestSequence ?? 0
    }

    mutating func consume(_ bus: DayObjectsSoundPulseBus?, at elapsed: Double) {
        if let bus {
            for event in bus.events(after: lastConsumedSequence) {
                timestamps[event.eventID] = elapsed
                lastConsumedSequence = max(lastConsumedSequence, event.sequence)
            }
        }

        timestamps = timestamps.filter { _, startedAt in
            elapsed - startedAt < DayObjectSoundResonance.duration
        }
    }
}

enum DayObjectSoundResonance {
    static let duration = 0.75

    static func scale(elapsedSinceAttack rawElapsed: Double, depth rawDepth: Double) -> Double {
        guard rawElapsed.isFinite, rawDepth.isFinite,
              rawElapsed >= 0, rawElapsed < duration else { return 1 }
        let depth = min(max(rawDepth, 0), 1)
        let attackProgress = min(rawElapsed / 0.05, 1)
        let attack = attackProgress * attackProgress * (3 - 2 * attackProgress)
        let decay = exp(-4 * rawElapsed)
        let amplitude = 0.042 - 0.016 * depth
        let oscillation = sin(2 * .pi * 5 * rawElapsed)
        return 1 + amplitude * attack * decay * oscillation
    }
}

struct DayObjectEnvironment: Equatable {
    let motionEnergy: Double
    let visualClarity: Double

    init(motionEnergy: Double, visualClarity: Double) {
        self.motionEnergy = Self.clampedUnit(motionEnergy)
        self.visualClarity = Self.clampedUnit(visualClarity)
    }

    var tempoScale: Double {
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

    init(visualClarity rawVisualClarity: Double, grainSeed _: UInt64, elapsed rawElapsed: Double = 0) {
        let visualClarity = Self.clampedUnit(rawVisualClarity)
        blurRadius = pow(1 - visualClarity, 1.4) * 18
        contrast = 0.84 + 0.16 * visualClarity
        saturation = 0.88 + 0.12 * visualClarity
        grainIntensity = 0.05

        let elapsed = rawElapsed.isFinite ? max(rawElapsed, 0) : 0
        // Drift the final monochrome grain by roughly one pixel per second.
        grainPhase = elapsed * 0.06
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
    static let metalStride = 80

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
    let silhouetteVariant: UInt32   // bytes 60...63; zero keeps curated legacy contours
    let paletteMorph: Float          // bytes 64...67
    let presentationSaturation: Float // bytes 68...71
    let removalEmphasis: Float       // bytes 72...75
    private let presentationPadding: Float // bytes 76...79

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
        localDepthSoftness: Float,
        paletteMorph: Float = 1,
        presentationSaturation: Float = 1,
        removalEmphasis: Float = 0,
        silhouetteVariant: UInt32 = 0
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
        self.silhouetteVariant = min(silhouetteVariant, 64)
        self.paletteMorph = Self.clampedUnit(paletteMorph)
        self.presentationSaturation = Self.clampedUnit(presentationSaturation)
        self.removalEmphasis = Self.clampedUnit(removalEmphasis)
        presentationPadding = 0
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
            localDepthSoftness: localDepthSoftness,
            paletteMorph: paletteMorph,
            presentationSaturation: presentationSaturation,
            removalEmphasis: removalEmphasis,
            silhouetteVariant: silhouetteVariant
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
    static let metalStride = 208

    let color0: SIMD4<Float>
    let color1: SIMD4<Float>
    let color2: SIMD4<Float>
    let radial0: SIMD4<Float>
    let radial1: SIMD4<Float>
    let radial2: SIMD4<Float>
    let field: SIMD4<Float>
    let optical0: SIMD4<Float>
    let optical1: SIMD4<Float>
    let light: SIMD4<Float>
    let recipe0: SIMD4<Float>
    let recipe1: SIMD4<Float>
    let metadata: SIMD4<UInt32>

    // Source compatibility for older focused tests. This is computed and does
    // not participate in the Metal ABI.
    var membrane: SIMD4<Float> { .zero }

    static let fallback = DayObjectGPUAppearance(
        color0: SIMD4(1, 1, 1, 1),
        color1: SIMD4(1, 1, 1, 1),
        color2: SIMD4(1, 1, 1, 1),
        radial0: SIMD4(0, 0, 1, 0.36),
        radial1: SIMD4(0.24, -0.16, 0.68, 0.42),
        radial2: SIMD4(0, 0, 0.42, 0.72),
        field: SIMD4(0, 1, 0, 0),
        optical0: SIMD4(0, 0, 1, 1),
        optical1: SIMD4(0.1, 0, 0, 0),
        light: SIMD4(0.7, 1, 0.42, 0),
        metadata: SIMD4(DayObjectMaterialFamily.gradient.rawValue, 1, 2, 0),
        recipe0: SIMD4(0.34, 0.68, 0.04, 0.72),
        recipe1: .zero
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
        let paddedLayers = Array(appearance.layers.prefix(3))
        func radialDescriptor(at index: Int) -> SIMD4<Float> {
            guard paddedLayers.indices.contains(index) else {
                return SIMD4(0, 0, 0.42, 0.72)
            }
            let layer = paddedLayers[index]
            return SIMD4(
                Float(layer.focalOffset.x), Float(layer.focalOffset.y),
                Float(layer.radius), Float(layer.softness)
            )
        }
        let layerOpacities = (0..<3).map { index -> Float in
            paddedLayers.indices.contains(index) ? Float(paddedLayers[index].opacity) : 0
        }
        let optical0 = SIMD4(
            Float(appearance.innerGlow), Float(appearance.outerGlow),
            Float(appearance.bodyOpacity), Float(appearance.centerOpacity)
        )
        let optical1 = SIMD4(
            Float(appearance.rimOpacity), Float(appearance.refractionStrength),
            Float(appearance.refractionAngle), Float(appearance.localDepthSoftness)
        )
        let field = SIMD4(
            Float(appearance.distortion), Float(appearance.distortionFrequency),
            Float(appearance.distortionPhase), Float(appearance.edgeSoftness)
        )
        let light = SIMD4(
            Float(appearance.lightResponse),
            layerOpacities[0], layerOpacities[1], layerOpacities[2]
        )
        let requestedMaterial = materialRawValue ?? appearance.material.rawValue
        let material = DayObjectMaterialFamily(rawValue: requestedMaterial) ?? .gradient
        let recipe1: SIMD4<Float>
        switch material {
        case .outline:
            recipe1 = SIMD4(
                Float(appearance.outlineCount), Float(appearance.outlineWidth),
                Float(appearance.outlineSpacing), Float(appearance.outlineWobble)
            )
        case .counterform:
            recipe1 = SIMD4(
                Float(appearance.counterformRadius), Float(appearance.counterformSoftness),
                Float(appearance.coronaWidth), Float(appearance.coronaIntensity)
            )
        default:
            recipe1 = .zero
        }
        self.init(
            color0: colors[0], color1: colors[1], color2: colors[2],
            radial0: radialDescriptor(at: 0),
            radial1: radialDescriptor(at: 1),
            radial2: radialDescriptor(at: 2),
            field: field,
            optical0: optical0, optical1: optical1,
            light: light,
            metadata: SIMD4(
                material.rawValue,
                UInt32(min(max(colorCount, 1), 3)),
                UInt32(min(max(paddedLayers.count, 1), 3)),
                appearance.mutationRole.rawValue
            ),
            recipe0: SIMD4(
                Float(appearance.colorStopLocations.x),
                Float(appearance.colorStopLocations.y),
                Float(appearance.edgeSoftness),
                Float(appearance.minimumOpacity)
            ),
            recipe1: recipe1
        )
    }

    init(
        color0: SIMD4<Float>, color1: SIMD4<Float>, color2: SIMD4<Float>,
        radial0: SIMD4<Float>, radial1: SIMD4<Float>, radial2: SIMD4<Float>,
        field: SIMD4<Float>, optical0: SIMD4<Float>, optical1: SIMD4<Float>,
        light: SIMD4<Float>,
        metadata: SIMD4<UInt32>,
        recipe0: SIMD4<Float> = SIMD4(0.34, 0.68, 0.04, 0.72),
        recipe1: SIMD4<Float> = .zero
    ) {
        self.color0 = Self.clampedColor(color0)
        self.color1 = Self.clampedColor(color1)
        self.color2 = Self.clampedColor(color2)
        self.radial0 = Self.radialDescriptor(radial0)
        self.radial1 = Self.radialDescriptor(radial1)
        self.radial2 = Self.radialDescriptor(radial2)
        self.field = SIMD4(
            Self.bounded(field.x, 0...0.18),
            Self.bounded(field.y, 0.8...4),
            Self.bounded(field.z, -2 * .pi...2 * .pi),
            Self.bounded(field.w, 0...1)
        )
        self.optical0 = Self.clampedColor(optical0)
        self.optical1 = SIMD4(
            Self.bounded(optical1.x, 0...1),
            Self.bounded(optical1.y, 0...0.08),
            Self.bounded(optical1.z, -2 * .pi...2 * .pi),
            Self.bounded(optical1.w, 0...1)
        )
        self.light = SIMD4(
            Self.bounded(light.x, 0...1),
            Self.bounded(light.y, 0...1),
            Self.bounded(light.z, 0...1),
            Self.bounded(light.w, 0...1)
        )
        self.recipe0 = SIMD4(
            Self.bounded(recipe0.x, 0.18...0.72),
            Self.bounded(recipe0.y, 0.42...0.90),
            Self.bounded(recipe0.z, 0...0.42),
            Self.bounded(recipe0.w, 0.58...0.92)
        )
        let material = DayObjectMaterialFamily(rawValue: metadata.x) ?? .gradient
        switch material {
        case .outline:
            self.recipe1 = SIMD4(
                Float(min(max(Int(recipe1.x.rounded()), 1), 3)),
                Self.bounded(recipe1.y, 0.012...0.075),
                Self.bounded(recipe1.z, 0.02...0.09),
                Self.bounded(recipe1.w, 0.01...0.08)
            )
        case .counterform:
            self.recipe1 = SIMD4(
                Self.bounded(recipe1.x, 0.44...0.62),
                Self.bounded(recipe1.y, 0.01...0.08),
                Self.bounded(recipe1.z, 0.14...0.34),
                Self.bounded(recipe1.w, 0.58...0.98)
            )
        case .gradient, .glass:
            self.recipe1 = SIMD4(
                Float(min(max(Int(Self.bounded(recipe1.x, 0...5).rounded()), 0), 5)),
                Self.bounded(recipe1.y, -2 * .pi...2 * .pi),
                Self.bounded(recipe1.z, 0...1),
                Self.bounded(recipe1.w, 0...1)
            )
        default:
            self.recipe1 = .zero
        }
        self.metadata = SIMD4(
            material.rawValue,
            min(max(metadata.y, 1), 3),
            min(max(metadata.z, 1), 3),
            min(metadata.w, UInt32(DayObjectMutationRole.allCases.count - 1))
        )
    }

    /// Compatibility initializer for the previous two-vector radial ABI.
    init(
        color0: SIMD4<Float>, color1: SIMD4<Float>, color2: SIMD4<Float>,
        radial0 legacyRadial: SIMD4<Float>, radial1 legacyField: SIMD4<Float>,
        optical0: SIMD4<Float>, optical1: SIMD4<Float>, membrane: SIMD4<Float>,
        light: SIMD4<Float>, metadata: SIMD4<UInt32>
    ) {
        let distance = Self.bounded(legacyRadial.x, 0...0.68)
        let angle = Self.bounded(legacyRadial.y, -2 * .pi...2 * .pi)
        let focus = SIMD2<Float>(cos(angle), sin(angle)) * distance
        let radius = Self.bounded(legacyRadial.z, 0.42...1.18)
        let softness = Self.bounded(legacyRadial.w + 0.24, 0.12...0.72)
        let secondFocus = focus + SIMD2(membrane.x, membrane.y)
        self.init(
            color0: color0,
            color1: color1,
            color2: color2,
            radial0: SIMD4(focus.x, focus.y, radius, softness),
            radial1: SIMD4(
                secondFocus.x, secondFocus.y,
                max(radius * 0.72, 0.42), min(softness + 0.10, 0.72)
            ),
            radial2: SIMD4(-focus.x * 0.55, -focus.y * 0.55, 0.52, 0.48),
            field: SIMD4(
                legacyField.y, legacyField.w, legacyField.z * .pi,
                optical1.w
            ),
            optical0: optical0,
            optical1: optical1,
            light: SIMD4(light.x, legacyField.x, legacyField.x * 0.65, 0.32),
            metadata: metadata
        )
    }

    private static func radialDescriptor(_ value: SIMD4<Float>) -> SIMD4<Float> {
        let finiteFocus = SIMD2(
            value.x.isFinite ? value.x : 0,
            value.y.isFinite ? value.y : 0
        )
        let focusLength = simd_length(finiteFocus)
        let focus = focusLength > 0.68 ? finiteFocus / focusLength * 0.68 : finiteFocus
        return SIMD4(
            focus.x, focus.y,
            bounded(value.z, 0.42...1.80),
            bounded(value.w, 0.12...1.0)
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
        canvasAspect rawCanvasAspect: Double = 1,
        soundPulseTimestamps: [String: Double] = [:]
    ) -> DayObjectRenderFrame {
        let elapsed = rawElapsed.isFinite ? max(rawElapsed, 0) : 0
        let canvasAspect = rawCanvasAspect.isFinite && rawCanvasAspect > 0 ? rawCanvasAspect : 1
        if let recipe = scene.sceneRecipeV1 {
            return makeEditorial(
                scene: scene,
                recipe: recipe,
                environment: environment,
                elapsed: elapsed,
                insertions: insertions,
                removals: removals,
                actorInsertions: actorInsertions,
                actorRemovals: actorRemovals,
                canvasAspect: canvasAspect,
                soundPulseTimestamps: soundPulseTimestamps
            )
        }
        let choreographyTime = elapsed * baseTempo * environment.tempoScale
        let postProcess = DayObjectPostProcess(
            visualClarity: environment.visualClarity,
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
            let resonanceScale = soundResonanceScale(
                eventID: actor.eventID,
                depth: pose.depth,
                elapsed: elapsed,
                timestamps: soundPulseTimestamps
            )
            let envelopeScale = insertion.scale * removal.scale * resonanceScale
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
                trailLength: Float(pose.trailReach),
                shape: numericShape(actor.appearance.shape),
                appearanceIndex: 0,
                depth: depth,
                materialPhase: Float(pose.materialPhase),
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

    private static func makeEditorial(
        scene: DayObjectScene,
        recipe: DayObjectSceneRecipeV1,
        environment: DayObjectEnvironment,
        elapsed: Double,
        insertions: [String: Double],
        removals: [String: Double],
        actorInsertions: [DayObjectActorID: Double],
        actorRemovals: [DayObjectActorID: Double],
        canvasAspect: Double,
        soundPulseTimestamps: [String: Double]
    ) -> DayObjectRenderFrame {
        let span = canvasAspect >= 1
            ? SIMD2<Double>(canvasAspect, 1)
            : SIMD2<Double>(1, 1 / canvasAspect)
        let actorByEventID = Dictionary(uniqueKeysWithValues: scene.actors.map { ($0.eventID, $0) })
        var rendered = [DayObjectRenderActor]()
        rendered.reserveCapacity(recipe.actors.count)

        for recipeActor in recipe.actors {
            guard let actor = actorByEventID[recipeActor.eventID] else { continue }
            let pose = recipeActor.motion.pose(
                elapsedTime: elapsed,
                energy: environment.motionEnergy
            )
            let insertion = editorialEnvelope(
                kind: .insertion,
                startedAt: actorInsertions[actor.id] ?? insertions[actor.eventID],
                elapsed: elapsed
            )
            let removal = editorialEnvelope(
                kind: .removal,
                startedAt: actorRemovals[actor.id] ?? removals[actor.eventID],
                elapsed: elapsed
            )
            let normalized = SIMD2(
                recipeActor.position.x + pose.positionOffset.x,
                recipeActor.position.y + pose.positionOffset.y
            )
            let position = SIMD2<Float>(
                Float((normalized.x - 0.5) * span.x),
                Float((normalized.y - 0.5) * span.y)
            )
            let motionLength = simd_length(pose.positionOffset)
            let direction = motionLength > 0.000_001
                ? SIMD2<Float>(Float(pose.positionOffset.x), Float(pose.positionOffset.y))
                : SIMD2<Float>(Float(cos(recipeActor.motion.directionBias)), Float(sin(recipeActor.motion.directionBias)))
            let transitionScale = insertion.scale * removal.scale
            let effectiveDepth = min(max(recipeActor.depth + pose.depthOffset, 0), 1)
            let resonanceScale = soundResonanceScale(
                eventID: actor.eventID,
                depth: effectiveDepth,
                elapsed: elapsed,
                timestamps: soundPulseTimestamps
            )
            let halfDiameter = Float(
                recipeActor.diameter * pose.scale * transitionScale * resonanceScale * 0.5
            )
            let foregroundSoftness = recipeActor.diameter > 0.4 && effectiveDepth > 0.65 ? 0.18 : 0
            let localSoftness = min(
                1,
                recipeActor.localBlur * 10 + effectiveDepth * 0.20 + foregroundSoftness
            )
            let silhouette = recipeActor.silhouette
            let silhouetteDirection = silhouette.variant == 0 ? direction
                : SIMD2<Float>(cos(silhouette.rotation), sin(silhouette.rotation))
            let gpuActor = DayObjectGPUActor(
                position: position,
                direction: silhouetteDirection,
                halfSize: SIMD2(halfDiameter, halfDiameter * silhouette.aspect),
                opacity: Float(insertion.opacity * removal.opacity),
                trailLength: 0,
                shape: recipeActor.shape.numericValue,
                appearanceIndex: 0,
                depth: Float(effectiveDepth),
                materialPhase: 0,
                localDepthSoftness: Float(localSoftness),
                silhouetteVariant: silhouette.variant
            )
            rendered.append(DayObjectRenderActor(
                actorID: actor.id,
                eventID: actor.eventID,
                gpuActor: gpuActor,
                gpuAppearance: recipeActor.material.gpuAppearance
            ))
        }

        rendered.sort { lhs, rhs in
            lhs.depth == rhs.depth ? lhs.actorID < rhs.actorID : lhs.depth < rhs.depth
        }
        rendered = rendered.enumerated().map { index, actor in
            DayObjectRenderActor(
                actorID: actor.actorID,
                eventID: actor.eventID,
                gpuActor: actor.gpuActor.withAppearanceIndex(UInt32(index)),
                gpuAppearance: actor.gpuAppearance
            )
        }
        let clarity = recipe.lowSleep ? min(environment.visualClarity, 0.42) : environment.visualClarity
        return DayObjectRenderFrame(
            choreographyTime: elapsed,
            actors: rendered,
            postProcess: DayObjectPostProcess(
                visualClarity: clarity,
                grainSeed: scene.rootSeed,
                elapsed: elapsed
            )
        )
    }

    private enum EditorialTransitionKind {
        case insertion
        case removal
    }

    private static func soundResonanceScale(
        eventID: String,
        depth: Double,
        elapsed: Double,
        timestamps: [String: Double]
    ) -> Double {
        guard let startedAt = timestamps[eventID] else { return 1 }
        return DayObjectSoundResonance.scale(
            elapsedSinceAttack: elapsed - startedAt,
            depth: depth
        )
    }

    private static func editorialEnvelope(
        kind: EditorialTransitionKind,
        startedAt: Double?,
        elapsed: Double
    ) -> DayObjectInsertionEnvelope {
        guard let startedAt else { return .init(opacity: 1, scale: 1) }
        let progress = min(max((elapsed - startedAt) / 1.1, 0), 1)
        let eased = progress * progress * progress * (progress * (progress * 6 - 15) + 10)
        switch kind {
        case .insertion:
            return .init(opacity: eased, scale: 0.96 + 0.04 * eased)
        case .removal:
            return .init(opacity: 1 - eased, scale: 1 - 0.04 * eased)
        }
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
        let major = pose.scale * 0.5
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

    private static func stableUnit(_ seed: UInt64, salt: UInt64) -> Double {
        var value = seed ^ salt
        value &+= 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) / Double(UInt64(1) << 53)
    }
}
