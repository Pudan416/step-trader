#if DEBUG || INTERNAL_BUILD
import AVFAudio
import Foundation

@MainActor
protocol DayObjectsPlaybackRuntimeProtocol: AnyObject {
    var playbackMetrics: DayObjectsPlaybackMetrics { get }

    func prepare(plan: DayMusicPlan) throws
    func startAudio() throws
    func startTransport(plan: DayMusicPlan) async throws
    func fadeMaster(to plan: DayMusicPlan) throws

    func stopScheduling()
    func endLead()
    func cancelRemix()
    func releaseLayers()
    func stopTransportAndEffects() async
    func drainTail() async
    func stopAudio()

    func applyContinuous(_ plan: DayMusicPlan)
    func scheduleStructuralPlan(_ plan: DayMusicPlan)
    func addHappening(_ plan: HappeningMusicPlan, playBirth: Bool)
    func removeHappening(id: String)
    func beginLead(_ gesture: LeadGestureSample)
    func updateLead(_ gesture: LeadGestureSample)
}

/// Owns the only user-facing playback lifecycle. Layer implementations remain
/// behind the runtime boundary so every partial start and every lifecycle stop
/// converges on exactly one ordered teardown.
@MainActor
final class DayObjectsMusicPlaybackEngine: DayObjectsMusicPlaybackProtocol {
    private let audioSession: any DayObjectsAudioSessionProtocol
    private let runtime: any DayObjectsPlaybackRuntimeProtocol
    private var successfulStartCount = 0
    private var sessionMayNeedDeactivation = false
    private var runtimeMayOwnResources = false
    private var teardownTask: Task<Void, Never>?
    private var teardownID: UUID?
    private var lifecycleGeneration: UInt64 = 0

    private(set) var state: DayObjectsSoundState = .off
    private(set) var currentPlan: DayMusicPlan?

    var metrics: DayObjectsPlaybackMetrics {
        var result = runtime.playbackMetrics
        result.engineStartCount = successfulStartCount
        return result
    }

    init(
        audioSession: any DayObjectsAudioSessionProtocol,
        runtime: any DayObjectsPlaybackRuntimeProtocol
    ) {
        self.audioSession = audioSession
        self.runtime = runtime
    }

    func start(plan: DayMusicPlan) async throws {
        guard state != .on, state != .starting else { return }
        if let teardownTask { await teardownTask.value }

        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        currentPlan = plan
        state = .starting
        do {
            try audioSession.configurePlayback()
            sessionMayNeedDeactivation = true
            try audioSession.activate()
            runtimeMayOwnResources = true
            try runtime.prepare(plan: plan)
            try runtime.startAudio()
            try await runtime.startTransport(plan: plan)
            guard generation == lifecycleGeneration, state == .starting else {
                await requestTeardown(finalState: .off, force: true)
                return
            }
            try runtime.fadeMaster(to: plan)
            successfulStartCount += 1
            state = .on
        } catch {
            guard generation == lifecycleGeneration else {
                await requestTeardown(finalState: .off, force: true)
                return
            }
            let audioError = (error as? DayObjectsAudioError)
                ?? DayObjectsAudioError(String(describing: error))
            await requestTeardown(finalState: .error(audioError), force: true)
            throw audioError
        }
    }

    func stop() async {
        lifecycleGeneration &+= 1
        state = .off
        await requestTeardown(finalState: .off, force: false)
    }

    func applyContinuous(_ plan: DayMusicPlan) {
        currentPlan = plan
        guard state == .on else { return }
        runtime.applyContinuous(plan)
    }

    func scheduleStructuralPlan(_ plan: DayMusicPlan) {
        currentPlan = plan
        guard state == .on else { return }
        runtime.scheduleStructuralPlan(plan)
    }

    func addHappening(_ plan: HappeningMusicPlan, playBirth: Bool) {
        guard state == .on else { return }
        runtime.addHappening(plan, playBirth: playBirth)
    }

    func removeHappening(id: String) {
        guard state == .on else { return }
        runtime.removeHappening(id: id)
    }

    func beginLead(_ gesture: LeadGestureSample) {
        guard state == .on else { return }
        runtime.beginLead(gesture)
    }

    func updateLead(_ gesture: LeadGestureSample) {
        guard state == .on else { return }
        runtime.updateLead(gesture)
    }

    func endLead() {
        runtime.endLead()
    }

    private func requestTeardown(finalState: DayObjectsSoundState, force: Bool) async {
        if let teardownTask {
            await teardownTask.value
            return
        }
        guard force || state != .off || sessionMayNeedDeactivation || runtimeMayOwnResources else {
            return
        }

        let id = UUID()
        teardownID = id
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performTeardown(finalState: finalState)
        }
        teardownTask = task
        await task.value
        if teardownID == id {
            teardownTask = nil
            teardownID = nil
        }
    }

    private func performTeardown(finalState: DayObjectsSoundState) async {
        runtime.stopScheduling()
        runtime.endLead()
        runtime.cancelRemix()
        runtime.releaseLayers()
        await runtime.stopTransportAndEffects()
        await runtime.drainTail()
        runtime.stopAudio()
        runtimeMayOwnResources = false

        if sessionMayNeedDeactivation {
            try? audioSession.deactivate(options: .notifyOthersOnDeactivation)
            sessionMayNeedDeactivation = false
        }
        state = finalState
    }
}

/// The production runtime: one shared AudioKit bank pair, one transport, and
/// one set of preallocated players per Remix world. Transport callbacks are
/// the only clock source used by rhythm, harmony, and Happenings.
struct DayObjectsLivePlaybackAllocationSnapshot: Equatable, Sendable {
    let activeNodeCount: Int
    let poolCount: Int
    let fixedSharedNodeIdentities: [ObjectIdentifier]
    let instrumentAllocationFingerprint: [DayObjectsInstrumentBankAllocationFingerprint?]
    let allocatedTonalVoiceCounts: [Int]
    let allocatedPianoVoiceCounts: [Int]
    let allocatedDrumPlayerCounts: [Int]
}

@MainActor
final class DayObjectsLivePlaybackRuntime: DayObjectsPlaybackRuntimeProtocol, DayObjectsRemixRuntime {
    @MainActor
    private final class EffectState: DayObjectsGlitchBackend, DayObjectsMixBackend {
        var onGlitch: ((DayObjectsGlitchCommand) -> Void)?
        var onMix: ((DayObjectsMixState) -> Void)?
        private(set) var glitchByRole: [GlitchRole: DayObjectsGlitchCommand] = [:]
        private(set) var mix: DayObjectsMixState?

        func apply(_ command: DayObjectsGlitchCommand) {
            glitchByRole[command.role] = command
            onGlitch?(command)
        }

        func apply(_ state: DayObjectsMixState) {
            mix = state
            onMix?(state)
        }
    }

    @MainActor
    private final class WorldState {
        let bank: PlaybackWorldBank
        let effects: EffectState
        private var rhythmPlayer: RhythmPlayer?
        private var harmonyPlayer: HarmonyPlayer?
        private var happeningScheduler: HappeningScheduler?
        private var leadPlayer: LeadPlayer?
        private var boundDrumBankIdentity: ObjectIdentifier?
        lazy var glitch = GlitchProcessor(backend: effects)
        lazy var mix = DayObjectsMixController(backend: effects)
        var plan: DayMusicPlan?
        var currentChordIndex = 0
        var isScheduling = false
        var isReleasing = false

        var rhythm: RhythmPlayer { rhythmPlayer! }
        var harmony: HarmonyPlayer { harmonyPlayer! }
        var happenings: HappeningScheduler { happeningScheduler! }
        var lead: LeadPlayer { leadPlayer! }
        var hasPreparedRhythmBackend: Bool {
            guard let boundDrumBankIdentity else { return false }
            return boundDrumBankIdentity == ObjectIdentifier(bank.drums)
                && bank.instrumentBank.metrics.state != .unprepared
        }

        init(bank: PlaybackWorldBank) {
            self.bank = bank
            effects = EffectState()
            effects.onGlitch = { [weak self] command in self?.apply(command) }
            effects.onMix = { [weak self] state in self?.apply(state) }
        }

        func bindPreparedPlayersIfNeeded() throws {
            guard rhythmPlayer == nil else { return }
            guard bank.instrumentBank.metrics.state != .unprepared else {
                throw DayObjectsInstrumentBankError.notPrepared
            }
            let drums = bank.drums
            boundDrumBankIdentity = ObjectIdentifier(drums)
            rhythmPlayer = RhythmPlayer(drumBank: drums)
            harmonyPlayer = HarmonyPlayer(worldBank: bank)
            happeningScheduler = HappeningScheduler(worldBank: bank)
            leadPlayer = LeadPlayer(worldBank: bank)
        }

        var activeVoiceCount: Int {
            guard rhythmPlayer != nil else { return 0 }
            return harmony.metrics.activeVoiceCount
                + happenings.metrics.activeVoiceCount
                + lead.metrics.voiceCount
                + rhythm.metrics.activeLogicalHitCount
        }

        func configure(_ plan: DayMusicPlan) throws {
            try harmony.configure(plan.harmony)
            try happenings.configure(
                plans: plan.happenings,
                tonalWorld: plan.world,
                remixSeed: plan.seed
            )
            try lead.configure(
                plan: plan.lead,
                gainDecibels: plan.mix.leadTargetDecibels,
                currentChordIndex: 0
            )
            happenings.configureGlitch(plan: plan.glitch, processor: glitch)
            glitch.apply(plan.glitch)
            applyMix(plan, ducking: 0)
            self.plan = plan
            currentChordIndex = 0
            isScheduling = false
            isReleasing = false
        }

        func startScheduling() throws {
            try happenings.start()
            isScheduling = true
        }

        func render(_ event: DayObjectsTransportEvent) {
            guard let plan, isScheduling else { return }
            let chordIndex = Self.chordIndex(at: event.position.bar, in: plan.world)
            currentChordIndex = chordIndex
            let chord = plan.world.progression[chordIndex]

            let rhythmFrame = rhythm.render(
                event,
                rhythmPlan: plan.rhythm,
                glitchPlan: plan.glitch
            )
            if event.kind == .barBoundary {
                glitch.applyRealizedEvent(
                    plan: plan.glitch,
                    role: .pad,
                    cycleIndex: Int(event.position.bar),
                    stepIndex: event.position.subdivisionInBar
                )
            }
            harmony.render(subdivision: event)
            harmony.render(barBoundary: event)
            happenings.render(event, currentChord: chord)
            if event.kind == .barBoundary || event.kind == .harmonicCycleBoundary {
                lead.setCurrentChordIndex(chordIndex)
            }
            applyMix(plan, ducking: rhythmFrame.harmonyDuckingDecibels)
        }

        func renderRelease(_ event: DayObjectsTransportEvent) {
            harmony.render(subdivision: event)
        }

        func applyContinuous(_ plan: DayMusicPlan) {
            guard let structuralPlan = self.plan else { return }
            let audiblePlan = Self.mergingContinuous(from: plan, into: structuralPlan)
            harmony.applyContinuous(audiblePlan.harmony)
            lead.applyContinuous(audiblePlan.lead)
            happenings.configureGlitch(plan: audiblePlan.glitch, processor: glitch)
            glitch.apply(audiblePlan.glitch)
            applyMix(audiblePlan, ducking: 0)
            self.plan = audiblePlan
        }

        func stopAttacks() {
            isScheduling = false
            isReleasing = true
            rhythm.releaseAll()
            happenings.stop()
        }

        func finishReleaseBeforeRecycle() {
            rhythm.releaseAll()
            harmony.releaseAll()
            happenings.stop()
            isReleasing = false
        }

        func releaseAll() {
            isScheduling = false
            rhythm.releaseAll()
            harmony.releaseAll()
            happenings.stop()
            lead.end()
            isReleasing = false
        }

        private func applyMix(_ plan: DayMusicPlan, ducking: Double) {
            let delay = max(
                plan.harmony.roles.map(\.delaySend).max() ?? 0,
                plan.happenings.map(\.delaySend).max() ?? 0
            )
            let reverb = max(
                plan.harmony.roles.map(\.reverbSend).max() ?? 0,
                plan.happenings.map(\.reverbSend).max() ?? 0
            )
            mix.apply(
                plan.mix,
                activeChordVoiceCount: max(1, harmony.metrics.activeVoiceCount),
                harmonyDuckingDecibels: ducking,
                delayFeedback: delay,
                reverbFeedback: reverb,
                rampDurationSeconds: 0.25
            )
        }

        private func apply(_ command: DayObjectsGlitchCommand) {
            switch command.role {
            case .pad: harmonyPlayer?.applyGlitch(command)
            case .happening: happeningScheduler?.applyGlitch(command)
            case .lead: leadPlayer?.applyGlitch(command)
            case .percussion, .timingAnchorKick: break
            }
        }

        private func apply(_ state: DayObjectsMixState) {
            rhythmPlayer?.applyMixTargetDecibels(state.rhythmTargetDecibels)
            harmonyPlayer?.applyMixTargetDecibels(state.harmonyPerVoiceTargetDecibels)
            happeningScheduler?.applyMixTargetDecibels(state.happeningPerVoiceTargetDecibels)
            leadPlayer?.applyMixTargetDecibels(state.leadTargetDecibels)
            bank.applyProgramEffects(
                masterLinearGain: pow(10, state.masterTargetDecibelsBeforeLimiter / 20),
                delayFeedback: state.delayFeedback,
                reverbFeedback: state.reverbFeedback,
                rampDurationSeconds: state.rampDurationSeconds
            )
        }

        private static func chordIndex(at absoluteBar: Int64, in world: TonalWorldPlan) -> Int {
            guard !world.progression.isEmpty else { return 0 }
            let cycle = max(world.cycleBars, 1)
            let cycleBar = Int(absoluteBar % Int64(cycle))
            var cursor = 0
            for (index, chord) in world.progression.enumerated() {
                cursor += max(chord.durationBars, 1)
                if cycleBar < cursor { return index }
            }
            return world.progression.count - 1
        }

        private static func mergingContinuous(
            from update: DayMusicPlan,
            into structural: DayMusicPlan
        ) -> DayMusicPlan {
            let rhythmVoices = structural.rhythm.voices.map { old in
                let fresh = update.rhythm.voice(for: old.role) ?? old
                return RhythmVoicePlan(
                    role: old.role,
                    drumVoice: old.drumVoice,
                    stepProbabilities: fresh.stepProbabilities,
                    velocityRange: fresh.velocityRange,
                    microtimingMilliseconds: fresh.microtimingMilliseconds,
                    roomSend: fresh.roomSend,
                    activation: .init(
                        startProgress: old.activation.startProgress,
                        fullProgress: old.activation.fullProgress,
                        amount: fresh.activation.amount
                    ),
                    isTimingAnchor: old.isTimingAnchor,
                    isGlitchEligible: old.isGlitchEligible
                )
            }
            let rhythm = RhythmPlan(
                baseTempoBPM: structural.rhythm.baseTempoBPM,
                tempoBPM: update.rhythm.tempoBPM,
                stepsProgress: update.rhythm.stepsProgress,
                family: structural.rhythm.family,
                patternOffsetSteps: structural.rhythm.patternOffsetSteps,
                humanizationProfile: structural.rhythm.humanizationProfile,
                realization: structural.rhythm.realization,
                voices: rhythmVoices,
                maximumSimultaneousAttacks: structural.rhythm.maximumSimultaneousAttacks,
                maximumFillsPerWindow: structural.rhythm.maximumFillsPerWindow,
                fillWindowBars: structural.rhythm.fillWindowBars,
                maximumMicrotimingMilliseconds: update.rhythm.maximumMicrotimingMilliseconds,
                velocityHumanizationRange: update.rhythm.velocityHumanizationRange,
                maximumHarmonyDuckingDecibels: update.rhythm.maximumHarmonyDuckingDecibels
            )
            let harmonyRoles = structural.harmony.roles.map { old in
                let fresh = update.harmony.role(for: old.role) ?? old
                return HarmonyRolePlan(
                    role: old.role,
                    instrumentTarget: old.instrumentTarget,
                    register: old.register,
                    gain: fresh.gain,
                    attackSeconds: fresh.attackSeconds,
                    releaseSeconds: fresh.releaseSeconds,
                    delaySend: fresh.delaySend,
                    reverbSend: fresh.reverbSend,
                    activation: .init(
                        startProgress: old.activation.startProgress,
                        fullProgress: old.activation.fullProgress,
                        amount: fresh.activation.amount
                    ),
                    chordSchedule: old.chordSchedule,
                    crossfadeBars: old.crossfadeBars
                )
            }
            let harmony = HarmonyPlan(
                sleepProgress: update.harmony.sleepProgress,
                cycleBars: structural.harmony.cycleBars,
                chordCount: structural.harmony.chordCount,
                roles: harmonyRoles
            )
            let lead = LeadPlan(
                instrumentID: structural.lead.instrumentID,
                maximumSimultaneousVoices: structural.lead.maximumSimultaneousVoices,
                register: structural.lead.register,
                pitchRegions: structural.lead.pitchRegions,
                compatibleChordMIDINotes: structural.lead.compatibleChordMIDINotes,
                portamentoMilliseconds: structural.lead.portamentoMilliseconds,
                attackSeconds: structural.lead.attackSeconds,
                releaseSeconds: structural.lead.releaseSeconds,
                cutoffMultiplierRange: update.lead.cutoffMultiplierRange,
                pitchSmoothingMilliseconds: update.lead.pitchSmoothingMilliseconds,
                expressionSmoothingMilliseconds: update.lead.expressionSmoothingMilliseconds,
                maximumExpressionDepth: update.lead.maximumExpressionDepth,
                delaySend: update.lead.delaySend,
                reverbSend: update.lead.reverbSend
            )
            let glitchRoles = structural.glitch.roles.map { old in
                let fresh = update.glitch.role(for: old.role) ?? old
                return GlitchRolePlan(
                    role: old.role,
                    isTimingAnchor: old.isTimingAnchor,
                    isGlitchEligible: old.isGlitchEligible,
                    pitchDriftCents: fresh.pitchDriftCents,
                    dropoutProbability: fresh.dropoutProbability,
                    delayTimeInstability: fresh.delayTimeInstability,
                    saturationAmount: fresh.saturationAmount,
                    timingDriftMilliseconds: fresh.timingDriftMilliseconds
                )
            }
            let glitch = GlitchPlan(
                progress: update.glitch.progress,
                roles: glitchRoles,
                wowFlutterDepth: update.glitch.wowFlutterDepth,
                stereoSeparationAddition: update.glitch.stereoSeparationAddition,
                realization: structural.glitch.realization
            )
            return DayMusicPlan(
                seed: structural.seed,
                input: update.input,
                world: structural.world,
                rhythm: rhythm,
                harmony: harmony,
                happenings: structural.happenings,
                lead: lead,
                glitch: glitch,
                mix: update.mix
            )
        }
    }

    private let pair: DayObjectsPlaybackBankPair
    private let worldA: WorldState
    private let worldB: WorldState
    private var coordinator: DayObjectsRemixCoordinator!
    private var transportIsRunning = false
    private var tempoUpdateTask: Task<Void, Never>?
    private var gestureOwner: PlaybackWorldBankSlot?
    private var isPrepared = false

    var preparedRhythmBackendCount: Int {
        [worldA, worldB].filter(\.hasPreparedRhythmBackend).count
    }

    var activeWorldVoiceCountForTesting: Int { activeWorld.activeVoiceCount }
    var activeHappeningNextPositionsForTesting: [String: MusicalPosition] {
        activeWorld.happenings.metrics.nextOccurrenceByHappeningID
    }
    var activeHappeningScheduledPositionsForTesting: [String: [MusicalPosition]] {
        activeWorld.happenings.metrics.scheduledOccurrencesByHappeningID
    }
    var activeHappeningAttackHistoryForTesting: [HappeningAttackRecord] {
        activeWorld.happenings.metrics.attackHistory
    }
    var activePlanForTesting: DayMusicPlan? { activeWorld.plan }
    var activeProgramEffectMetricsForTesting: DayObjectsProgramEffectMetrics {
        activeWorld.bank.programEffectMetrics
    }
    var totalLeadAttackCountForTesting: Int {
        worldA.lead.metrics.amplitudeAttackCount + worldB.lead.metrics.amplitudeAttackCount
    }
    var totalLeadReleaseCountForTesting: Int {
        worldA.lead.metrics.releaseCount + worldB.lead.metrics.releaseCount
    }
    var inactiveLeadVoiceCountForTesting: Int {
        world(for: coordinator.metrics.inactiveBank).lead.metrics.voiceCount
    }
    var inactiveWorldRecycleCountForTesting: Int {
        world(for: coordinator.metrics.inactiveBank).bank.metrics.recycleCount
    }
    var inactiveBankActiveTonalVoiceCountForTesting: Int {
        world(for: coordinator.metrics.inactiveBank).bank.metrics.activeTonalVoiceCount
    }
    var remixResultForTesting: DayObjectsRemixResult { coordinator.result }
    var inactiveWorldVoiceCountForTesting: Int {
        world(for: coordinator.metrics.inactiveBank).activeVoiceCount
    }
    var allocationSnapshotForTesting: DayObjectsLivePlaybackAllocationSnapshot {
        let pairMetrics = pair.metrics
        let worldMetrics = [worldA.bank.metrics, worldB.bank.metrics]
        return .init(
            activeNodeCount: metrics.nodeCount,
            poolCount: metrics.poolCount,
            fixedSharedNodeIdentities: pairMetrics.fixedSharedNodeIdentities,
            instrumentAllocationFingerprint: pairMetrics.allocationFingerprint,
            allocatedTonalVoiceCounts: worldMetrics.map(\.allocatedTonalVoiceCount),
            allocatedPianoVoiceCounts: worldMetrics.map(\.allocatedPianoVoiceCount),
            allocatedDrumPlayerCounts: worldMetrics.map(\.allocatedDrumPlayerCount)
        )
    }
    var playbackPairMetricsForTesting: DayObjectsPlaybackBankPairMetrics { pair.metrics }
    var happeningRecordIDsForTesting: Set<String> {
        guard isPrepared else { return [] }
        return Set(
            worldA.happenings.metrics.activeHappeningIDs
                + worldB.happenings.metrics.activeHappeningIDs
        )
    }

    func startPreparedWorldForTesting() throws { try activeWorld.startScheduling() }
    func renderForTesting(_ event: DayObjectsTransportEvent) { coordinator.render(event) }

    private lazy var transport = DayObjectsTransport { [weak self] event in
        await self?.renderTransportEvent(event)
    }

    var playbackMetrics: DayObjectsPlaybackMetrics {
        let coordinatorMetrics = coordinator.metrics
        let activeHappeningCount = isPrepared
            ? activeWorld.happenings.metrics.activeHappeningIDs.count
            : 0
        return .init(
            activeTransportCount: transportIsRunning ? 1 : 0,
            activeTaskCount: (transportIsRunning ? 1 : 0) + (tempoUpdateTask == nil ? 0 : 1),
            activeNodeCount: metrics.nodeCount,
            activeVoiceCount: worldA.activeVoiceCount + worldB.activeVoiceCount,
            activeHappeningCount: activeHappeningCount,
            pendingRemixCount: coordinatorMetrics.pendingRemixCount,
            leadVoiceCount: isPrepared
                ? worldA.lead.metrics.voiceCount + worldB.lead.metrics.voiceCount
                : 0
        )
    }

    var metrics: DayObjectsRemixRuntimeMetrics {
        let banks = [worldA.bank.metrics, worldB.bank.metrics]
        let tonal = banks.reduce(0) { $0 + $1.allocatedTonalVoiceCount }
        let piano = banks.reduce(0) { $0 + $1.allocatedPianoVoiceCount }
        let drums = banks.reduce(0) { $0 + $1.allocatedDrumPlayerCount }
        let leadCount = isPrepared
            ? worldA.lead.metrics.voiceCount + worldB.lead.metrics.voiceCount
            : 0
        let happeningCount = isPrepared
            ? worldA.happenings.metrics.activeVoiceCount + worldB.happenings.metrics.activeVoiceCount
            : 0
        return .init(
            nodeCount: pair.metrics.fixedSharedNodeCount + tonal + piano + drums,
            poolCount: PlaybackWorldBankConfiguration.PoolName.allCases.count * 2,
            taskCount: (transportIsRunning ? 1 : 0) + (tempoUpdateTask == nil ? 0 : 1),
            transportCount: transportIsRunning ? 1 : 0,
            leadTokenCount: leadCount,
            happeningTokenCount: happeningCount
        )
    }

    init(bundle: Bundle = .main) throws {
        pair = DayObjectsInstrumentBank.makePlaybackPair(bundle: bundle)
        worldA = WorldState(bank: PlaybackWorldBank(instrumentBank: pair.bankA))
        worldB = WorldState(bank: PlaybackWorldBank(instrumentBank: pair.bankB))
        coordinator = try DayObjectsRemixCoordinator(
            bankA: worldA.bank,
            bankB: worldB.bank,
            runtime: self
        )
    }

    func prepare(plan: DayMusicPlan) throws {
        try pair.prepare(configuration: .playbackWorld)
        try coordinator.prepare(initialPlan: plan)
        worldA.bank.setOutputGain(0, rampDurationSeconds: 0)
        worldB.bank.setOutputGain(0, rampDurationSeconds: 0)
        gestureOwner = nil
        isPrepared = true
    }

    func startAudio() throws {
        guard isPrepared else { throw DayObjectsInstrumentBankError.notPrepared }
        try pair.start()
    }

    func startTransport(plan: DayMusicPlan) async throws {
        try activeWorld.startScheduling()
        transportIsRunning = true
        await transport.start(
            tempoBPM: plan.rhythm.tempoBPM,
            harmonicCycleBars: plan.world.cycleBars
        )
    }

    func fadeMaster(to plan: DayMusicPlan) throws {
        guard pair.metrics.sharedEngineIsRunning else {
            throw DayObjectsInstrumentBankError.startFailed
        }
        activeWorld.bank.setOutputGain(1, rampDurationSeconds: 0.35)
    }

    func stopScheduling() {
        worldA.isScheduling = false
        worldB.isScheduling = false
    }

    func endLead() {
        worldA.lead.end()
        worldB.lead.end()
        gestureOwner = nil
    }

    func cancelRemix() {
        coordinator.cancelPending()
    }

    func releaseLayers() {
        worldA.releaseAll()
        worldB.releaseAll()
    }

    func stopTransportAndEffects() async {
        tempoUpdateTask?.cancel()
        await tempoUpdateTask?.value
        tempoUpdateTask = nil
        await transport.stop()
        transportIsRunning = false
    }

    func drainTail() async {
        try? await Task.sleep(nanoseconds: 120_000_000)
    }

    func stopAudio() {
        pair.stop()
        worldA.bank.setOutputGain(0, rampDurationSeconds: 0)
        worldB.bank.setOutputGain(0, rampDurationSeconds: 0)
    }

    func applyContinuous(_ plan: DayMusicPlan) {
        activeWorld.applyContinuous(plan)
        tempoUpdateTask?.cancel()
        tempoUpdateTask = Task { [transport] in
            await transport.setTempoBPM(plan.rhythm.tempoBPM)
        }
    }

    func scheduleStructuralPlan(_ plan: DayMusicPlan) {
        coordinator.schedule(plan)
    }

    func addHappening(_ plan: HappeningMusicPlan, playBirth: Bool) {
        guard let chord = activeWorld.plan?.world.progression[safe: activeWorld.currentChordIndex] else { return }
        try? activeWorld.happenings.add(plan, currentChord: chord, playBirth: playBirth)
    }

    func removeHappening(id: String) {
        activeWorld.happenings.remove(id: id)
    }

    func beginLead(_ gesture: LeadGestureSample) {
        activeWorld.lead.begin(gesture)
        if activeWorld.lead.metrics.voiceCount == 1 {
            gestureOwner = coordinator.metrics.activeBank
        }
    }

    func updateLead(_ gesture: LeadGestureSample) {
        world(for: gestureOwner ?? coordinator.metrics.activeBank).lead.update(gesture)
    }

    func prepare(bank: PlaybackWorldBank) throws {
        try bank.prepare()
        try world(for: bank).bindPreparedPlayersIfNeeded()
    }

    func configure(bank: PlaybackWorldBank, plan: DayMusicPlan) throws {
        try world(for: bank).configure(plan)
    }

    func rollbackInitialConfiguration(in bank: PlaybackWorldBank) {
        world(for: bank).releaseAll()
    }

    func renderTransport(
        _ event: DayObjectsTransportEvent,
        activeBank: PlaybackWorldBank,
        releasingBank: PlaybackWorldBank?
    ) {
        world(for: activeBank).render(event)
        releasingBank.map(world(for:))?.renderRelease(event)
    }

    func stopAttackScheduling(in bank: PlaybackWorldBank, at event: DayObjectsTransportEvent) {
        world(for: bank).stopAttacks()
    }

    func beginRelease(in bank: PlaybackWorldBank, at event: DayObjectsTransportEvent) {
        world(for: bank).stopAttacks()
    }

    func startRhythm(
        in bank: PlaybackWorldBank,
        plan: DayMusicPlan,
        at event: DayObjectsTransportEvent
    ) throws {
        try world(for: bank).happenings.start(at: event.position)
        world(for: bank).isScheduling = true
    }

    func beginEqualPowerCrossfade(
        from oldBank: PlaybackWorldBank,
        to newBank: PlaybackWorldBank,
        plan: DayMusicPlan,
        startingAt event: DayObjectsTransportEvent,
        durationBars: Int
    ) {}

    func replaceHappeningsAndScheduleFirstCycle(
        from oldBank: PlaybackWorldBank,
        to newBank: PlaybackWorldBank,
        oldPlan: DayMusicPlan,
        newPlan: DayMusicPlan,
        at event: DayObjectsTransportEvent
    ) throws -> DayObjectsHappeningHandoffState {
        let oldIDs = oldPlan.happenings.map(\.happeningID)
        let newIDs = newPlan.happenings.map(\.happeningID)
        let oldSet = Set(oldIDs)
        let newSet = Set(newIDs)
        return .init(
            retainedAndReplacedIDs: newIDs.filter(oldSet.contains),
            removedAndCanceledIDs: oldIDs.filter { !newSet.contains($0) },
            addedIDs: newIDs.filter { !oldSet.contains($0) },
            firstCycleScheduledIDs: newIDs
        )
    }

    func leadCompatibility(
        from oldBank: PlaybackWorldBank,
        to newBank: PlaybackWorldBank,
        oldPlan: DayMusicPlan,
        newPlan: DayMusicPlan
    ) -> DayObjectsRemixLeadCompatibility {
        let source = world(for: oldBank)
        guard let held = source.lead.heldState else { return .notHeld }
        let oldNotes = oldPlan.lead.compatibleChordMIDINotes[safe: source.currentChordIndex] ?? []
        let destination = world(for: newBank)
        let newNotes = newPlan.lead.compatibleChordMIDINotes[safe: destination.currentChordIndex] ?? []
        let shared = Set(oldNotes).intersection(newNotes)
        guard let note = shared.min(by: {
            abs(Int($0) - Int(held.currentMIDINote)) < abs(Int($1) - Int(held.currentMIDINote))
        }) else { return .requiresRestart }
        return .safeCommonPitch(note)
    }

    func glideHeldLead(
        from oldBank: PlaybackWorldBank,
        to newBank: PlaybackWorldBank,
        midiNote: UInt8,
        newPlan: DayMusicPlan
    ) {
        let result = world(for: oldBank).lead.handoff(
            to: world(for: newBank).lead,
            safeCommonMIDINote: midiNote
        )
        gestureOwner = result.gestureOwner == .destination
            ? slot(for: newBank)
            : (result.gestureOwner == .source ? slot(for: oldBank) : nil)
    }

    func releaseAndRestartHeldLead(
        from oldBank: PlaybackWorldBank,
        to newBank: PlaybackWorldBank,
        newPlan: DayMusicPlan
    ) {
        let result = world(for: oldBank).lead.handoff(
            to: world(for: newBank).lead,
            safeCommonMIDINote: nil
        )
        gestureOwner = result.gestureOwner == .destination ? slot(for: newBank) : nil
    }

    func isDrained(_ bank: PlaybackWorldBank) -> Bool {
        let state = world(for: bank)
        guard !state.isScheduling else { return false }
        if state.isReleasing { state.finishReleaseBeforeRecycle() }
        return state.harmony.metrics.activeVoiceCount == 0
            && state.happenings.metrics.activeVoiceCount == 0
            && state.lead.metrics.voiceCount == 0
    }

    func recycle(_ bank: PlaybackWorldBank) {
        let old = world(for: bank)
        old.releaseAll()
    }

    func rollbackFailedTransition(
        newBank: PlaybackWorldBank,
        restoring oldBank: PlaybackWorldBank,
        currentPlan: DayMusicPlan,
        at event: DayObjectsTransportEvent
    ) {
        world(for: newBank).releaseAll()
        let restored = world(for: oldBank)
        if !restored.isScheduling { try? restored.startScheduling() }
    }

    func stop(_ bank: PlaybackWorldBank) {
        world(for: bank).releaseAll()
    }

    private var activeWorld: WorldState {
        world(for: coordinator.metrics.activeBank)
    }

    private func renderTransportEvent(_ event: DayObjectsTransportEvent) {
        coordinator.render(event)
    }

    private func world(for bank: PlaybackWorldBank) -> WorldState {
        bank === worldA.bank ? worldA : worldB
    }

    private func world(for slot: PlaybackWorldBankSlot) -> WorldState {
        slot == .a ? worldA : worldB
    }

    private func slot(for bank: PlaybackWorldBank) -> PlaybackWorldBankSlot {
        bank === worldA.bank ? .a : .b
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
