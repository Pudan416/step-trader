#if DEBUG || INTERNAL_BUILD
import AVFAudio
import Foundation

enum DayObjectsHappeningAuditionHarmony: String, Equatable, Sendable, CustomStringConvertible {
    case referenceC4
    case currentHarmony

    var description: String { rawValue }
}

struct DayObjectsHappeningAuditionRecord: Equatable, Sendable {
    let resolvedSound: ResolvedHappeningSound
    let effects: HappeningEffectCommand
    let priority: HappeningPlaybackPriority
}

private enum DayObjectsHappeningAuditionReference {
    static let c4World = TonalWorldPlan(
        centerPitchClass: 0,
        mode: .majorPentatonic,
        scalePitchClasses: [0, 2, 4, 7, 9],
        progression: [c4Chord],
        cycleBars: 4
    )
    static let c4Chord = ChordPlan(
        modalDegree: 0,
        rootPitchClass: 0,
        chordPitchClasses: [0, 4, 7],
        safePassingPitchClasses: [2, 9],
        voicedMIDINotes: [48, 60, 64, 67],
        durationBars: 4
    )

    static func effects(for recipe: HappeningSoundRecipe) -> HappeningEffectCommand {
        .init(
            filterCutoffHz: recipe.filterEndHz,
            delayMix: recipe.delayMix,
            delayFeedback: recipe.delayFeedback,
            reverbMix: recipe.reverbMix
        )
    }
}

@MainActor
protocol DayObjectsPlaybackRuntimeProtocol: AnyObject {
    var playbackMetrics: DayObjectsPlaybackMetrics { get }
    var diagnosticMeterSnapshot: DayObjectsDiagnosticMeterSnapshot { get }

    func prepare(plan: DayMusicPlan) throws
    func prepareForPlayback(plan: DayMusicPlan) async throws
    func startAudio() throws
    func startTransport(plan: DayMusicPlan) async throws
    func fadeMaster(to plan: DayMusicPlan) throws
    func prepareSamples(recipeIDs: Set<HappeningSoundRecipeID>) async throws
    func auditionHappening(
        _ recipeID: HappeningSoundRecipeID,
        harmony: DayObjectsHappeningAuditionHarmony
    ) throws
    func releaseAuditions()
    func rollbackFullStartToSampleOnly()

    func stopScheduling()
    func endLead()
    func cancelRemix()
    func releaseLayers()
    func stopTransportAndEffects() async
    func drainTail() async
    func stopAudio() async

    func applyContinuous(_ plan: DayMusicPlan)
    func scheduleStructuralPlan(_ plan: DayMusicPlan)
    func addHappening(_ plan: HappeningMusicPlan, playBirth: Bool)
    func removeHappening(id: String)
    func beginLead(_ gesture: LeadGestureSample)
    func updateLead(_ gesture: LeadGestureSample)
    func applyDiagnosticAudition(_ mode: DayObjectsAuditionMode, plan: DayMusicPlan)
    func releaseDiagnosticAudition(plan: DayMusicPlan)
    func auditionKickBassSidechain(preferredBassID: DayObjectsInstrumentID?) -> DayObjectsSidechainAuditionResult?
    func setHappeningAttackHandler(_ handler: ((String) -> Void)?)
}

extension DayObjectsPlaybackRuntimeProtocol {
    func prepareForPlayback(plan: DayMusicPlan) async throws { try prepare(plan: plan) }
    var diagnosticMeterSnapshot: DayObjectsDiagnosticMeterSnapshot { .silent }
    func applyDiagnosticAudition(_ mode: DayObjectsAuditionMode, plan: DayMusicPlan) {}
    func releaseDiagnosticAudition(plan: DayMusicPlan) {}
    func auditionKickBassSidechain(preferredBassID: DayObjectsInstrumentID?) -> DayObjectsSidechainAuditionResult? { nil }
    func setHappeningAttackHandler(_ handler: ((String) -> Void)?) {}
}

/// Owns the only user-facing playback lifecycle. Layer implementations remain
/// behind the runtime boundary so every partial start and every lifecycle stop
/// converges on exactly one ordered teardown.
@MainActor
final class DayObjectsMusicPlaybackEngine: DayObjectsMusicPlaybackProtocol {
    enum RuntimeState: Equatable, Sendable {
        case stopped
        case preparingSamples
        case sampleOnly
        case fullMusic
    }

    private let audioSession: any DayObjectsAudioSessionProtocol
    private let runtime: any DayObjectsPlaybackRuntimeProtocol
    private var successfulStartCount = 0
    private var sessionMayNeedDeactivation = false
    private var runtimeMayOwnResources = false
    private var teardownTask: Task<Void, Never>?
    private var teardownID: UUID?
    private var lifecycleGeneration: UInt64 = 0
    private var samplePreparationTask: Task<Void, Error>?
    private var fullStartTask: Task<Void, Error>?
    private var fullStartID: UUID?

    func setHappeningAttackHandler(_ handler: ((String) -> Void)?) {
        runtime.setHappeningAttackHandler(handler)
    }
    private var auditionWaiters: Set<UUID> = []
    private var hasAuditionVoices = false
    private var needsIdleSampleOnlyReconciliation = false

    private(set) var state: DayObjectsSoundState = .off
    private(set) var currentPlan: DayMusicPlan?
    private(set) var runtimeState: RuntimeState = .stopped
    var hasFullStartTaskForTesting: Bool { fullStartTask != nil }
    var hasSamplePreparationTaskForTesting: Bool { samplePreparationTask != nil }
    var hasTeardownTaskForTesting: Bool { teardownTask != nil }
    var auditionWaiterCountForTesting: Int { auditionWaiters.count }

    var metrics: DayObjectsPlaybackMetrics {
        var result = runtime.playbackMetrics
        result.engineStartCount = successfulStartCount
        return result
    }

    var diagnosticMeterSnapshot: DayObjectsDiagnosticMeterSnapshot {
        runtime.diagnosticMeterSnapshot
    }

    init(
        audioSession: any DayObjectsAudioSessionProtocol,
        runtime: any DayObjectsPlaybackRuntimeProtocol
    ) {
        self.audioSession = audioSession
        self.runtime = runtime
    }

    func start(plan: DayMusicPlan) async throws {
        let generation = lifecycleGeneration
        await awaitExistingTeardownBarrier()
        try checkLifecycleOperation(generation)
        guard state != .on else { return }
        if let fullStartTask {
            do {
                try await fullStartTask.value
                try checkLifecycleOperation(generation)
            } catch {
                guard generation == lifecycleGeneration else {
                    throw CancellationError()
                }
                try Task.checkCancellation()
                throw error
            }
            return
        }
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            try await self.performFullStart(plan: plan, generation: generation)
        }
        fullStartID = id
        fullStartTask = task
        do {
            try await task.value
            try checkLifecycleOperation(generation)
            await finishFullStart(id: id)
        } catch {
            let wasInvalidated = generation != lifecycleGeneration
            await finishFullStart(id: id)
            if wasInvalidated { throw CancellationError() }
            try Task.checkCancellation()
            throw error
        }
    }

    private func performFullStart(plan: DayMusicPlan, generation: UInt64) async throws {
        try checkLifecycleOperation(generation)

        if let samplePreparationTask {
            do {
                try await samplePreparationTask.value
                try checkLifecycleOperation(generation)
                if runtimeState == .preparingSamples { runtimeState = .sampleOnly }
                self.samplePreparationTask = nil
            } catch {
                guard generation == lifecycleGeneration else {
                    throw CancellationError()
                }
                try Task.checkCancellation()
                self.samplePreparationTask = nil
                if runtimeState == .preparingSamples {
                    await performTeardown(finalState: .off, operationGeneration: generation)
                    try checkLifecycleOperation(generation)
                }
            }
        }

        try checkLifecycleOperation(generation)
        let upgradingSampleOnly = runtimeState == .sampleOnly
        currentPlan = plan
        state = .starting
        do {
            if !upgradingSampleOnly {
                try audioSession.configurePlayback()
                sessionMayNeedDeactivation = true
                try audioSession.activate()
            }
            runtimeMayOwnResources = true
            try await runtime.prepareForPlayback(plan: plan)
            try checkLifecycleOperation(generation)
            if hasAuditionVoices {
                // The bank's successful full-preparation commit owns clearing
                // sample-only voices. A failed prepare leaves this truth intact.
                hasAuditionVoices = false
            }
            try runtime.startAudio()
            try await runtime.startTransport(plan: plan)
            try checkLifecycleOperation(generation)
            guard state == .starting else { throw CancellationError() }
            try runtime.fadeMaster(to: plan)
            successfulStartCount += 1
            runtimeState = .fullMusic
            state = .on
        } catch {
            guard generation == lifecycleGeneration else {
                throw CancellationError()
            }
            try Task.checkCancellation()
            let audioError = DayObjectsAudioError.classifying(error)
            if upgradingSampleOnly {
                runtime.stopScheduling()
                runtime.endLead()
                runtime.cancelRemix()
                runtime.releaseLayers()
                await runtime.stopTransportAndEffects()
                try checkLifecycleOperation(generation)
                runtime.rollbackFullStartToSampleOnly()
                runtimeState = .sampleOnly
                state = .error(audioError)
                throw audioError
            }
            await performTeardown(
                finalState: .error(audioError),
                operationGeneration: generation
            )
            try checkLifecycleOperation(generation)
            throw audioError
        }
    }

    func auditionHappening(_ recipeID: HappeningSoundRecipeID) async throws {
        let waiterID = UUID()
        let generation = lifecycleGeneration
        auditionWaiters.insert(waiterID)
        needsIdleSampleOnlyReconciliation = false
        do {
            try await withTaskCancellationHandler {
                await awaitExistingTeardownBarrier()
                try checkAuditionIntent(waiterID, generation: generation)
                guard HappeningSoundCatalog.recipe(for: recipeID) != nil else {
                    throw HappeningSamplePoolError.recipeUnavailable(recipeID)
                }
                try await awaitFullStartIfNeeded(
                    waiterID: waiterID,
                    generation: generation
                )
                try checkAuditionIntent(waiterID, generation: generation)
                if runtimeState == .fullMusic {
                    try runtime.auditionHappening(recipeID, harmony: .currentHarmony)
                    hasAuditionVoices = true
                    return
                }
                if runtimeState == .sampleOnly {
                    try runtime.auditionHappening(recipeID, harmony: .referenceC4)
                    hasAuditionVoices = true
                    return
                }

                let task = try samplePreparationTask ?? beginSamplePreparation()
                try await task.value
                try checkAuditionIntent(waiterID, generation: generation)
                if runtimeState == .preparingSamples { runtimeState = .sampleOnly }
                samplePreparationTask = nil
                try await awaitFullStartIfNeeded(
                    waiterID: waiterID,
                    generation: generation
                )
                try checkAuditionIntent(waiterID, generation: generation)
                let harmony: DayObjectsHappeningAuditionHarmony = runtimeState == .fullMusic
                    ? .currentHarmony
                    : .referenceC4
                try runtime.auditionHappening(recipeID, harmony: harmony)
                hasAuditionVoices = true
            } onCancel: {
                Task { @MainActor [weak self] in
                    await self?.finishAuditionWaiter(waiterID, generation: generation)
                }
            }
            await finishAuditionWaiter(waiterID, generation: generation)
        } catch {
            let wasInvalidated = generation != lifecycleGeneration
            let sampleStartFailed = runtimeState == .preparingSamples
                || samplePreparationTask != nil
            let audioError = DayObjectsAudioError.classifying(error)
            await finishAuditionWaiter(waiterID, generation: generation)
            if wasInvalidated { throw CancellationError() }
            try Task.checkCancellation()
            if sampleStartFailed {
                state = .error(audioError)
                throw audioError
            }
            throw error
        }
    }

    func stop() async {
        if let priorBarrier = teardownTask, fullStartTask == nil, samplePreparationTask == nil {
            lifecycleGeneration &+= 1
            state = .off
            auditionWaiters.removeAll()
            needsIdleSampleOnlyReconciliation = false
            let id = UUID()
            teardownID = id
            let task = Task { @MainActor [weak self] in
                await priorBarrier.value
                self?.state = .off
            }
            teardownTask = task
            await task.value
            if teardownID == id {
                teardownTask = nil
                teardownID = nil
            }
            return
        }
        let needsTeardown = state != .off || sessionMayNeedDeactivation || runtimeMayOwnResources
        lifecycleGeneration &+= 1
        state = .off
        auditionWaiters.removeAll()
        needsIdleSampleOnlyReconciliation = false
        let staleSamplePreparation = samplePreparationTask
        samplePreparationTask = nil
        let staleFullStart = fullStartTask
        fullStartTask = nil
        fullStartID = nil
        staleSamplePreparation?.cancel()
        staleFullStart?.cancel()
        guard needsTeardown || staleSamplePreparation != nil || staleFullStart != nil else { return }

        let priorBarrier = teardownTask
        let id = UUID()
        teardownID = id
        let task = Task { @MainActor [weak self] in
            if let priorBarrier { await priorBarrier.value }
            _ = try? await staleSamplePreparation?.value
            _ = try? await staleFullStart?.value
            guard let self else { return }
            await self.performTeardown(finalState: .off)
        }
        teardownTask = task
        await task.value
        if teardownID == id {
            teardownTask = nil
            teardownID = nil
        }
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

    func applyDiagnosticAudition(_ mode: DayObjectsAuditionMode, plan: DayMusicPlan) {
        guard state == .on else { return }
        runtime.applyDiagnosticAudition(mode, plan: plan)
    }

    func releaseDiagnosticAudition() {
        guard state == .on else { return }
        guard let currentPlan else { return }
        runtime.releaseDiagnosticAudition(plan: currentPlan)
    }

    func auditionKickBassSidechain(preferredBassID: DayObjectsInstrumentID?) -> DayObjectsSidechainAuditionResult? {
        guard state == .on else { return nil }
        return runtime.auditionKickBassSidechain(preferredBassID: preferredBassID)
    }

    private func requestTeardown(finalState: DayObjectsSoundState, force: Bool) async {
        if teardownTask != nil {
            await awaitExistingTeardownBarrier()
            return
        }
        guard force || state != .off || sessionMayNeedDeactivation || runtimeMayOwnResources else {
            return
        }

        let id = UUID()
        teardownID = id
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performTeardown(finalState: finalState, operationGeneration: nil)
        }
        teardownTask = task
        await task.value
        if teardownID == id {
            teardownTask = nil
            teardownID = nil
        }
    }

    private func awaitExistingTeardownBarrier() async {
        guard let task = teardownTask, let id = teardownID else {
            assert(teardownTask == nil && teardownID == nil)
            return
        }
        await task.value
        if teardownID == id {
            teardownTask = nil
            teardownID = nil
        }
    }

    private func checkLifecycleOperation(_ generation: UInt64) throws {
        guard generation == lifecycleGeneration else { throw CancellationError() }
        try Task.checkCancellation()
    }

    private func checkAuditionIntent(_ waiterID: UUID, generation: UInt64) throws {
        guard generation == lifecycleGeneration, auditionWaiters.contains(waiterID) else {
            throw CancellationError()
        }
        try Task.checkCancellation()
    }

    private func performTeardown(
        finalState: DayObjectsSoundState,
        operationGeneration: UInt64? = nil
    ) async {
        runtime.stopScheduling()
        runtime.endLead()
        runtime.cancelRemix()
        if hasAuditionVoices {
            runtime.releaseAuditions()
            hasAuditionVoices = false
        }
        runtime.releaseLayers()
        await runtime.stopTransportAndEffects()
        await runtime.drainTail()
        await runtime.stopAudio()
        runtimeMayOwnResources = false
        runtimeState = .stopped

        if sessionMayNeedDeactivation {
            try? audioSession.deactivate(options: .notifyOthersOnDeactivation)
            sessionMayNeedDeactivation = false
        }
        if operationGeneration == nil || operationGeneration == lifecycleGeneration {
            state = finalState
        }
    }

    private func beginSamplePreparation() throws -> Task<Void, Error> {
        guard runtimeState == .stopped else {
            throw DayObjectsAudioError("Invalid sample preparation state")
        }
        runtimeState = .preparingSamples
        do {
            try audioSession.configurePlayback()
            sessionMayNeedDeactivation = true
            try audioSession.activate()
            runtimeMayOwnResources = true
        } catch {
            runtimeState = .stopped
            throw error
        }
        let recipeIDs = Set(HappeningSoundCatalog.recipes.map(\.id))
        let task = Task { @MainActor [runtime] in
            try await runtime.prepareSamples(recipeIDs: recipeIDs)
            try Task.checkCancellation()
            try runtime.startAudio()
        }
        samplePreparationTask = task
        return task
    }

    private func finishAuditionWaiter(_ waiterID: UUID, generation: UInt64) async {
        guard generation == lifecycleGeneration else { return }
        auditionWaiters.remove(waiterID)
        await reconcileIdleSampleOnly(requestedByWaiterCompletion: true)
    }

    private func reconcileIdleSampleOnly(requestedByWaiterCompletion: Bool) async {
        guard auditionWaiters.isEmpty, !hasAuditionVoices else {
            needsIdleSampleOnlyReconciliation = false
            return
        }
        if fullStartTask != nil {
            if requestedByWaiterCompletion {
                needsIdleSampleOnlyReconciliation = true
            }
            return
        }
        guard requestedByWaiterCompletion || needsIdleSampleOnlyReconciliation else { return }
        needsIdleSampleOnlyReconciliation = false
        guard runtimeState == .preparingSamples
                || runtimeState == .sampleOnly else { return }
        samplePreparationTask?.cancel()
        samplePreparationTask = nil
        await requestTeardown(finalState: .off, force: true)
    }

    private func finishFullStart(id: UUID) async {
        guard fullStartID == id else { return }
        fullStartTask = nil
        fullStartID = nil
        await reconcileIdleSampleOnly(requestedByWaiterCompletion: false)
    }

    private func awaitFullStartIfNeeded(waiterID: UUID, generation: UInt64) async throws {
        guard let task = fullStartTask else { return }
        do {
            try await task.value
        } catch {
            try checkAuditionIntent(waiterID, generation: generation)
            guard runtimeState == .sampleOnly else { throw error }
        }
        try checkAuditionIntent(waiterID, generation: generation)
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

private enum DayObjectsDiagnosticScheduling {
    // At 48 kHz this is 3,840 frames: below Audio Unit's 4,096-frame
    // immediate-offset bound, but long enough to submit Bass, Rhythm, and
    // duck automation synchronously while remaining tap-like.
    static let leadTimeSeconds: TimeInterval = 0.08

    static func deadline(using clock: () -> TimeInterval) -> TimeInterval? {
        let now = clock()
        guard now.isFinite, now >= 0 else { return nil }
        let deadline = now + leadTimeSeconds
        return deadline.isFinite ? deadline : nil
    }
}

@MainActor
final class DayObjectsLivePlaybackRuntime: DayObjectsPlaybackRuntimeProtocol, DayObjectsRemixRuntime {
    private enum AudioOwnershipMode {
        case sampleOnly
        case fullPair
    }

    @MainActor
    final class EffectState: DayObjectsGlitchBackend, DayObjectsMixBackend {
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
    final class WorldState {
        let bank: PlaybackWorldBank
        let effects: EffectState
        private var rhythmPlayer: RhythmPlayer?
        private var bassPlayer: BassPlayer?
        private var harmonyPlayer: HarmonyPlayer?
        private var happeningScheduler: HappeningScheduler?
        private var leadPlayer: LeadPlayer?
        private var happeningAttackHandler: ((String) -> Void)?
        private var boundDrumBankIdentity: ObjectIdentifier?
        private let bassDucker = BassDucker()
        lazy var glitch = GlitchProcessor(backend: effects)
        lazy var mix = DayObjectsMixController(backend: effects)
        var plan: DayMusicPlan?
        var currentChordIndex = 0
        var isScheduling = false
        var isReleasing = false
        private(set) var diagnosticAuditionMode: DayObjectsAuditionMode = .fullComposition

        var rhythm: RhythmPlayer? { rhythmPlayer }
        var bass: BassPlayer? { bassPlayer }
        var harmony: HarmonyPlayer? { harmonyPlayer }
        var happenings: HappeningScheduler? { happeningScheduler }
        var lead: LeadPlayer? { leadPlayer }
        var hasPreparedRhythmBackend: Bool {
            guard let boundDrumBankIdentity else { return false }
            return boundDrumBankIdentity == ObjectIdentifier(bank.drums)
                && bank.instrumentBank.metrics.state != .unprepared
        }
        var hasBoundPlayers: Bool {
            rhythmPlayer != nil
                && bassPlayer != nil
                && harmonyPlayer != nil
                && happeningScheduler != nil
                && leadPlayer != nil
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
            bassPlayer = BassPlayer(worldBank: bank, duckBackend: bank)
            harmonyPlayer = HarmonyPlayer(worldBank: bank)
            let scheduler = HappeningScheduler(worldBank: bank)
            scheduler.onAttack = { [weak self] attack in
                self?.happeningAttackHandler?(attack.happeningID)
            }
            happeningScheduler = scheduler
            leadPlayer = LeadPlayer(worldBank: bank)
        }

        func setHappeningAttackHandler(_ handler: ((String) -> Void)?) {
            happeningAttackHandler = handler
        }

        var activeVoiceCount: Int {
            let harmonyCount = harmonyPlayer?.metrics.activeVoiceCount ?? 0
            let bassCount = bassPlayer?.metrics.activeVoiceCount ?? 0
            let happeningCount = happeningScheduler?.metrics.activeVoiceCount ?? 0
            let leadCount = leadPlayer?.metrics.voiceCount ?? 0
            let rhythmCount = rhythmPlayer?.metrics.activeLogicalHitCount ?? 0
            return harmonyCount + bassCount + happeningCount + leadCount + rhythmCount
        }

        func configure(
            _ plan: DayMusicPlan,
            diagnosticAuditionMode: DayObjectsAuditionMode = .fullComposition,
            usesSampledPiano: Bool = true
        ) throws {
            guard let bass = bassPlayer,
                  let harmony = harmonyPlayer,
                  let happenings = happeningScheduler,
                  let lead = leadPlayer else {
                throw DayObjectsInstrumentBankError.notPrepared
            }
            self.diagnosticAuditionMode = diagnosticAuditionMode
            bassDucker.reset()
            bank.resetBassDuckGain()
            try bass.configure(
                plan.bass,
                cycleLengthSubdivisions: Int64(max(plan.world.cycleBars, 1)) * MusicalPosition.subdivisionsPerBar
            )
            try harmony.configure(
                usesSampledPiano ? plan.harmony : plan.harmony.replacingFeltPianoWithTonalKeys()
            )
            try happenings.configure(
                plans: plan.happenings,
                tonalWorld: plan.world,
                remixSeed: plan.seed
            )
            happenings.applyReverbSendScale(plan.mix.worldGroupCalibration?.reverbSendScale ?? 1)
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

        func startScheduling(at position: MusicalPosition? = nil) throws {
            guard let happenings = happeningScheduler,
                  let bass = bassPlayer else {
                throw DayObjectsInstrumentBankError.notPrepared
            }
            if let position {
                try happenings.start(at: position)
            } else {
                try happenings.start(playInitialBirths: true)
            }
            bass.startScheduling(at: position)
            isScheduling = true
        }

        func render(_ event: DayObjectsTransportEvent) {
            guard let plan,
                  isScheduling,
                  let rhythm = rhythmPlayer,
                  let bass = bassPlayer,
                  let harmony = harmonyPlayer,
                  let happenings = happeningScheduler,
                  let lead = leadPlayer else { return }
            let chordIndex = Self.chordIndex(at: event.position.bar, in: plan.world)
            currentChordIndex = chordIndex
            let chord = plan.world.progression[chordIndex]

            let rhythmFrame = rhythm.render(
                event,
                rhythmPlan: plan.rhythm,
                glitchPlan: plan.glitch
            )
            var bassDuckCommand: BassDuckCommand?
            if let bassPlan = plan.bass {
                for hit in rhythmFrame.hits where hit.isTimingAnchor {
                    bassDuckCommand = bassDucker.command(
                        kickVelocity: hit.velocity,
                        hostTime: hit.scheduledHostTimeSeconds,
                        plan: bassPlan.ducking
                    )
                    if bassDuckCommand != nil { break }
                }
            }
            _ = bass.render(event, plan: plan.bass, duckCommand: bassDuckCommand)
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
            harmonyPlayer?.render(subdivision: event)
        }

        func applyContinuous(_ plan: DayMusicPlan) {
            guard let structuralPlan = self.plan,
                  let bass = bassPlayer,
                  let harmony = harmonyPlayer,
                  let lead = leadPlayer,
                  let happenings = happeningScheduler else { return }
            let audiblePlan = Self.mergingContinuous(from: plan, into: structuralPlan)
            bass.applyContinuous(audiblePlan.bass)
            harmony.applyContinuous(audiblePlan.harmony)
            lead.applyContinuous(audiblePlan.lead)
            happenings.configureGlitch(plan: audiblePlan.glitch, processor: glitch)
            happenings.applyReverbSendScale(audiblePlan.mix.worldGroupCalibration?.reverbSendScale ?? 1)
            glitch.apply(audiblePlan.glitch)
            applyMix(audiblePlan, ducking: 0)
            self.plan = audiblePlan
        }

        func applyDiagnosticAudition(_ mode: DayObjectsAuditionMode, plan: DayMusicPlan) {
            guard mode != .kickBassSidechain else { return }
            diagnosticAuditionMode = mode
            // The controller may already describe a pending Remix. Isolation
            // changes the mix of the world that is currently sounding.
            applyMix(self.plan ?? plan, ducking: 0)
        }

        func resetDiagnosticAudition() {
            diagnosticAuditionMode = .fullComposition
            bassPlayer?.releaseDiagnosticAudition(restoring: plan?.bass)
        }

        func auditionKickBassSidechain(
            preferredBassID: DayObjectsInstrumentID?,
            hostTime: TimeInterval,
            automaticallyReleaseAfterWallClock: Bool = true,
            forceFreshDuckingCommand: Bool = false
        ) -> DayObjectsSidechainAuditionResult? {
            guard let plan, let bass = bassPlayer, hostTime.isFinite else { return nil }
            if forceFreshDuckingCommand { bassDucker.reset() }
            let descriptor = diagnosticBassDescriptor(preferredBassID)
            let ducking = plan.bass?.ducking ?? .init(
                maximumAttenuationDecibels: 5,
                attackSeconds: 0.005,
                holdSeconds: 0.045,
                releaseSeconds: 0.180
            )
            guard let command = bassDucker.command(
                kickVelocity: 1,
                hostTime: hostTime,
                plan: ducking
            ) else { return nil }
            do {
                guard try bass.audition(
                    instrumentID: descriptor.id,
                    midiNote: descriptor.referenceMIDI,
                    velocity: 0.78,
                    hostTime: hostTime,
                    restorationPlan: plan.bass,
                    automaticallyReleaseAfterWallClock: automaticallyReleaseAfterWallClock
                ) else { return nil }
                let kick = DayObjectsScheduledDrumHit(
                    voice: .kickSoft,
                    velocity: 1,
                    scheduledHostTimeSeconds: hostTime,
                    microtimingMilliseconds: 0,
                    roomSend: 0,
                    stereoOffset: 0,
                    pitchDriftCents: 0
                )
                bank.drums.schedule(kick)
                bank.apply(command)
                return .init(
                    instrumentID: descriptor.id,
                    duckCommand: command,
                    scheduledKick: kick
                )
            } catch {
                return nil
            }
        }

        func stopAttacks() {
            isScheduling = false
            isReleasing = true
            bank.resetBassDuckGain()
            rhythmPlayer?.releaseAll()
            bassPlayer?.stopAttacks()
            happeningScheduler?.stop()
        }

        func finishReleaseBeforeRecycle() {
            bank.resetBassDuckGain()
            rhythmPlayer?.releaseAll()
            bassPlayer?.releaseAll()
            harmonyPlayer?.releaseAll()
            happeningScheduler?.stop()
            isReleasing = false
        }

        func releaseAll() {
            isScheduling = false
            bank.resetBassDuckGain()
            rhythmPlayer?.releaseAll()
            bassPlayer?.releaseAll()
            harmonyPlayer?.releaseAll()
            happeningScheduler?.stop()
            leadPlayer?.end()
            isReleasing = false
        }

        func endLeadIfBound() { leadPlayer?.end() }

        private func applyMix(_ plan: DayMusicPlan, ducking: Double) {
            applyMix(effectiveMix(for: plan.mix), using: plan, ducking: ducking)
        }

        private func effectiveMix(for mix: LayerMixPlan) -> LayerMixPlan {
            switch diagnosticAuditionMode {
            case .fullComposition, .kickBassSidechain: mix
            case let .isolatedBus(role): Self.isolatedMix(role: role, from: mix)
            }
        }

        private func diagnosticBassDescriptor(
            _ preferredBassID: DayObjectsInstrumentID?
        ) -> DayObjectsInstrumentDescriptor {
            if let preferredBassID,
               let descriptor = bank.instrumentBank.descriptors.first(where: {
                   $0.id == preferredBassID && $0.category == .bass
               }) {
                return descriptor
            }
            return bank.instrumentBank.descriptors.first {
                $0.id.rawValue == "bass.analog-boom"
            }!
        }

        private func applyMix(
            _ mixPlan: LayerMixPlan,
            using plan: DayMusicPlan,
            ducking: Double
        ) {
            let harmonySend = plan.harmony.roles.map(\.reverbSend).max() ?? 0
            let happeningSend = plan.happenings.map(\.reverbSend).max() ?? 0
            let reverbScale = plan.mix.worldGroupCalibration?.reverbSendScale ?? 1
            let calibration = DayObjectsPlanAwareGainCalibration.make(
                grooveMode: plan.groove.mode,
                stepsActivityDensity: plan.rhythm.stepsProgress
            )
            mix.apply(
                mixPlan,
                activeChordVoiceCount: max(1, harmonyPlayer?.metrics.activeVoiceCount ?? 0),
                harmonyDuckingDecibels: ducking,
                spatial: .init(
                    rhythm: .init(sendLevel: 0.08 * reverbScale, decay: 0.42),
                    bass: .init(sendLevel: plan.bass?.reverbSend ?? 0, decay: 0.36),
                    harmony: .init(sendLevel: harmonySend, decay: 0.72),
                    happenings: .init(sendLevel: happeningSend * reverbScale, decay: 0.84),
                    lead: .init(
                        sendLevel: plan.lead.reverbSend,
                        decay: 0.62,
                        secondarySendLevel: plan.lead.delaySend,
                        secondaryDecay: 0.32
                    )
                ),
                calibration: calibration,
                rampDurationSeconds: 0.25
            )
        }

        private static func isolatedMix(
            role: DayObjectsRoleBus,
            from mix: LayerMixPlan
        ) -> LayerMixPlan {
            let muted = -60.0
            return .init(
                rhythmTargetDecibels: role == .rhythm ? mix.rhythmTargetDecibels : muted,
                bassTargetDecibels: role == .bass ? mix.bassTargetDecibels : muted,
                harmonyTargetDecibels: role == .harmony ? mix.harmonyTargetDecibels : muted,
                happeningAggregateTargetDecibels: role == .happenings ? mix.happeningAggregateTargetDecibels : muted,
                happeningPerVoiceTargetDecibels: role == .happenings ? mix.happeningPerVoiceTargetDecibels : muted,
                happeningCount: mix.happeningCount,
                leadTargetDecibels: role == .lead ? mix.leadTargetDecibels : muted,
                masterTargetDecibelsBeforeLimiter: mix.masterTargetDecibelsBeforeLimiter,
                maximumHarmonyDuckingDecibels: 0,
                worldGroupCalibration: mix.worldGroupCalibration
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
            rhythmPlayer?.applyMixTargetDecibels(0)
            bassPlayer?.applyMixTargetDecibels(0)
            harmonyPlayer?.applyMixTargetDecibels(
                state.harmonyPerVoiceTargetDecibels - state.harmonyTargetDecibels
            )
            happeningScheduler?.applyMixTargetDecibels(
                state.happeningPerVoiceTargetDecibels - state.happeningAggregateTargetDecibels
            )
            leadPlayer?.applyBusOwnedMixTargetDecibels(state.leadVoiceTargetDecibels)
            bank.applyMix(state)
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
            // Group gain and wet recipes belong to the instruments that are
            // sounding. A pending world/mood must bring its entire calibration
            // at the structural boundary, including its calibrated base mix.
            let sameGroup = update.soundWorld == structural.soundWorld && update.mood == structural.mood
            let rhythmVoices = structural.rhythm.voices.map { old in
                let fresh = update.rhythm.voice(for: old.role) ?? old
                return RhythmVoicePlan(
                    role: old.role,
                    drumVoice: old.drumVoice,
                    stepProbabilities: fresh.stepProbabilities,
                    velocityRange: fresh.velocityRange,
                    microtimingMilliseconds: fresh.microtimingMilliseconds,
                    roomSend: sameGroup ? fresh.roomSend : old.roomSend,
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
                kitID: structural.rhythm.kitID,
                baseTempoBPM: structural.rhythm.baseTempoBPM,
                tempoBPM: update.rhythm.tempoBPM,
                stepsProgress: update.rhythm.stepsProgress,
                family: structural.rhythm.family,
                patternOffsetSteps: structural.rhythm.patternOffsetSteps,
                humanizationProfile: structural.rhythm.humanizationProfile,
                groove: structural.rhythm.groove,
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
                    delaySend: sameGroup ? fresh.delaySend : old.delaySend,
                    reverbSend: sameGroup ? fresh.reverbSend : old.reverbSend,
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
                delaySend: sameGroup ? update.lead.delaySend : structural.lead.delaySend,
                reverbSend: sameGroup ? update.lead.reverbSend : structural.lead.reverbSend
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
            let bass = mergedBass(from: update.bass, into: structural.bass, preserveWetSend: !sameGroup)
            return DayMusicPlan(
                seed: structural.seed,
                soundWorld: structural.soundWorld,
                mood: structural.mood,
                guestWorld: structural.guestWorld,
                guestInstrumentIDs: structural.guestInstrumentIDs,
                input: update.input,
                world: structural.world,
                rhythm: rhythm,
                groove: structural.groove,
                bass: bass,
                harmony: harmony,
                happenings: structural.happenings,
                lead: lead,
                glitch: glitch,
                mix: sameGroup ? update.mix : structural.mix
            )
        }

        private static func mergedBass(
            from update: BassPlan?,
            into structural: BassPlan?,
            preserveWetSend: Bool
        ) -> BassPlan? {
            guard let structural, let update else { return structural }
            guard hasSameBassStructure(structural, update) else { return structural }
            let events = structural.events.map { old in
                guard let fresh = update.events.first(where: { $0.stableID == old.stableID }) else {
                    return old
                }
                return BassEventPlan(
                    stableID: old.stableID,
                    chordIndex: old.chordIndex,
                    startSubdivision: old.startSubdivision,
                    durationSubdivisions: old.durationSubdivisions,
                    midiNote: old.midiNote,
                    velocity: fresh.velocity,
                    activationThreshold: fresh.activationThreshold,
                    allowedPitchClasses: old.allowedPitchClasses
                )
            }
            return BassPlan(
                mode: structural.mode,
                instrumentID: structural.instrumentID,
                register: structural.register,
                articulation: structural.articulation,
                stepsProgress: update.stepsProgress,
                cutoffMultiplier: update.cutoffMultiplier,
                glideMilliseconds: update.glideMilliseconds,
                reverbSend: preserveWetSend ? structural.reverbSend : update.reverbSend,
                ducking: BassDuckingPlan(
                    maximumAttenuationDecibels: update.ducking.maximumAttenuationDecibels,
                    attackSeconds: structural.ducking.attackSeconds,
                    holdSeconds: structural.ducking.holdSeconds,
                    releaseSeconds: structural.ducking.releaseSeconds
                ),
                events: events
            )
        }

        private static func hasSameBassStructure(
            _ lhs: BassPlan,
            _ rhs: BassPlan
        ) -> Bool {
            lhs.mode == rhs.mode
                && lhs.instrumentID == rhs.instrumentID
                && lhs.register == rhs.register
                && lhs.articulation == rhs.articulation
                && lhs.ducking.attackSeconds == rhs.ducking.attackSeconds
                && lhs.ducking.holdSeconds == rhs.ducking.holdSeconds
                && lhs.ducking.releaseSeconds == rhs.ducking.releaseSeconds
                && lhs.events.map(BassStructuralEventIdentity.init)
                    == rhs.events.map(BassStructuralEventIdentity.init)
        }

        private struct BassStructuralEventIdentity: Equatable {
            let stableID: UInt64
            let chordIndex: Int
            let startSubdivision: Int64
            let durationSubdivisions: Int64
            let midiNote: UInt8
            let allowedPitchClasses: Set<Int>

            init(event: BassEventPlan) {
                stableID = event.stableID
                chordIndex = event.chordIndex
                startSubdivision = event.startSubdivision
                durationSubdivisions = event.durationSubdivisions
                midiNote = event.midiNote
                allowedPitchClasses = event.allowedPitchClasses
            }
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
    private var desiredAudioOwnershipMode: AudioOwnershipMode?
    private var currentAudioOwnershipMode: AudioOwnershipMode?
    private var auditionHandles: [HappeningPlaybackHandle] = []
    private var auditionReleaseTasks: [HappeningPlaybackHandle: Task<Void, Never>] = [:]
    private(set) var auditionRecordsForTesting: [DayObjectsHappeningAuditionRecord] = []
    private let diagnosticHostTimeProvider: () -> TimeInterval
    private var diagnosticAuditionMode: DayObjectsAuditionMode = .fullComposition

    var auditionHandleCountForTesting: Int { auditionHandles.count }
    var auditionReleaseTaskCountForTesting: Int { auditionReleaseTasks.count }
    var audioEngineIsRunningForTesting: Bool { pair.metrics.sharedEngineIsRunning }

    var preparedRhythmBackendCount: Int {
        [worldA, worldB].filter(\.hasPreparedRhythmBackend).count
    }

    var activeWorldVoiceCountForTesting: Int { activeWorld.activeVoiceCount }
    var activeBassDuckGainMetricsForTesting: BassDuckGainMetrics {
        activeWorld.bank.bassDuckGainMetrics
    }
    var activeHarmonyDuckingForTesting: Double { activeWorld.effects.mix?.harmonyDuckingDecibels ?? 0 }
    var activeHappeningNextPositionsForTesting: [String: MusicalPosition] {
        activeWorld.happenings?.metrics.nextOccurrenceByHappeningID ?? [:]
    }
    var activeHappeningScheduledPositionsForTesting: [String: [MusicalPosition]] {
        activeWorld.happenings?.metrics.scheduledOccurrencesByHappeningID ?? [:]
    }
    var activeHappeningAttackHistoryForTesting: [HappeningAttackRecord] {
        activeWorld.happenings?.metrics.attackHistory ?? []
    }
    var activePlanForTesting: DayMusicPlan? { activeWorld.plan }
    var activeProgramEffectMetricsForTesting: DayObjectsProgramEffectMetrics {
        activeWorld.bank.programEffectMetrics
    }
    var activeDiagnosticAuditionModeForTesting: DayObjectsAuditionMode {
        activeWorld.diagnosticAuditionMode
    }
    var totalLeadAttackCountForTesting: Int {
        (worldA.lead?.metrics.amplitudeAttackCount ?? 0)
            + (worldB.lead?.metrics.amplitudeAttackCount ?? 0)
    }
    var totalLeadReleaseCountForTesting: Int {
        (worldA.lead?.metrics.releaseCount ?? 0)
            + (worldB.lead?.metrics.releaseCount ?? 0)
    }
    var totalBassAttackCountForTesting: Int {
        (worldA.bass?.metrics.attackCount ?? 0)
            + (worldB.bass?.metrics.attackCount ?? 0)
    }
    var totalBassReleaseCountForTesting: Int {
        (worldA.bass?.metrics.releaseCount ?? 0)
            + (worldB.bass?.metrics.releaseCount ?? 0)
    }
    var activeBassVoiceCountForTesting: Int { activeWorld.bass?.metrics.activeVoiceCount ?? 0 }
    var activeBassSchedulingOriginForTesting: Int64? {
        activeWorld.bass?.metrics.schedulingOriginSubdivision
    }
    var inactiveBassVoiceCountForTesting: Int {
        world(for: coordinator.metrics.inactiveBank).bass?.metrics.activeVoiceCount ?? 0
    }
    var inactiveLeadVoiceCountForTesting: Int {
        world(for: coordinator.metrics.inactiveBank).lead?.metrics.voiceCount ?? 0
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
    var engineTopologyForTesting: DayObjectsInstrumentBankEngineTopologyMetrics {
        pair.bankA.metrics.engineTopology
    }
    var worldRecycleCountsForTesting: [Int] {
        [worldA.bank.metrics.recycleCount, worldB.bank.metrics.recycleCount]
    }
    var happeningRecordIDsForTesting: Set<String> {
        guard isPrepared else { return [] }
        return Set(
            (worldA.happenings?.metrics.activeHappeningIDs ?? [])
                + (worldB.happenings?.metrics.activeHappeningIDs ?? [])
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
            ? activeWorld.happenings?.metrics.activeHappeningIDs.count ?? 0
            : 0
        return .init(
            activeTransportCount: transportIsRunning ? 1 : 0,
            activeTaskCount: (transportIsRunning ? 1 : 0) + (tempoUpdateTask == nil ? 0 : 1),
            activeNodeCount: metrics.nodeCount,
            activeVoiceCount: worldA.activeVoiceCount + worldB.activeVoiceCount,
            activeHappeningCount: activeHappeningCount,
            pendingRemixCount: coordinatorMetrics.pendingRemixCount,
            leadVoiceCount: isPrepared
                ? (worldA.lead?.metrics.voiceCount ?? 0) + (worldB.lead?.metrics.voiceCount ?? 0)
                : 0
        )
    }

    var diagnosticMeterSnapshot: DayObjectsDiagnosticMeterSnapshot {
        let metrics = pair.metrics
        return .init(
            roleBusMetrics: metrics.roleBusMetrics,
            masterMetrics: metrics.masterMetrics
        )
    }

    func setHappeningAttackHandler(_ handler: ((String) -> Void)?) {
        worldA.setHappeningAttackHandler(handler)
        worldB.setHappeningAttackHandler(handler)
    }

    func applyDiagnosticAudition(_ mode: DayObjectsAuditionMode, plan: DayMusicPlan) {
        guard mode != .kickBassSidechain else { return }
        diagnosticAuditionMode = mode
        activeWorld.applyDiagnosticAudition(mode, plan: plan)
    }

    func releaseDiagnosticAudition(plan: DayMusicPlan) {
        diagnosticAuditionMode = .fullComposition
        activeWorld.resetDiagnosticAudition()
        activeWorld.applyDiagnosticAudition(.fullComposition, plan: plan)
    }

    func auditionKickBassSidechain(preferredBassID: DayObjectsInstrumentID?) -> DayObjectsSidechainAuditionResult? {
        guard let deadline = DayObjectsDiagnosticScheduling.deadline(
            using: diagnosticHostTimeProvider
        ) else { return nil }
        return activeWorld.auditionKickBassSidechain(
            preferredBassID: preferredBassID,
            hostTime: deadline
        )
    }

    var metrics: DayObjectsRemixRuntimeMetrics {
        let banks = [worldA.bank.metrics, worldB.bank.metrics]
        let tonal = banks.reduce(0) { $0 + $1.allocatedTonalVoiceCount }
        let piano = banks.reduce(0) { $0 + $1.allocatedPianoVoiceCount }
        let drums = banks.reduce(0) { $0 + $1.allocatedDrumPlayerCount }
        let leadCount = isPrepared
            ? (worldA.lead?.metrics.voiceCount ?? 0) + (worldB.lead?.metrics.voiceCount ?? 0)
            : 0
        let happeningCount = isPrepared
            ? (worldA.happenings?.metrics.activeVoiceCount ?? 0)
                + (worldB.happenings?.metrics.activeVoiceCount ?? 0)
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

    init(
        bundle: Bundle = .main,
        soundWorldResources: DayObjectsSoundWorldResources? = nil,
        diagnosticHostTimeProvider: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) throws {
        self.diagnosticHostTimeProvider = diagnosticHostTimeProvider
        pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: bundle,
            soundWorldResources: soundWorldResources,
            outputGainHostTimeProvider: diagnosticHostTimeProvider
        )
        worldA = WorldState(bank: PlaybackWorldBank(instrumentBank: pair.bankA))
        worldB = WorldState(bank: PlaybackWorldBank(instrumentBank: pair.bankB))
        coordinator = try DayObjectsRemixCoordinator(
            bankA: worldA.bank,
            bankB: worldB.bank,
            runtime: self
        )
    }

    func prepare(plan: DayMusicPlan) throws {
        let previousDesiredMode = desiredAudioOwnershipMode
        do {
            try pair.prepare(configuration: .playbackWorld)
            try coordinator.prepare(initialPlan: plan)
            auditionReleaseTasks.values.forEach { $0.cancel() }
            auditionReleaseTasks.removeAll()
            auditionHandles.removeAll()
            auditionRecordsForTesting.removeAll()
            worldA.bank.setOutputGain(0, rampDurationSeconds: 0)
            worldB.bank.setOutputGain(0, rampDurationSeconds: 0)
            gestureOwner = nil
            isPrepared = true
            desiredAudioOwnershipMode = .fullPair
        } catch {
            desiredAudioOwnershipMode = previousDesiredMode
            throw error
        }
    }

    func prepareSamples(recipeIDs: Set<HappeningSoundRecipeID>) async throws {
        try pair.bankA.prepare(level: .sampleOnly(recipeIDs))
        desiredAudioOwnershipMode = .sampleOnly
    }

    func startAudio() throws {
        switch desiredAudioOwnershipMode {
        case .fullPair:
            try pair.start()
            currentAudioOwnershipMode = .fullPair
        case .sampleOnly:
            try pair.bankA.start()
            currentAudioOwnershipMode = .sampleOnly
        case nil:
            throw DayObjectsInstrumentBankError.notPrepared
        }
    }

    func auditionHappening(
        _ recipeID: HappeningSoundRecipeID,
        harmony: DayObjectsHappeningAuditionHarmony
    ) throws {
        let recipe = try Self.recipe(recipeID)
        let reference = try auditionReference(harmony)
        let sound = HappeningPitchResolver.resolve(
            recipe: recipe,
            chord: reference.chord,
            tonalWorld: reference.world
        )
        let effects = DayObjectsHappeningAuditionReference.effects(for: recipe)
        let handle = try pair.bankA.happenings.play(
            sound,
            gain: 1,
            priority: .manualAudition,
            effects: effects,
            pan: 0
        )
        auditionHandles.append(handle)
        scheduleAuditionRelease(handle, after: recipe.releaseSeconds, pool: pair.bankA.happenings)
        auditionRecordsForTesting.append(.init(
            resolvedSound: sound,
            effects: effects,
            priority: .manualAudition
        ))
    }

    func releaseAuditions() {
        let pool = pair.bankA.happenings
        auditionReleaseTasks.values.forEach { $0.cancel() }
        auditionReleaseTasks.removeAll()
        auditionHandles.forEach(pool.stop)
        auditionHandles.removeAll()
    }

    func rollbackFullStartToSampleOnly() {
        if currentAudioOwnershipMode == .fullPair {
            pair.demoteToBankASampleOnlyOwnership()
        }
        desiredAudioOwnershipMode = .sampleOnly
        currentAudioOwnershipMode = .sampleOnly
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
        worldA.endLeadIfBound()
        worldB.endLeadIfBound()
        gestureOwner = nil
    }

    func cancelRemix() {
        coordinator.cancelPending()
    }

    func releaseLayers() {
        diagnosticAuditionMode = .fullComposition
        worldA.resetDiagnosticAudition()
        worldB.resetDiagnosticAudition()
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

    func stopAudio() async {
        switch currentAudioOwnershipMode {
        case .fullPair:
            pair.stop()
        case .sampleOnly:
            await pair.bankA.stop()
        case nil:
            if pair.metrics.sharedEngineIsRunning {
                assertionFailure("Running live audio must have an explicit ownership mode")
                if pair.metrics.lifecycleState == .started {
                    pair.stop()
                } else {
                    await pair.bankA.stop()
                }
            }
        }
        currentAudioOwnershipMode = nil
        desiredAudioOwnershipMode = nil
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
        try? activeWorld.happenings?.add(plan, currentChord: chord, playBirth: playBirth)
    }

    func removeHappening(id: String) {
        activeWorld.happenings?.remove(id: id)
    }

    func beginLead(_ gesture: LeadGestureSample) {
        activeWorld.lead?.begin(gesture)
        if activeWorld.lead?.metrics.voiceCount == 1 {
            gestureOwner = coordinator.metrics.activeBank
        }
    }

    func updateLead(_ gesture: LeadGestureSample) {
        world(for: gestureOwner ?? coordinator.metrics.activeBank).lead?.update(gesture)
    }

    func prepare(bank: PlaybackWorldBank) throws {
        try bank.prepare()
        try world(for: bank).bindPreparedPlayersIfNeeded()
    }

    func configure(bank: PlaybackWorldBank, plan: DayMusicPlan) throws {
        try world(for: bank).configure(plan, diagnosticAuditionMode: diagnosticAuditionMode)
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
        try world(for: bank).startScheduling(at: event.position)
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
        guard let held = source.lead?.heldState else { return .notHeld }
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
        guard let sourceLead = world(for: oldBank).lead,
              let destinationLead = world(for: newBank).lead else {
            gestureOwner = nil
            return
        }
        let result = sourceLead.handoff(
            to: destinationLead,
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
        guard let sourceLead = world(for: oldBank).lead,
              let destinationLead = world(for: newBank).lead else {
            gestureOwner = nil
            return
        }
        let result = sourceLead.handoff(
            to: destinationLead,
            safeCommonMIDINote: nil
        )
        gestureOwner = result.gestureOwner == .destination ? slot(for: newBank) : nil
    }

    func isDrained(_ bank: PlaybackWorldBank) -> Bool {
        let state = world(for: bank)
        guard !state.isScheduling else { return false }
        if state.isReleasing { state.finishReleaseBeforeRecycle() }
        return (state.harmony?.metrics.activeVoiceCount ?? 0) == 0
            && (state.bass?.metrics.activeVoiceCount ?? 0) == 0
            && (state.happenings?.metrics.activeVoiceCount ?? 0) == 0
            && (state.lead?.metrics.voiceCount ?? 0) == 0
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

    private func auditionReference(
        _ harmony: DayObjectsHappeningAuditionHarmony
    ) throws -> (chord: ChordPlan, world: TonalWorldPlan) {
        switch harmony {
        case .referenceC4:
            return (DayObjectsHappeningAuditionReference.c4Chord, DayObjectsHappeningAuditionReference.c4World)
        case .currentHarmony:
            guard let plan = activeWorld.plan,
                  let chord = plan.world.progression[safe: activeWorld.currentChordIndex] else {
                throw DayObjectsAudioError("No sounding harmony for Happening audition")
            }
            return (chord, plan.world)
        }
    }

    private static func recipe(_ recipeID: HappeningSoundRecipeID) throws -> HappeningSoundRecipe {
        guard let recipe = HappeningSoundCatalog.recipe(for: recipeID) else {
            throw HappeningSamplePoolError.recipeUnavailable(recipeID)
        }
        return recipe
    }

    private func scheduleAuditionRelease(
        _ handle: HappeningPlaybackHandle,
        after seconds: Double,
        pool: DayObjectsHappeningSamplePoolProtocol
    ) {
        auditionReleaseTasks[handle] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            pool.stop(handle)
            self?.auditionHandles.removeAll { $0 == handle }
            self?.auditionReleaseTasks[handle] = nil
        }
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

/// The iPhone runtime keeps one complete musical world alive. Remix is applied
/// in place on a bar boundary, which trades the old dual-world crossfade for a
/// much smaller realtime graph and predictable playback on device speakers.
@MainActor
final class DayObjectsMobilePlaybackRuntime: DayObjectsPlaybackRuntimeProtocol {
    private let world: DayObjectsLivePlaybackRuntime.WorldState
    private let diagnosticHostTimeProvider: () -> TimeInterval
    private var diagnosticAuditionMode: DayObjectsAuditionMode = .fullComposition
    private var pendingStructuralPlan: DayMusicPlan?
    private var transportIsRunning = false
    private var tempoUpdateTask: Task<Void, Never>?
    private var isPrepared = false
    private var isSamplePrepared = false
    private var auditionHandles: [HappeningPlaybackHandle] = []
    private var auditionReleaseTasks: [HappeningPlaybackHandle: Task<Void, Never>] = [:]
    private(set) var auditionRecordsForTesting: [DayObjectsHappeningAuditionRecord] = []

    var auditionHandleCountForTesting: Int { auditionHandles.count }
    var auditionReleaseTaskCountForTesting: Int { auditionReleaseTasks.count }
    var audioEngineIsRunningForTesting: Bool {
        world.bank.instrumentBank.metrics.state == .started
    }

    var preparedRhythmBackendCount: Int { world.hasPreparedRhythmBackend ? 1 : 0 }
    var instrumentAllocationCountForTesting: Int {
        world.bank.instrumentBank.metrics.allocationFingerprint == nil ? 0 : 1
    }
    var allocatedPianoVoiceCountForTesting: Int {
        world.bank.metrics.allocatedPianoVoiceCount
    }
    var preparedHappeningRecipeIDsForTesting: Set<HappeningSoundRecipeID> {
        world.bank.happenings.metrics.availableRecipeIDs
    }
    var activePlanForTesting: DayMusicPlan? { world.plan }
    var activeProgramEffectMetricsForTesting: DayObjectsProgramEffectMetrics {
        world.bank.programEffectMetrics
    }
    var activeBassDuckGainMetricsForTesting: BassDuckGainMetrics {
        world.bank.bassDuckGainMetrics
    }
    var retainedDiagnosticAuditionModeForTesting: DayObjectsAuditionMode {
        diagnosticAuditionMode
    }
    var worldDiagnosticAuditionModeForTesting: DayObjectsAuditionMode {
        world.diagnosticAuditionMode
    }
    var activeHappeningAttackHistoryForTesting: [HappeningAttackRecord] {
        world.happenings?.metrics.attackHistory ?? []
    }
    var totalBassAttackCountForTesting: Int { world.bass?.metrics.attackCount ?? 0 }
    var totalBassReleaseCountForTesting: Int { world.bass?.metrics.releaseCount ?? 0 }
    var activeBassVoiceCountForTesting: Int { world.bass?.metrics.activeVoiceCount ?? 0 }
    var activeBassSchedulingOriginForTesting: Int64? {
        world.bass?.metrics.schedulingOriginSubdivision
    }

    func startPreparedWorldForTesting() throws { try world.startScheduling() }
    func renderForTesting(_ event: DayObjectsTransportEvent) { renderTransportEvent(event) }

    private lazy var transport = DayObjectsTransport { [weak self] event in
        await self?.renderTransportEvent(event)
    }

    var playbackMetrics: DayObjectsPlaybackMetrics {
        let bankMetrics = world.bank.metrics
        return .init(
            activeTransportCount: transportIsRunning ? 1 : 0,
            activeTaskCount: (transportIsRunning ? 1 : 0) + (tempoUpdateTask == nil ? 0 : 1),
            activeNodeCount: bankMetrics.allocatedTonalVoiceCount
                + bankMetrics.allocatedPianoVoiceCount
                + bankMetrics.allocatedDrumPlayerCount,
            activeVoiceCount: world.activeVoiceCount,
            activeHappeningCount: isPrepared
                ? world.happenings?.metrics.activeHappeningIDs.count ?? 0
                : 0,
            pendingRemixCount: pendingStructuralPlan == nil ? 0 : 1,
            leadVoiceCount: isPrepared ? world.lead?.metrics.voiceCount ?? 0 : 0
        )
    }

    var diagnosticMeterSnapshot: DayObjectsDiagnosticMeterSnapshot {
        world.bank.instrumentBank.diagnosticMeterSnapshot
    }

    func setHappeningAttackHandler(_ handler: ((String) -> Void)?) {
        world.setHappeningAttackHandler(handler)
    }

    func applyDiagnosticAudition(_ mode: DayObjectsAuditionMode, plan: DayMusicPlan) {
        if mode != .kickBassSidechain { diagnosticAuditionMode = mode }
        world.applyDiagnosticAudition(mode, plan: plan)
    }

    func releaseDiagnosticAudition(plan: DayMusicPlan) {
        diagnosticAuditionMode = .fullComposition
        world.resetDiagnosticAudition()
        world.applyDiagnosticAudition(.fullComposition, plan: plan)
    }

    func auditionKickBassSidechain(preferredBassID: DayObjectsInstrumentID?) -> DayObjectsSidechainAuditionResult? {
        guard let deadline = DayObjectsDiagnosticScheduling.deadline(
            using: diagnosticHostTimeProvider
        ) else { return nil }
        return world.auditionKickBassSidechain(
            preferredBassID: preferredBassID,
            hostTime: deadline
        )
    }

    init(
        bundle: Bundle = .main,
        soundWorldResources: DayObjectsSoundWorldResources? = nil,
        diagnosticHostTimeProvider: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.diagnosticHostTimeProvider = diagnosticHostTimeProvider
        world = DayObjectsLivePlaybackRuntime.WorldState(
            bank: PlaybackWorldBank(instrumentBank: DayObjectsInstrumentBank(
                bundle: bundle,
                soundWorldResources: soundWorldResources,
                tonalVoiceProfile: .mobileRealtime,
                audioHostTimeProvider: diagnosticHostTimeProvider
            ))
        )
    }

    func prepareForPlayback(plan: DayMusicPlan) async throws {
        if let bank = world.bank.instrumentBank as? DayObjectsInstrumentBank {
            try await bank.prepareForPlayback(configuration: PlaybackWorldBankConfiguration.mobilePlaybackWorld,
                                              happeningRecipeIDs: Set(plan.happenings.map(\.recipeID)))
        }
        try Task.checkCancellation()
        try prepare(plan: plan)
    }

    func prepare(plan: DayMusicPlan) throws {
        try world.bank.prepare(
            happeningRecipeIDs: Set(plan.happenings.map(\.recipeID)),
            configuration: PlaybackWorldBankConfiguration.mobilePlaybackWorld
        )
        try world.bindPreparedPlayersIfNeeded()
        world.releaseAll()
        try world.configure(
            plan,
            diagnosticAuditionMode: diagnosticAuditionMode,
            usesSampledPiano: false
        )
        auditionReleaseTasks.values.forEach { $0.cancel() }
        auditionReleaseTasks.removeAll()
        auditionHandles.removeAll()
        auditionRecordsForTesting.removeAll()
        world.bank.setOutputGain(0, rampDurationSeconds: 0)
        pendingStructuralPlan = nil
        isPrepared = true
        isSamplePrepared = false
    }

    func prepareSamples(recipeIDs: Set<HappeningSoundRecipeID>) async throws {
        guard let bank = world.bank.instrumentBank as? DayObjectsInstrumentBank else {
            throw DayObjectsAudioError("Sample-only preparation requires the shared instrument bank")
        }
        try bank.prepare(level: .sampleOnly(recipeIDs))
        isSamplePrepared = true
    }

    func startAudio() throws {
        guard isPrepared || isSamplePrepared else { throw DayObjectsInstrumentBankError.notPrepared }
        try world.bank.instrumentBank.start()
    }

    func auditionHappening(
        _ recipeID: HappeningSoundRecipeID,
        harmony: DayObjectsHappeningAuditionHarmony
    ) throws {
        guard let recipe = HappeningSoundCatalog.recipe(for: recipeID) else {
            throw HappeningSamplePoolError.recipeUnavailable(recipeID)
        }
        let reference: (chord: ChordPlan, world: TonalWorldPlan)
        switch harmony {
        case .referenceC4:
            reference = (
                DayObjectsHappeningAuditionReference.c4Chord,
                DayObjectsHappeningAuditionReference.c4World
            )
        case .currentHarmony:
            guard let plan = world.plan,
                  let chord = plan.world.progression[safe: world.currentChordIndex] else {
                throw DayObjectsAudioError("No sounding harmony for Happening audition")
            }
            reference = (chord, plan.world)
        }
        let sound = HappeningPitchResolver.resolve(
            recipe: recipe,
            chord: reference.chord,
            tonalWorld: reference.world
        )
        let effects = DayObjectsHappeningAuditionReference.effects(for: recipe)
        try world.bank.happenings.prepare(recipeIDs: [recipeID])
        let handle = try world.bank.happenings.play(
            sound,
            gain: 1,
            priority: .manualAudition,
            effects: effects,
            pan: 0
        )
        auditionHandles.append(handle)
        scheduleAuditionRelease(handle, after: recipe.releaseSeconds, pool: world.bank.happenings)
        auditionRecordsForTesting.append(.init(
            resolvedSound: sound,
            effects: effects,
            priority: .manualAudition
        ))
    }

    func releaseAuditions() {
        let pool = world.bank.happenings
        auditionReleaseTasks.values.forEach { $0.cancel() }
        auditionReleaseTasks.removeAll()
        auditionHandles.forEach(pool.stop)
        auditionHandles.removeAll()
    }

    func rollbackFullStartToSampleOnly() {}

    func startTransport(plan: DayMusicPlan) async throws {
        try world.startScheduling()
        transportIsRunning = true
        await transport.start(
            tempoBPM: plan.rhythm.tempoBPM,
            harmonicCycleBars: plan.world.cycleBars
        )
    }

    func fadeMaster(to plan: DayMusicPlan) throws {
        guard world.bank.instrumentBank.metrics.state == .started else {
            throw DayObjectsInstrumentBankError.startFailed
        }
        world.bank.setOutputGain(1, rampDurationSeconds: 0.35)
    }

    func stopScheduling() { world.isScheduling = false }
    func endLead() { world.endLeadIfBound() }
    func cancelRemix() { pendingStructuralPlan = nil }
    func releaseLayers() {
        diagnosticAuditionMode = .fullComposition
        world.resetDiagnosticAudition()
        world.releaseAll()
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

    func stopAudio() async {
        await world.bank.instrumentBank.stop()
        world.bank.setOutputGain(0, rampDurationSeconds: 0)
    }

    func applyContinuous(_ plan: DayMusicPlan) {
        world.applyContinuous(plan)
        updateTransport(for: plan)
    }

    func scheduleStructuralPlan(_ plan: DayMusicPlan) {
        pendingStructuralPlan = plan
    }

    func addHappening(_ plan: HappeningMusicPlan, playBirth: Bool) {
        guard let tonalPlan = world.plan,
              let chord = tonalPlan.world.progression[safe: world.currentChordIndex] else { return }
        try? world.happenings?.add(plan, currentChord: chord, playBirth: playBirth)
    }

    func removeHappening(id: String) { world.happenings?.remove(id: id) }
    func beginLead(_ gesture: LeadGestureSample) { world.lead?.begin(gesture) }
    func updateLead(_ gesture: LeadGestureSample) { world.lead?.update(gesture) }

    private func renderTransportEvent(_ event: DayObjectsTransportEvent) {
        if event.kind == .subdivision,
           event.position.subdivisionInBar == 0,
           let plan = pendingStructuralPlan {
            world.releaseAll()
            do {
                try world.configure(
                    plan,
                    diagnosticAuditionMode: diagnosticAuditionMode,
                    usesSampledPiano: false
                )
                try world.startScheduling(at: event.position)
                pendingStructuralPlan = nil
                updateTransport(for: plan)
            } catch {
                // Keep the last configured world stopped instead of allowing a
                // partially configured Remix to hammer the realtime thread.
                world.isScheduling = false
            }
        }
        world.render(event)
    }

    private func updateTransport(for plan: DayMusicPlan) {
        tempoUpdateTask?.cancel()
        tempoUpdateTask = Task { [transport] in
            await transport.setTempoBPM(plan.rhythm.tempoBPM)
        }
    }

    private func scheduleAuditionRelease(
        _ handle: HappeningPlaybackHandle,
        after seconds: Double,
        pool: DayObjectsHappeningSamplePoolProtocol
    ) {
        auditionReleaseTasks[handle] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            pool.stop(handle)
            self?.auditionHandles.removeAll { $0 == handle }
            self?.auditionReleaseTasks[handle] = nil
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension HarmonyPlan {
    func replacingFeltPianoWithTonalKeys() -> HarmonyPlan {
        let fallback = roles.lazy.compactMap { role -> DayObjectsInstrumentID? in
            guard role.role == .secondaryPadOrKeys || role.role == .innerMotion else { return nil }
            if case let .tonal(id) = role.instrumentTarget { return id }
            return nil
        }.first ?? roles.lazy.compactMap { role -> DayObjectsInstrumentID? in
            if case let .tonal(id) = role.instrumentTarget { return id }
            return nil
        }.first

        guard let fallback else {
            return .init(
                sleepProgress: sleepProgress,
                cycleBars: cycleBars,
                chordCount: chordCount,
                roles: roles.filter { $0.instrumentTarget != .feltPiano }
            )
        }
        return .init(
            sleepProgress: sleepProgress,
            cycleBars: cycleBars,
            chordCount: chordCount,
            roles: roles.map { role in
                guard role.instrumentTarget == .feltPiano else { return role }
                return .init(
                    role: role.role,
                    instrumentTarget: .tonal(fallback),
                    register: role.register,
                    gain: role.gain,
                    attackSeconds: role.attackSeconds,
                    releaseSeconds: role.releaseSeconds,
                    delaySend: role.delaySend,
                    reverbSend: role.reverbSend,
                    activation: role.activation,
                    chordSchedule: role.chordSchedule,
                    crossfadeBars: role.crossfadeBars
                )
            }
        )
    }
}
#endif
