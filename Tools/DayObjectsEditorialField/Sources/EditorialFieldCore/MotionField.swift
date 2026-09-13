import Foundation

public struct ActorMotionRecipe: Codable, Equatable, Sendable {
    public let eventID: String
    public let period: Double
    public let phase: Double
    public let directionBias: Double
    public let amplitude: Double
    public let speedRatio: Double
    public let breathingAmplitude: Double
    public let depthParallax: Double

    public init(
        eventID: String,
        period: Double,
        phase: Double,
        directionBias: Double,
        amplitude: Double,
        speedRatio: Double,
        breathingAmplitude: Double,
        depthParallax: Double
    ) {
        self.eventID = eventID
        self.period = period
        self.phase = phase
        self.directionBias = directionBias
        self.amplitude = amplitude
        self.speedRatio = speedRatio
        self.breathingAmplitude = breathingAmplitude
        self.depthParallax = depthParallax
    }
}

public struct ActorMotionPose: Codable, Equatable, Sendable {
    public let positionOffset: CompositionPoint
    public let depthOffset: Double
    public let scale: Double
    public let rotation: Double

    public init(
        positionOffset: CompositionPoint,
        depthOffset: Double,
        scale: Double,
        rotation: Double
    ) {
        self.positionOffset = positionOffset
        self.depthOffset = depthOffset
        self.scale = scale
        self.rotation = rotation
    }
}

public enum ActorTransitionKind: String, Codable, Sendable {
    case insertion
    case removal
}

public struct ActorTransitionPose: Codable, Equatable, Sendable {
    public let opacity: Double
    public let scale: Double

    public init(opacity: Double, scale: Double) {
        self.opacity = opacity
        self.scale = scale
    }
}

public enum MotionField {
    public static func make<EventIDs: Sequence>(
        daySeed: UInt64,
        eventIDs: EventIDs
    ) -> [String: ActorMotionRecipe] where EventIDs.Element == String {
        let requested = Set(eventIDs)
        let canonical = CorpusManifest.canonicalEventIDs
        let canonicalSet = Set(canonical)
        let extras = requested.subtracting(canonicalSet).sorted()
        let admitted = Array((canonical.filter(requested.contains) + extras).prefix(10))
        let dayDirection = -Double.pi + 2 * Double.pi * unit(
            from: daySeed ^ 0xD1CE_C710_5A11_F10F
        )

        return Dictionary(uniqueKeysWithValues: admitted.map { eventID in
            let identity = stableHash(eventID)
            let localDirection = interpolate(
                -0.42...0.42,
                unit(from: daySeed ^ identity ^ 0xA11C_E5D1_4EC7_10A1)
            )
            let recipe = ActorMotionRecipe(
                eventID: eventID,
                period: interpolate(
                    90...220,
                    unit(from: daySeed ^ identity ^ 0x90EE_2200_4D07_10F1)
                ),
                phase: unit(from: daySeed ^ identity ^ 0x0F45_EA11_10CA_1A51),
                directionBias: wrappedAngle(dayDirection + localDirection),
                amplitude: interpolate(
                    0.045...0.115,
                    unit(from: daySeed ^ identity ^ 0xA4A5_0115_5A07_10F1)
                ),
                speedRatio: interpolate(
                    0.82...1.18,
                    unit(from: daySeed ^ identity ^ 0x5EED_8211_8A71_0F11)
                ),
                breathingAmplitude: interpolate(
                    0.02...0.05,
                    unit(from: daySeed ^ identity ^ 0xB4EA_7050_2005_E111)
                ),
                depthParallax: interpolate(
                    0.018...0.060,
                    unit(from: daySeed ^ identity ^ 0xDE07_0180_060A_11A1)
                )
            )
            return (eventID, recipe)
        })
    }

    public static func phase(
        recipe: ActorMotionRecipe,
        elapsedTime: Double,
        steps: StepCondition
    ) -> Double {
        guard elapsedTime.isFinite else { return 0 }
        let period = bounded(recipe.period, to: 90...220, fallback: 155)
        let speedRatio = bounded(recipe.speedRatio, to: 0.82...1.18, fallback: 1)
        let tempo = steps == .low ? 0.12 : 1.0
        return canonicalPhase(elapsedTime / period * speedRatio * tempo)
    }

    public static func pose(
        recipe: ActorMotionRecipe,
        phase: Double,
        steps _: StepCondition,
        reduceMotion: Bool = false,
        baseDepth: Double = 0.5
    ) -> ActorMotionPose {
        guard !reduceMotion else { return neutralPose }
        let cycle = canonicalPhase(phase)
        guard cycle != 0 else { return neutralPose }

        let depth = baseDepth.isFinite ? min(1, max(0, baseDepth)) : 0.5
        let baselinePhase = canonicalPhase(recipe.phase)
        let samplePhase = canonicalPhase(baselinePhase + cycle)
        let direction = recipe.directionBias.isFinite ? wrappedAngle(recipe.directionBias) : 0
        let amplitude = bounded(recipe.amplitude, to: 0.045...0.115, fallback: 0.08)
        let breathingAmplitude = bounded(
            recipe.breathingAmplitude,
            to: 0.02...0.05,
            fallback: 0.035
        )
        let depthParallax = bounded(recipe.depthParallax, to: 0.018...0.060, fallback: 0.039)
        let sample = flow(at: samplePhase)
        let baseline = flow(at: baselinePhase)
        let rawX = (sample.x - baseline.x) * 0.35
        let rawY = (sample.y - baseline.y) * 0.35
        let cosine = cos(direction)
        let sine = sin(direction)
        let depthTranslation = 0.72 + 0.43 * depth
        let translatedX = (rawX * cosine - rawY * sine)
            * amplitude * depthTranslation
        let translatedY = (rawX * sine + rawY * cosine)
            * amplitude * depthTranslation

        let depthSample = depthWave(at: samplePhase)
        let depthBaseline = depthWave(at: baselinePhase)
        let depthMultiplier = 0.65 + 0.35 * depth
        let depthOffset = (depthSample - depthBaseline) * 0.5
            * depthParallax * depthMultiplier

        let breathSample = breathingWave(at: samplePhase)
        let breathBaseline = breathingWave(at: baselinePhase)
        let scale = 1 + (breathSample - breathBaseline) * 0.5
            * breathingAmplitude

        let rotationSample = rotationWave(at: samplePhase)
        let rotationBaseline = rotationWave(at: baselinePhase)
        let rotation = (rotationSample - rotationBaseline) * 0.003

        return ActorMotionPose(
            positionOffset: CompositionPoint(x: translatedX, y: translatedY),
            depthOffset: depthOffset,
            scale: scale,
            rotation: rotation
        )
    }

    public static func pose(
        recipe: ActorMotionRecipe,
        elapsedTime: Double,
        steps: StepCondition,
        reduceMotion: Bool = false,
        baseDepth: Double = 0.5
    ) -> ActorMotionPose {
        pose(
            recipe: recipe,
            phase: phase(recipe: recipe, elapsedTime: elapsedTime, steps: steps),
            steps: steps,
            reduceMotion: reduceMotion,
            baseDepth: baseDepth
        )
    }

    public static func transition(
        kind: ActorTransitionKind,
        progress: Double,
        reduceMotion: Bool = false
    ) -> ActorTransitionPose {
        let clamped = progress.isNaN ? 0 : min(1, max(0, progress))
        let eased = clamped * clamped * clamped
            * (clamped * (clamped * 6 - 15) + 10)
        let opacity: Double
        let scale: Double
        switch kind {
        case .insertion:
            opacity = eased
            scale = 0.96 + 0.04 * eased
        case .removal:
            opacity = 1 - eased
            scale = 1 - 0.04 * eased
        }
        return ActorTransitionPose(
            opacity: opacity,
            scale: reduceMotion ? 1 : scale
        )
    }

    private static let neutralPose = ActorMotionPose(
        positionOffset: CompositionPoint(x: 0, y: 0),
        depthOffset: 0,
        scale: 1,
        rotation: 0
    )

    private static func flow(at phase: Double) -> CompositionPoint {
        let angle = 2 * Double.pi * phase
        return CompositionPoint(
            x: 0.90 * sin(angle) + 0.07 * sin(2 * angle) + 0.03 * cos(3 * angle),
            y: 0.86 * cos(angle) - 0.09 * cos(2 * angle) + 0.05 * sin(3 * angle)
        )
    }

    private static func depthWave(at phase: Double) -> Double {
        let angle = 2 * Double.pi * phase
        return 0.62 * sin(angle) + 0.25 * cos(2 * angle) + 0.13 * sin(3 * angle)
    }

    private static func breathingWave(at phase: Double) -> Double {
        let angle = 2 * Double.pi * phase
        return 0.58 * sin(angle + 0.35)
            + 0.27 * cos(2 * angle - 0.50)
            + 0.15 * sin(3 * angle + 0.80)
    }

    private static func rotationWave(at phase: Double) -> Double {
        let angle = 2 * Double.pi * phase
        return 0.55 * sin(angle - 0.20)
            + 0.30 * cos(2 * angle + 0.45)
            + 0.15 * sin(3 * angle - 0.70)
    }

    private static func canonicalPhase(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let canonical = value - floor(value)
        return canonical == 0 ? 0 : canonical
    }

    private static func wrappedAngle(_ value: Double) -> Double {
        let turn = 2 * Double.pi
        let wrapped = (value + Double.pi).truncatingRemainder(dividingBy: turn)
        return (wrapped < 0 ? wrapped + turn : wrapped) - Double.pi
    }

    private static func interpolate(_ range: ClosedRange<Double>, _ unit: Double) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }

    private static func bounded(
        _ value: Double,
        to range: ClosedRange<Double>,
        fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(0xCBF29CE484222325) { partial, byte in
            (partial ^ UInt64(byte)) &* 0x100000001B3
        }
    }

    private static func unit(from seed: UInt64) -> Double {
        var value = seed &+ 0x9E3779B97F4A7C15
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) / Double(UInt64(1) << 53)
    }
}
