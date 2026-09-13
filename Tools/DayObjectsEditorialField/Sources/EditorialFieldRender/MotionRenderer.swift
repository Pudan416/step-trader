import Foundation
import EditorialFieldCore

public struct ActorMotionTransition: Equatable, Sendable {
    public let kind: ActorTransitionKind
    public let progress: Double

    public init(kind: ActorTransitionKind, progress: Double) {
        self.kind = kind
        self.progress = progress
    }
}

public struct MotionActorFrame: Equatable, Sendable {
    public let eventID: String
    public let baseDrawOrder: Int
    public let effectiveDrawOrder: Int
    public let pose: ActorMotionPose
    public let transition: ActorTransitionPose

    public init(
        eventID: String,
        baseDrawOrder: Int,
        effectiveDrawOrder: Int,
        pose: ActorMotionPose,
        transition: ActorTransitionPose
    ) {
        self.eventID = eventID
        self.baseDrawOrder = baseDrawOrder
        self.effectiveDrawOrder = effectiveDrawOrder
        self.pose = pose
        self.transition = transition
    }
}

public struct MotionSceneFrame: Equatable, Sendable {
    public let recipe: CompositionRecipe
    public let actorFrames: [MotionActorFrame]
    public let actorCompositeOpacities: [String: Double]
    public let actorRigidRotations: [String: Double]

    public init(
        recipe: CompositionRecipe,
        actorFrames: [MotionActorFrame],
        actorCompositeOpacities: [String: Double],
        actorRigidRotations: [String: Double]
    ) {
        self.recipe = recipe
        self.actorFrames = actorFrames
        self.actorCompositeOpacities = actorCompositeOpacities
        self.actorRigidRotations = actorRigidRotations
    }
}

public enum MotionRendererError: Error, Equatable, LocalizedError {
    case actorLimitExceeded(Int)
    case duplicateCompositionActor(String)
    case invalidCompositionActor(String)
    case missingMotionRecipe(String)
    case unknownMotionRecipe(String)
    case mismatchedMotionRecipe(expectedEventID: String, actualEventID: String)
    case unknownTransition(String)

    public var errorDescription: String? {
        switch self {
        case .actorLimitExceeded(let count):
            "Motion renderer supports at most 10 actors, got \(count)"
        case .duplicateCompositionActor(let eventID):
            "Duplicate composition actor \(eventID)"
        case .invalidCompositionActor(let eventID):
            "Composition actor has non-finite or invalid geometry: \(eventID)"
        case .missingMotionRecipe(let eventID):
            "Missing motion recipe for actor \(eventID)"
        case .unknownMotionRecipe(let eventID):
            "Motion recipe has no composition actor: \(eventID)"
        case .mismatchedMotionRecipe(let expectedEventID, let actualEventID):
            "Motion recipe key \(expectedEventID) contains actor \(actualEventID)"
        case .unknownTransition(let eventID):
            "Transition has no composition actor: \(eventID)"
        }
    }
}

public struct MotionRenderer {
    public init() {}

    public func frame(
        recipe: CompositionRecipe,
        motionRecipes: [String: ActorMotionRecipe],
        phase: Double,
        steps: StepCondition,
        reduceMotion: Bool = false,
        transitions: [String: ActorMotionTransition] = [:]
    ) throws -> MotionSceneFrame {
        try makeFrame(
            recipe: recipe,
            motionRecipes: motionRecipes,
            reduceMotion: reduceMotion,
            transitions: transitions
        ) { motion, baseDepth in
            MotionField.pose(
                recipe: motion,
                phase: phase,
                steps: steps,
                reduceMotion: reduceMotion,
                baseDepth: baseDepth
            )
        }
    }

    public func frame(
        recipe: CompositionRecipe,
        motionRecipes: [String: ActorMotionRecipe],
        elapsedTime: Double,
        steps: StepCondition,
        reduceMotion: Bool = false,
        transitions: [String: ActorMotionTransition] = [:]
    ) throws -> MotionSceneFrame {
        try makeFrame(
            recipe: recipe,
            motionRecipes: motionRecipes,
            reduceMotion: reduceMotion,
            transitions: transitions
        ) { motion, baseDepth in
            MotionField.pose(
                recipe: motion,
                elapsedTime: elapsedTime,
                steps: steps,
                reduceMotion: reduceMotion,
                baseDepth: baseDepth
            )
        }
    }

    public func render(
        recipe: CompositionRecipe,
        material: DailyMaterialDNA,
        motionRecipes: [String: ActorMotionRecipe],
        background: BackgroundCondition,
        phase: Double,
        steps: StepCondition,
        reduceMotion: Bool = false,
        transitions: [String: ActorMotionTransition] = [:],
        configuration: MaterialRenderConfiguration = .init()
    ) throws -> MaterialRenderedScene {
        let frame = try frame(
            recipe: recipe,
            motionRecipes: motionRecipes,
            phase: phase,
            steps: steps,
            reduceMotion: reduceMotion,
            transitions: transitions
        )
        return try render(
            frame: frame,
            material: material,
            background: background,
            configuration: configuration
        )
    }

    public func render(
        recipe: CompositionRecipe,
        material: DailyMaterialDNA,
        motionRecipes: [String: ActorMotionRecipe],
        background: BackgroundCondition,
        elapsedTime: Double,
        steps: StepCondition,
        reduceMotion: Bool = false,
        transitions: [String: ActorMotionTransition] = [:],
        configuration: MaterialRenderConfiguration = .init()
    ) throws -> MaterialRenderedScene {
        let frame = try frame(
            recipe: recipe,
            motionRecipes: motionRecipes,
            elapsedTime: elapsedTime,
            steps: steps,
            reduceMotion: reduceMotion,
            transitions: transitions
        )
        return try render(
            frame: frame,
            material: material,
            background: background,
            configuration: configuration
        )
    }

    private func render(
        frame: MotionSceneFrame,
        material: DailyMaterialDNA,
        background: BackgroundCondition,
        configuration: MaterialRenderConfiguration
    ) throws -> MaterialRenderedScene {
        let actorPresentations = Dictionary(uniqueKeysWithValues: frame.actorFrames.map { actor in
            (
                actor.eventID,
                MaterialActorPresentation(
                    opacity: frame.actorCompositeOpacities[actor.eventID] ?? 1,
                    rigidRotation: frame.actorRigidRotations[actor.eventID] ?? 0
                )
            )
        })
        let frameConfiguration = MaterialRenderConfiguration(
            scale: configuration.scale,
            supersampling: configuration.supersampling,
            outlineVisibilityPlacement: configuration.outlineVisibilityPlacement,
            outlineCounterfactualMode: configuration.outlineCounterfactualMode,
            instrumentation: configuration.instrumentation,
            rawSceneCapture: configuration.rawSceneCapture,
            presentationEvidenceRequest: configuration.presentationEvidenceRequest,
            presentationScale: configuration.presentationScale,
            actorPresentations: actorPresentations
        )
        return try MaterialRenderer().render(
            recipe: frame.recipe,
            material: material,
            background: background,
            configuration: frameConfiguration
        )
    }

    private func makeFrame(
        recipe: CompositionRecipe,
        motionRecipes: [String: ActorMotionRecipe],
        reduceMotion: Bool,
        transitions: [String: ActorMotionTransition],
        pose: (ActorMotionRecipe, Double) -> ActorMotionPose
    ) throws -> MotionSceneFrame {
        try validate(recipe: recipe, motionRecipes: motionRecipes, transitions: transitions)

        let sampled = try recipe.actors.map { actor -> SampledActor in
            let motion = try requiredMotionRecipe(for: actor.eventID, in: motionRecipes)
            let sampledPose = pose(motion, actor.depth)
            let transition = transitions[actor.eventID].map {
                MotionField.transition(
                    kind: $0.kind,
                    progress: $0.progress,
                    reduceMotion: reduceMotion
                )
            } ?? ActorTransitionPose(opacity: 1, scale: 1)
            return SampledActor(
                base: actor,
                pose: sampledPose,
                transition: transition,
                effectiveDepth: clamp(actor.depth + sampledPose.depthOffset)
            )
        }
        let ordered = sampled.sorted {
            if $0.effectiveDepth != $1.effectiveDepth {
                return $0.effectiveDepth < $1.effectiveDepth
            }
            if $0.base.drawOrder != $1.base.drawOrder {
                return $0.base.drawOrder < $1.base.drawOrder
            }
            return $0.base.eventID < $1.base.eventID
        }
        let hasExactFrozenPoses = sampled.allSatisfy {
            $0.pose.positionOffset == CompositionPoint(x: 0, y: 0)
                && $0.pose.depthOffset == 0
                && $0.pose.scale == 1
                && $0.pose.rotation == 0
        }
        let effectiveOrders = hasExactFrozenPoses
            ? Dictionary(uniqueKeysWithValues: sampled.map {
                ($0.base.eventID, $0.base.drawOrder)
            })
            : Dictionary(uniqueKeysWithValues: ordered.enumerated().map {
                ($0.element.base.eventID, $0.offset)
            })
        let transformedActors = sampled.map { actor in
            ActorCompositionRecipe(
                eventID: actor.base.eventID,
                position: CompositionPoint(
                    x: actor.base.position.x + actor.pose.positionOffset.x
                        * recipe.viewport.shortSide / recipe.viewport.width,
                    y: actor.base.position.y + actor.pose.positionOffset.y
                        * recipe.viewport.shortSide / recipe.viewport.height
                ),
                diameter: actor.base.diameter * actor.pose.scale * actor.transition.scale,
                depth: actor.effectiveDepth,
                localBlur: actor.effectiveDepth == actor.base.depth
                    ? actor.base.localBlur
                    : max(
                        0,
                        actor.base.localBlur
                            + focusProfile(actor.effectiveDepth)
                            - focusProfile(actor.base.depth)
                    ),
                cropAllowance: actor.base.cropAllowance,
                drawOrder: effectiveOrders[actor.base.eventID] ?? actor.base.drawOrder
            )
        }
        let actorFrames = sampled.map { actor in
            MotionActorFrame(
                eventID: actor.base.eventID,
                baseDrawOrder: actor.base.drawOrder,
                effectiveDrawOrder: effectiveOrders[actor.base.eventID] ?? actor.base.drawOrder,
                pose: actor.pose,
                transition: actor.transition
            )
        }
        return MotionSceneFrame(
            recipe: CompositionRecipe(
                daySeed: recipe.daySeed,
                grammar: recipe.grammar,
                viewport: recipe.viewport,
                actors: transformedActors
            ),
            actorFrames: actorFrames,
            actorCompositeOpacities: Dictionary(uniqueKeysWithValues: sampled.map {
                ($0.base.eventID, $0.transition.opacity)
            }),
            actorRigidRotations: Dictionary(uniqueKeysWithValues: sampled.map {
                ($0.base.eventID, $0.pose.rotation)
            })
        )
    }

    private func validate(
        recipe: CompositionRecipe,
        motionRecipes: [String: ActorMotionRecipe],
        transitions: [String: ActorMotionTransition]
    ) throws {
        guard recipe.actors.count <= 10 else {
            throw MotionRendererError.actorLimitExceeded(recipe.actors.count)
        }
        var actorIDs = Set<String>()
        for actor in recipe.actors {
            guard actorIDs.insert(actor.eventID).inserted else {
                throw MotionRendererError.duplicateCompositionActor(actor.eventID)
            }
            guard actor.position.x.isFinite,
                  actor.position.y.isFinite,
                  actor.diameter.isFinite,
                  actor.diameter >= 0,
                  actor.depth.isFinite,
                  actor.localBlur.isFinite,
                  actor.localBlur >= 0,
                  actor.cropAllowance.isFinite
            else { throw MotionRendererError.invalidCompositionActor(actor.eventID) }
            _ = try requiredMotionRecipe(for: actor.eventID, in: motionRecipes)
        }
        if let unknown = motionRecipes.keys.filter({ !actorIDs.contains($0) }).sorted().first {
            throw MotionRendererError.unknownMotionRecipe(unknown)
        }
        if let unknown = transitions.keys.filter({ !actorIDs.contains($0) }).sorted().first {
            throw MotionRendererError.unknownTransition(unknown)
        }
    }

    private func requiredMotionRecipe(
        for eventID: String,
        in motionRecipes: [String: ActorMotionRecipe]
    ) throws -> ActorMotionRecipe {
        guard let motion = motionRecipes[eventID] else {
            throw MotionRendererError.missingMotionRecipe(eventID)
        }
        guard motion.eventID == eventID else {
            throw MotionRendererError.mismatchedMotionRecipe(
                expectedEventID: eventID,
                actualEventID: motion.eventID
            )
        }
        return motion
    }

    private func focusProfile(_ depth: Double) -> Double {
        0.008 * pow(abs(2 * clamp(depth) - 1), 2)
    }

    private func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private struct SampledActor {
        let base: ActorCompositionRecipe
        let pose: ActorMotionPose
        let transition: ActorTransitionPose
        let effectiveDepth: Double
    }
}
