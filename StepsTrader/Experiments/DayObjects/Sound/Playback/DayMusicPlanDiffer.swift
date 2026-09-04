#if DEBUG || INTERNAL_BUILD
enum DayMusicPlanDiffer {
    static func change(from oldPlan: DayMusicPlan, to newPlan: DayMusicPlan) -> DayMusicPlanChange {
        let oldHappenings = stableUniqueHappenings(oldPlan.happenings)
        let newHappenings = stableUniqueHappenings(newPlan.happenings)
        let oldHappeningsByID = indexedByID(oldHappenings)
        let newHappeningsByID = indexedByID(newHappenings)

        let addedHappenings = newHappenings.filter {
            oldHappeningsByID[$0.happeningID] == nil
        }
        let removedHappeningIDs = oldHappenings.compactMap {
            newHappeningsByID[$0.happeningID] == nil ? $0.happeningID : nil
        }

        let hasDedicatedHappeningChange = !addedHappenings.isEmpty || !removedHappeningIDs.isEmpty
        let hasLayerMixChange = hasDedicatedHappeningChange
            ? NonHappeningLayerMixSignature(plan: oldPlan.mix)
                != NonHappeningLayerMixSignature(plan: newPlan.mix)
            : oldPlan.mix != newPlan.mix
        let hasContinuousChange = continuousSignature(of: oldPlan) != continuousSignature(of: newPlan)
            || hasLayerMixChange
        let hasStructuralChange = structuralSignature(
            of: oldPlan,
            commonWith: newPlan
        ) != structuralSignature(
            of: newPlan,
            commonWith: oldPlan
        )

        return DayMusicPlanChange(
            continuousPlan: hasContinuousChange ? newPlan : nil,
            structuralPlan: hasStructuralChange ? newPlan : nil,
            addedHappenings: addedHappenings,
            removedHappeningIDs: removedHappeningIDs
        )
    }

    private static func continuousSignature(of plan: DayMusicPlan) -> ContinuousSignature {
        ContinuousSignature(
            stepsProgress: plan.input.stepsProgress,
            sleepProgress: plan.input.sleepProgress,
            glitchProgress: plan.input.glitchProgress,
            motionEnergy: plan.input.motionEnergy,
            visualClarity: plan.input.visualClarity,
            rhythm: ContinuousRhythmSignature(plan: plan.rhythm),
            bass: plan.bass.map(ContinuousBassSignature.init),
            harmonyRoles: plan.harmony.roles.map(ContinuousHarmonyRoleSignature.init),
            lead: ContinuousLeadSignature(plan: plan.lead),
            glitch: ContinuousGlitchSignature(plan: plan.glitch)
        )
    }

    private static func structuralSignature(
        of plan: DayMusicPlan,
        commonWith otherPlan: DayMusicPlan
    ) -> StructuralSignature {
        let otherIDs = Set(otherPlan.happenings.map(\.happeningID))
        let commonHappenings = stableUniqueHappenings(plan.happenings).filter {
            otherIDs.contains($0.happeningID)
        }

        return StructuralSignature(
            seed: plan.seed,
            world: plan.world,
            rhythm: StructuralRhythmSignature(plan: plan.rhythm),
            groove: StructuralGrooveSignature(plan: plan.groove),
            bass: plan.bass.map(StructuralBassSignature.init),
            harmony: StructuralHarmonySignature(plan: plan.harmony),
            existingHappenings: commonHappenings,
            lead: StructuralLeadSignature(plan: plan.lead),
            glitch: StructuralGlitchSignature(plan: plan.glitch)
        )
    }

    private static func indexedByID(
        _ happenings: [HappeningMusicPlan]
    ) -> [String: HappeningMusicPlan] {
        happenings.reduce(into: [:]) { result, plan in
            result[plan.happeningID] = plan
        }
    }

    private static func stableUniqueHappenings(
        _ happenings: [HappeningMusicPlan]
    ) -> [HappeningMusicPlan] {
        var seen = Set<String>()
        return happenings.filter { seen.insert($0.happeningID).inserted }
    }
}

private struct ContinuousSignature: Equatable {
    let stepsProgress: Double
    let sleepProgress: Double
    let glitchProgress: Double
    let motionEnergy: Double
    let visualClarity: Double
    let rhythm: ContinuousRhythmSignature
    let bass: ContinuousBassSignature?
    let harmonyRoles: [ContinuousHarmonyRoleSignature]
    let lead: ContinuousLeadSignature
    let glitch: ContinuousGlitchSignature
}

private struct ContinuousBassSignature: Equatable {
    let activeEvents: [ContinuousBassEventSignature]
    let cutoffMultiplier: Double
    let glideMilliseconds: Double
    let reverbSend: Double
    let duckingDecibels: Double

    init(plan: BassPlan) {
        activeEvents = plan.activeEvents.map(ContinuousBassEventSignature.init)
        cutoffMultiplier = plan.cutoffMultiplier
        glideMilliseconds = plan.glideMilliseconds
        reverbSend = plan.reverbSend
        duckingDecibels = plan.ducking.maximumAttenuationDecibels
    }
}

private struct ContinuousBassEventSignature: Equatable {
    let stableID: UInt64
    let velocity: Double

    init(plan: BassEventPlan) {
        stableID = plan.stableID
        velocity = plan.velocity
    }
}

private struct ContinuousRhythmSignature: Equatable {
    let tempoBPM: Double
    let stepsProgress: Double
    let voices: [ContinuousRhythmVoiceSignature]
    let maximumMicrotimingMilliseconds: Double
    let velocityHumanizationRange: ClosedRange<Double>
    let maximumHarmonyDuckingDecibels: Double

    init(plan: RhythmPlan) {
        tempoBPM = plan.tempoBPM
        stepsProgress = plan.stepsProgress
        voices = plan.voices.map(ContinuousRhythmVoiceSignature.init)
        maximumMicrotimingMilliseconds = plan.maximumMicrotimingMilliseconds
        velocityHumanizationRange = plan.velocityHumanizationRange
        maximumHarmonyDuckingDecibels = plan.maximumHarmonyDuckingDecibels
    }
}

private struct ContinuousRhythmVoiceSignature: Equatable {
    let role: RhythmRole
    let stepProbabilities: [Double]
    let velocityRange: ClosedRange<Double>
    let microtimingMilliseconds: ClosedRange<Double>
    let roomSend: Double
    let activationAmount: Double

    init(plan: RhythmVoicePlan) {
        role = plan.role
        stepProbabilities = plan.stepProbabilities
        velocityRange = plan.velocityRange
        microtimingMilliseconds = plan.microtimingMilliseconds
        roomSend = plan.roomSend
        activationAmount = plan.activation.amount
    }
}

private struct ContinuousHarmonyRoleSignature: Equatable {
    let role: HarmonyRole
    let gain: Double
    let attackSeconds: Double
    let releaseSeconds: Double
    let delaySend: Double
    let reverbSend: Double
    let activationAmount: Double

    init(plan: HarmonyRolePlan) {
        role = plan.role
        gain = plan.gain
        attackSeconds = plan.attackSeconds
        releaseSeconds = plan.releaseSeconds
        delaySend = plan.delaySend
        reverbSend = plan.reverbSend
        activationAmount = plan.activation.amount
    }
}

private struct ContinuousLeadSignature: Equatable {
    let cutoffMultiplierRange: ClosedRange<Double>
    let pitchSmoothingMilliseconds: Double
    let expressionSmoothingMilliseconds: Double
    let maximumExpressionDepth: Double
    let delaySend: Double
    let reverbSend: Double

    init(plan: LeadPlan) {
        cutoffMultiplierRange = plan.cutoffMultiplierRange
        pitchSmoothingMilliseconds = plan.pitchSmoothingMilliseconds
        expressionSmoothingMilliseconds = plan.expressionSmoothingMilliseconds
        maximumExpressionDepth = plan.maximumExpressionDepth
        delaySend = plan.delaySend
        reverbSend = plan.reverbSend
    }
}

private struct ContinuousGlitchSignature: Equatable {
    let progress: Double
    let roleAmounts: [ContinuousGlitchRoleSignature]
    let wowFlutterDepth: Double
    let stereoSeparationAddition: Double

    init(plan: GlitchPlan) {
        progress = plan.progress
        roleAmounts = plan.roles.map(ContinuousGlitchRoleSignature.init)
        wowFlutterDepth = plan.wowFlutterDepth
        stereoSeparationAddition = plan.stereoSeparationAddition
    }
}

private struct ContinuousGlitchRoleSignature: Equatable {
    let pitchDriftCents: Double
    let dropoutProbability: Double
    let delayTimeInstability: Double
    let saturationAmount: Double
    let timingDriftMilliseconds: Double

    init(plan: GlitchRolePlan) {
        pitchDriftCents = plan.pitchDriftCents
        dropoutProbability = plan.dropoutProbability
        delayTimeInstability = plan.delayTimeInstability
        saturationAmount = plan.saturationAmount
        timingDriftMilliseconds = plan.timingDriftMilliseconds
    }
}

private struct NonHappeningLayerMixSignature: Equatable {
    let rhythmTargetDecibels: Double
    let harmonyTargetDecibels: Double
    let leadTargetDecibels: Double
    let masterTargetDecibelsBeforeLimiter: Double
    let maximumHarmonyDuckingDecibels: Double

    init(plan: LayerMixPlan) {
        rhythmTargetDecibels = plan.rhythmTargetDecibels
        harmonyTargetDecibels = plan.harmonyTargetDecibels
        leadTargetDecibels = plan.leadTargetDecibels
        masterTargetDecibelsBeforeLimiter = plan.masterTargetDecibelsBeforeLimiter
        maximumHarmonyDuckingDecibels = plan.maximumHarmonyDuckingDecibels
    }
}

private struct StructuralSignature: Equatable {
    let seed: UInt64
    let world: TonalWorldPlan
    let rhythm: StructuralRhythmSignature
    let groove: StructuralGrooveSignature
    let bass: StructuralBassSignature?
    let harmony: StructuralHarmonySignature
    let existingHappenings: [HappeningMusicPlan]
    let lead: StructuralLeadSignature
    let glitch: StructuralGlitchSignature
}

private struct StructuralGrooveSignature: Equatable {
    let mode: GrooveMode

    init(plan: GroovePlan) {
        mode = plan.mode
    }
}

private struct StructuralBassSignature: Equatable {
    let mode: GrooveMode
    let instrumentID: DayObjectsInstrumentID
    let articulation: BassArticulation
    let register: ClosedRange<UInt8>
    let events: [StructuralBassEventSignature]
    let duckAttackSeconds: Double
    let duckHoldSeconds: Double
    let duckReleaseSeconds: Double

    init(plan: BassPlan) {
        mode = plan.mode
        instrumentID = plan.instrumentID
        articulation = plan.articulation
        register = plan.register
        events = plan.events.map(StructuralBassEventSignature.init)
        duckAttackSeconds = plan.ducking.attackSeconds
        duckHoldSeconds = plan.ducking.holdSeconds
        duckReleaseSeconds = plan.ducking.releaseSeconds
    }
}

private struct StructuralBassEventSignature: Equatable {
    let stableID: UInt64
    let chordIndex: Int
    let startSubdivision: Int64
    let durationSubdivisions: Int64
    let midiNote: UInt8
    let allowedPitchClasses: Set<Int>

    init(plan: BassEventPlan) {
        stableID = plan.stableID
        chordIndex = plan.chordIndex
        startSubdivision = plan.startSubdivision
        durationSubdivisions = plan.durationSubdivisions
        midiNote = plan.midiNote
        allowedPitchClasses = plan.allowedPitchClasses
    }
}

private struct StructuralRhythmSignature: Equatable {
    let baseTempoBPM: Double
    let family: RhythmFamily
    let patternOffsetSteps: Int
    let humanizationProfile: RhythmHumanizationProfile
    let realization: RhythmRealizationState
    let voices: [StructuralRhythmVoiceSignature]
    let maximumSimultaneousAttacks: Int
    let maximumFillsPerWindow: Int
    let fillWindowBars: Int

    init(plan: RhythmPlan) {
        baseTempoBPM = plan.baseTempoBPM
        family = plan.family
        patternOffsetSteps = plan.patternOffsetSteps
        humanizationProfile = plan.humanizationProfile
        realization = plan.realization
        voices = plan.voices.map(StructuralRhythmVoiceSignature.init)
        maximumSimultaneousAttacks = plan.maximumSimultaneousAttacks
        maximumFillsPerWindow = plan.maximumFillsPerWindow
        fillWindowBars = plan.fillWindowBars
    }
}

private struct StructuralRhythmVoiceSignature: Equatable {
    let role: RhythmRole
    let drumVoice: DayObjectsDrumVoice
    let activationStart: Double
    let activationFull: Double
    let isTimingAnchor: Bool
    let isGlitchEligible: Bool

    init(plan: RhythmVoicePlan) {
        role = plan.role
        drumVoice = plan.drumVoice
        activationStart = plan.activation.startProgress
        activationFull = plan.activation.fullProgress
        isTimingAnchor = plan.isTimingAnchor
        isGlitchEligible = plan.isGlitchEligible
    }
}

private struct StructuralHarmonySignature: Equatable {
    let cycleBars: Int
    let chordCount: Int
    let roles: [StructuralHarmonyRoleSignature]

    init(plan: HarmonyPlan) {
        cycleBars = plan.cycleBars
        chordCount = plan.chordCount
        roles = plan.roles.map(StructuralHarmonyRoleSignature.init)
    }
}

private struct StructuralHarmonyRoleSignature: Equatable {
    let role: HarmonyRole
    let instrumentTarget: HarmonyInstrumentTarget
    let register: ClosedRange<UInt8>
    let activationStart: Double
    let activationFull: Double
    let chordSchedule: [HarmonyChordScheduleEntry]
    let crossfadeBars: Double

    init(plan: HarmonyRolePlan) {
        role = plan.role
        instrumentTarget = plan.instrumentTarget
        register = plan.register
        activationStart = plan.activation.startProgress
        activationFull = plan.activation.fullProgress
        chordSchedule = plan.chordSchedule
        crossfadeBars = plan.crossfadeBars
    }
}

private struct StructuralLeadSignature: Equatable {
    let instrumentID: DayObjectsInstrumentID
    let maximumSimultaneousVoices: Int
    let register: ClosedRange<UInt8>
    let pitchRegions: [LeadPitchRegion]
    let compatibleChordMIDINotes: [[UInt8]]
    let portamentoMilliseconds: Double
    let attackSeconds: Double
    let releaseSeconds: Double

    init(plan: LeadPlan) {
        instrumentID = plan.instrumentID
        maximumSimultaneousVoices = plan.maximumSimultaneousVoices
        register = plan.register
        pitchRegions = plan.pitchRegions
        compatibleChordMIDINotes = plan.compatibleChordMIDINotes
        portamentoMilliseconds = plan.portamentoMilliseconds
        attackSeconds = plan.attackSeconds
        releaseSeconds = plan.releaseSeconds
    }
}

private struct StructuralGlitchSignature: Equatable {
    let roles: [StructuralGlitchRoleSignature]
    let realization: GlitchRealizationState

    init(plan: GlitchPlan) {
        roles = plan.roles.map(StructuralGlitchRoleSignature.init)
        realization = plan.realization
    }
}

private struct StructuralGlitchRoleSignature: Equatable {
    let role: GlitchRole
    let isTimingAnchor: Bool
    let isGlitchEligible: Bool

    init(plan: GlitchRolePlan) {
        role = plan.role
        isTimingAnchor = plan.isTimingAnchor
        isGlitchEligible = plan.isGlitchEligible
    }
}
#endif
