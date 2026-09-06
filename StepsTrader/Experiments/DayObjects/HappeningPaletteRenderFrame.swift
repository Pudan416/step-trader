import Foundation
import simd

struct HappeningPaletteRenderSlot: Equatable {
    let happeningID: String
    let assignment: HappeningEditorialAssignment
    let visualState: HappeningPaletteSlotVisualState
    let source: HappeningFieldLayout.Source
}

struct HappeningPaletteRenderPresentation: Equatable {
    let slots: [HappeningPaletteRenderSlot]
    let viewportSize: CGSize
    let reduceMotion: Bool
    let isTransitionActive: Bool
    let backgroundRevision: UInt64
}

enum DayObjectsPresentationMode: Equatable {
    case canvas
    case happeningPalette(HappeningPaletteRenderPresentation)

    var prefersSixtyFPS: Bool {
        guard case let .happeningPalette(value) = self else { return false }
        return value.isTransitionActive
    }
}

struct HappeningPaletteRenderControls: Equatable {
    let paletteMorph: Double
    let saturation: Double
    let removalEmphasis: Double
    let scale: Double
    let opacity: Double
    let depth: Double

    static func target(for state: HappeningPaletteSlotVisualState) -> Self {
        switch state {
        case .available:
            Self(paletteMorph: 0, saturation: 1, removalEmphasis: 0, scale: 1, opacity: 1, depth: 0.45)
        case .additionPreview:
            Self(paletteMorph: 1, saturation: 1, removalEmphasis: 0, scale: 1.06, opacity: 1, depth: 0.90)
        case .added:
            Self(paletteMorph: 1, saturation: 0.08, removalEmphasis: 0, scale: 0.98, opacity: 0.82, depth: 0.45)
        case .removalPreview:
            Self(paletteMorph: 1, saturation: 0.08, removalEmphasis: 1, scale: 1.04, opacity: 0.88, depth: 0.90)
        }
    }

    func interpolated(to target: Self, progress: Double) -> Self {
        Self(
            paletteMorph: interpolate(paletteMorph, target.paletteMorph, progress),
            saturation: interpolate(saturation, target.saturation, progress),
            removalEmphasis: interpolate(removalEmphasis, target.removalEmphasis, progress),
            scale: interpolate(scale, target.scale, progress),
            opacity: interpolate(opacity, target.opacity, progress),
            depth: interpolate(depth, target.depth, progress)
        )
    }
}

struct HappeningPaletteRenderSample: Equatable {
    struct Slot: Equatable {
        let happeningID: String
        let assignment: HappeningEditorialAssignment
        let source: HappeningFieldLayout.Source
        let controls: HappeningPaletteRenderControls
    }

    let slots: [Slot]

    func controls(for happeningID: String) -> HappeningPaletteRenderControls {
        slots.first(where: { $0.happeningID == happeningID })?.controls
            ?? HappeningPaletteRenderControls.target(for: .available)
    }
}

struct HappeningPaletteTransitionTimeline {
    private static let transitionDuration = 0.34
    private static let reducedMotionFadeDuration = 0.10

    private struct PriorSlot {
        let assignment: HappeningEditorialAssignment
        let source: HappeningFieldLayout.Source
        let controls: HappeningPaletteRenderControls
    }

    private struct Transition {
        let prior: PriorSlot
        let startedAt: Double
    }

    private var presentation: HappeningPaletteRenderPresentation?
    private var transitions: [String: Transition] = [:]

    func hasActiveTransitions(at rawElapsed: Double) -> Bool {
        guard let presentation else { return false }
        let elapsed = normalizedElapsed(rawElapsed)
        let duration = presentation.reduceMotion
            ? Self.reducedMotionFadeDuration * 2
            : Self.transitionDuration
        return transitions.values.contains { max(elapsed - $0.startedAt, 0) < duration }
    }

    mutating func update(to next: HappeningPaletteRenderPresentation, elapsed rawElapsed: Double) {
        let elapsed = normalizedElapsed(rawElapsed)
        guard let presentation else {
            self.presentation = next
            transitions = [:]
            return
        }

        let existingSample = sample(at: elapsed)
        let existingByID = Dictionary(uniqueKeysWithValues: existingSample.slots.map { ($0.happeningID, $0) })
        let currentSlots = Dictionary(uniqueKeysWithValues: presentation.slots.map { ($0.happeningID, $0) })
        var nextTransitions = [String: Transition]()

        for slot in next.slots {
            if destinationChanged(
                from: currentSlots[slot.happeningID],
                to: slot,
                reduceMotionChanged: presentation.reduceMotion != next.reduceMotion
            ), let current = existingByID[slot.happeningID] {
                nextTransitions[slot.happeningID] = Transition(
                    prior: PriorSlot(
                        assignment: current.assignment,
                        source: current.source,
                        controls: current.controls
                    ),
                    startedAt: elapsed
                )
            } else if let existing = transitions[slot.happeningID] {
                nextTransitions[slot.happeningID] = existing
            }
        }

        self.presentation = next
        transitions = nextTransitions
    }

    func sample(at rawElapsed: Double) -> HappeningPaletteRenderSample {
        guard let presentation else { return HappeningPaletteRenderSample(slots: []) }
        let elapsed = normalizedElapsed(rawElapsed)

        return HappeningPaletteRenderSample(slots: presentation.slots.map { slot in
            let target = HappeningPaletteRenderControls.target(for: slot.visualState)
            guard let transition = transitions[slot.happeningID] else {
                return .init(
                    happeningID: slot.happeningID,
                    assignment: slot.assignment,
                    source: slot.source,
                    controls: target
                )
            }
            let elapsedSinceTransition = max(elapsed - transition.startedAt, 0)
            let prior = transition.prior

            if presentation.reduceMotion {
                let fade = Self.reducedMotionFadeDuration
                if elapsedSinceTransition < fade {
                    return .init(
                        happeningID: slot.happeningID,
                        assignment: prior.assignment,
                        source: prior.source,
                        controls: withOpacity(prior.controls, multiplier: 1 - elapsedSinceTransition / fade)
                    )
                }
                if elapsedSinceTransition < fade * 2 {
                    return .init(
                        happeningID: slot.happeningID,
                        assignment: slot.assignment,
                        source: slot.source,
                        controls: withOpacity(target, multiplier: (elapsedSinceTransition - fade) / fade)
                    )
                }
                return .init(
                    happeningID: slot.happeningID,
                    assignment: slot.assignment,
                    source: slot.source,
                    controls: target
                )
            }

            let progress = min(elapsedSinceTransition / Self.transitionDuration, 1)
            let smoothProgress = progress * progress * (3 - 2 * progress)
            return .init(
                happeningID: slot.happeningID,
                assignment: slot.assignment,
                source: interpolatedSource(from: prior.source, to: slot.source, progress: smoothProgress),
                controls: prior.controls.interpolated(to: target, progress: smoothProgress)
            )
        })
    }

    private func destinationChanged(
        from current: HappeningPaletteRenderSlot?,
        to next: HappeningPaletteRenderSlot,
        reduceMotionChanged: Bool
    ) -> Bool {
        guard let current else { return false }
        return reduceMotionChanged
            || current.assignment != next.assignment
            || current.source != next.source
            || HappeningPaletteRenderControls.target(for: current.visualState)
                != HappeningPaletteRenderControls.target(for: next.visualState)
    }

    private func interpolatedSource(
        from source: HappeningFieldLayout.Source,
        to target: HappeningFieldLayout.Source,
        progress: Double
    ) -> HappeningFieldLayout.Source {
        HappeningFieldLayout.Source(
            index: target.index,
            center: CGPoint(
                x: interpolate(Double(source.center.x), Double(target.center.x), progress),
                y: interpolate(Double(source.center.y), Double(target.center.y), progress)
            ),
            radius: interpolate(Double(source.radius), Double(target.radius), progress)
        )
    }
}

enum HappeningPaletteRenderFrame {
    static func make(
        presentation: HappeningPaletteRenderPresentation,
        scene: DayObjectScene,
        elapsed rawElapsed: Double,
        timeline: HappeningPaletteTransitionTimeline? = nil
    ) -> DayObjectRenderFrame {
        let elapsed = normalizedElapsed(rawElapsed)
        let sample = timeline?.sample(at: elapsed) ?? HappeningPaletteRenderSample(
            slots: presentation.slots.map {
                .init(
                    happeningID: $0.happeningID,
                    assignment: $0.assignment,
                    source: $0.source,
                    controls: .target(for: $0.visualState)
                )
            }
        )
        let shortSide = max(min(presentation.viewportSize.width, presentation.viewportSize.height), 1)
        let actors = sample.slots.map { slot in
            let position = SIMD2<Float>(
                Float((slot.source.center.x - presentation.viewportSize.width / 2) / shortSide),
                Float((slot.source.center.y - presentation.viewportSize.height / 2) / shortSide)
            )
            let halfSize = Float(slot.source.radius / shortSide * slot.controls.scale)
            return DayObjectRenderActor(
                actorID: DayObjectActorID(eventID: slot.happeningID, memberIndex: 0),
                eventID: slot.happeningID,
                gpuActor: DayObjectGPUActor(
                    position: position,
                    direction: SIMD2(0, -1),
                    halfSize: SIMD2(repeating: halfSize),
                    opacity: Float(slot.controls.opacity),
                    trailLength: 0,
                    shape: slot.assignment.shape.numericValue,
                    appearanceIndex: 0,
                    depth: Float(slot.controls.depth),
                    materialPhase: 0,
                    localDepthSoftness: 0,
                    paletteMorph: Float(slot.controls.paletteMorph),
                    presentationSaturation: Float(slot.controls.saturation),
                    removalEmphasis: Float(slot.controls.removalEmphasis)
                ),
                gpuAppearance: slot.assignment.material.gpuAppearance
            )
        }.sorted { $0.gpuActor.depth < $1.gpuActor.depth }

        return DayObjectRenderFrame(
            choreographyTime: elapsed,
            actors: actors,
            postProcess: DayObjectPostProcess(
                visualClarity: 1,
                grainSeed: scene.rootSeed,
                elapsed: elapsed
            )
        )
    }
}

private func interpolate(_ start: Double, _ end: Double, _ progress: Double) -> Double {
    start + (end - start) * min(max(progress, 0), 1)
}

private func withOpacity(_ controls: HappeningPaletteRenderControls, multiplier: Double) -> HappeningPaletteRenderControls {
    HappeningPaletteRenderControls(
        paletteMorph: controls.paletteMorph,
        saturation: controls.saturation,
        removalEmphasis: controls.removalEmphasis,
        scale: controls.scale,
        opacity: controls.opacity * min(max(multiplier, 0), 1),
        depth: controls.depth
    )
}

private func normalizedElapsed(_ elapsed: Double) -> Double {
    elapsed.isFinite ? max(elapsed, 0) : 0
}
