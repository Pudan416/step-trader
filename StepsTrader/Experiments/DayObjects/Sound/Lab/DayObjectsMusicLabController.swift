#if DEBUG || INTERNAL_BUILD
import Combine
import Foundation

enum HappeningPadAuditionStatus: Equatable, Sendable {
    case ready
    case loading
    case soundStopping
    case unavailable
}

enum DayObjectsLabLifecycleEvent: Sendable {
    case viewAppeared
    case viewDisappeared
    case sceneActive
    case sceneInactive
    case interruptionBegan
    case interruptionEnded

    fileprivate var isActive: Bool {
        switch self {
        case .viewAppeared, .sceneActive, .interruptionEnded: true
        case .viewDisappeared, .sceneInactive, .interruptionBegan: false
        }
    }

    fileprivate var requiresAudioStop: Bool { !isActive }
}

struct DayObjectsLabLifecycleIntent: Sendable {
    fileprivate let generation: UInt64
    fileprivate let event: DayObjectsLabLifecycleEvent
}

struct DayObjectsSoundButtonIntent: Sendable {
    fileprivate enum Action: Sendable {
        case turnOn
        case turnOff
    }

    fileprivate let id: UUID
    fileprivate let action: Action
}

/// Single state and command boundary for the Day Objects lab. Visual changes
/// are published synchronously; audio receives only the typed plan delta while
/// Sound is explicitly on.
@MainActor
final class DayObjectsMusicLabController: ObservableObject {
    static let maximumSteps = 10_000.0
    static let maximumSleepHours = 8.0
    static let maximumHappenings = 10
    static let maximumSpentColors = 100

    @Published private(set) var state: DayObjectsLabMusicState
    @Published private(set) var currentPlan: DayMusicPlan
    @Published private(set) var soundState: DayObjectsSoundState = .off
    @Published private(set) var loadingHappeningRecipeIDs: Set<HappeningSoundRecipeID> = []
    @Published private(set) var unavailableHappeningRecipeIDs: Set<HappeningSoundRecipeID> = []
    @Published private(set) var auditionMode: DayObjectsAuditionMode = .fullComposition
    @Published private(set) var busMeterRows = DayObjectsRoleBus.allCases.map {
        DayObjectsBusMeterRow(role: $0, metrics: .init(peakDBFS: -120, rmsDBFS: -120, activeVoiceCount: 0))
    }
    @Published private(set) var masterMeterRow = DayObjectsMasterMeterRow(
        peakDBFS: -120,
        rmsDBFS: -120,
        estimatedLimiterReductionDB: 0
    )

    private let playback: any DayObjectsMusicPlaybackProtocol
    private var isLeadHeld = false
    private var isLeadAvailable = true
    private var stopTask: Task<Void, Never>?
    private var stopID: UUID?
    private var lifecycleGeneration: UInt64 = 0
    private var happeningPadGeneration: UInt64 = 0
    private var happeningPadLifecycleIsActive = true
    private var happeningPadTasks: [HappeningSoundRecipeID: HappeningPadTask] = [:]
    private var lifecycleEventGeneration: UInt64 = 0
    private var lastDiagnosticMeterPoll = Date.distantPast
    private var diagnosticActionGeneration: UInt64 = 0
    private var diagnosticActionTask: Task<Void, Never>?
    @Published private var acceptedSoundButtonIntent: DayObjectsSoundButtonIntent?

    private struct HappeningPadTask {
        let id: UUID
        let task: Task<Void, Never>
    }

    init(
        state: DayObjectsLabMusicState = DayObjectsLabMusicState(),
        playback: (any DayObjectsMusicPlaybackProtocol)? = nil
    ) {
        var sanitized = state
        sanitized.steps = Self.clamp(state.steps, to: 0...Self.maximumSteps)
        sanitized.sleepHours = Self.clamp(state.sleepHours, to: 0...Self.maximumSleepHours)
        sanitized.happeningCount = min(max(state.happeningCount, 0), Self.maximumHappenings)
        sanitized.spentColors = min(max(state.spentColors, 0), Self.maximumSpentColors)
        self.state = sanitized
        currentPlan = Self.makePlan(for: sanitized)
        if let playback {
            self.playback = playback
        } else {
            let runtime = DayObjectsMobilePlaybackRuntime()
            self.playback = DayObjectsMusicPlaybackEngine(
                audioSession: DayObjectsSystemAudioSession(),
                runtime: runtime
            )
        }
    }

    var normalizedInput: NormalizedDayMusicInput { currentPlan.input }
    var digitalImpact: DayObjectDigitalImpact { .init(spentColors: state.spentColors) }
    var happeningIDs: [String] { Self.happeningIDs(count: state.happeningCount) }
    var metrics: DayObjectsPlaybackMetrics { playback.metrics }

    var worldSummary: String {
        let world = currentPlan.world
        let center = Self.pitchClassNames[world.centerPitchClass]
        let chordLabel = world.progression.count == 1 ? "chord" : "chords"
        return "\(center) \(Self.modeName(world.mode)) · \(world.progression.count) \(chordLabel) · \(world.cycleBars)-bar cycle"
    }

    /// Changes the already running composition mix only after the user has
    /// explicitly enabled canvas Sound. This is state-only while Sound is off.
    func selectAuditionMode(_ mode: DayObjectsAuditionMode) {
        guard soundState == .on else { return }
        auditionMode = mode
        playback.applyDiagnosticAudition(mode, plan: currentPlan)
    }

    /// Polls the Task 7 fixed-size meter handoff at most ten times a second.
    /// The audio callback itself never publishes SwiftUI state.
    func refreshDiagnosticMeters(now: Date = .now) {
        guard now.timeIntervalSince(lastDiagnosticMeterPoll) >= 0.1 else { return }
        lastDiagnosticMeterPoll = now
        let snapshot = playback.diagnosticMeterSnapshot
        busMeterRows = DayObjectsRoleBus.allCases.map {
            .init(role: $0, metrics: snapshot.roleBusMetrics.metrics(for: $0))
        }
        masterMeterRow = .init(metrics: snapshot.masterMetrics)
    }

    /// Releases a debug audition without changing the normal Sound lifecycle.
    /// In particular, collapsing diagnostics must never start the canvas.
    func disableDiagnostics() {
        invalidateDiagnosticActions()
        guard auditionMode != .fullComposition else { return }
        auditionMode = .fullComposition
        playback.releaseDiagnosticAudition()
    }

    @discardableResult
    func beginKickBassSidechainAudition(
        preferredBassID: DayObjectsInstrumentID?,
        beforeAudition: @escaping @MainActor () async -> Void = {},
        onResult: @escaping @MainActor (DayObjectsSidechainAuditionResult) -> Void = { _ in }
    ) -> Task<Void, Never>? {
        guard soundState == .on, diagnosticActionTask == nil else { return nil }
        let generation = diagnosticActionGeneration
        let task = Task { @MainActor [weak self] in
            await beforeAudition()
            guard let self,
                  !Task.isCancelled,
                  generation == self.diagnosticActionGeneration,
                  self.soundState == .on,
                  self.stopTask == nil else { return }
            if let result = self.playback.auditionKickBassSidechain(preferredBassID: preferredBassID) {
                onResult(result)
            }
            if generation == self.diagnosticActionGeneration {
                self.diagnosticActionTask = nil
            }
        }
        diagnosticActionTask = task
        return task
    }

    func toggleSound() async {
        guard let intent = acceptSoundButtonIntent() else { return }
        await completeSoundButtonIntent(intent)
    }

    func acceptSoundButtonIntent() -> DayObjectsSoundButtonIntent? {
        guard acceptedSoundButtonIntent == nil,
              soundState != .starting else { return nil }
        let action: DayObjectsSoundButtonIntent.Action = soundState == .on ? .turnOff : .turnOn
        let intent = DayObjectsSoundButtonIntent(id: UUID(), action: action)
        acceptedSoundButtonIntent = intent
        if action == .turnOff {
            cancelHappeningPadTasks(deactivate: false)
        }
        return intent
    }

    func completeSoundButtonIntent(_ intent: DayObjectsSoundButtonIntent) async {
        guard acceptedSoundButtonIntent?.id == intent.id else { return }
        defer {
            if acceptedSoundButtonIntent?.id == intent.id {
                acceptedSoundButtonIntent = nil
            }
        }
        switch intent.action {
        case .turnOff:
            guard soundState == .on else { return }
            await stop()
        case .turnOn:
            guard soundState != .on, soundState != .starting else { return }
            await startSound()
        }
    }

    private func startSound() async {
        let startedPlan = currentPlan
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        soundState = .starting
        do {
            try await playback.start(plan: startedPlan)
            guard generation == lifecycleGeneration else {
                soundState = .off
                return
            }
            soundState = playback.state
            if soundState == .on, currentPlan != startedPlan {
                routePlaybackChange(from: startedPlan, to: currentPlan)
            }
        } catch {
            guard generation == lifecycleGeneration else {
                soundState = .off
                return
            }
            soundState = playback.state
            if soundState == .starting || soundState == .off {
                soundState = .error(.classifying(error))
            }
        }
    }

    func auditionHappening(_ recipeID: HappeningSoundRecipeID) async throws {
        try await auditionHappening(recipeID, generation: happeningPadGeneration)
    }

    @discardableResult
    func beginHappeningPadAudition(
        _ recipeID: HappeningSoundRecipeID,
        beforeAudition: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never>? {
        guard happeningPadLifecycleIsActive,
              stopTask == nil,
              acceptedSoundButtonIntent?.action != .turnOff,
              !unavailableHappeningRecipeIDs.contains(recipeID),
              happeningPadTasks[recipeID] == nil else { return nil }

        let generation = happeningPadGeneration
        let operationID = UUID()
        loadingHappeningRecipeIDs.insert(recipeID)
        let task = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            await beforeAudition()
            guard let self else { return }
            guard !Task.isCancelled,
                  self.happeningPadLifecycleIsActive,
                  self.happeningPadGeneration == generation else {
                self.finishHappeningPadTask(recipeID, operationID: operationID)
                return
            }
            _ = try? await self.auditionHappening(recipeID, generation: generation)
            self.finishHappeningPadTask(recipeID, operationID: operationID)
        }
        happeningPadTasks[recipeID] = .init(id: operationID, task: task)
        return task
    }

    func happeningPadStatus(for recipeID: HappeningSoundRecipeID) -> HappeningPadAuditionStatus {
        if unavailableHappeningRecipeIDs.contains(recipeID) { return .unavailable }
        if acceptedSoundButtonIntent?.action == .turnOff { return .soundStopping }
        if loadingHappeningRecipeIDs.contains(recipeID) { return .loading }
        return .ready
    }

    func setSteps(_ value: Double) {
        updateState { $0.steps = Self.clamp(value, to: 0...Self.maximumSteps) }
    }

    func setSleepHours(_ value: Double) {
        updateState { $0.sleepHours = Self.clamp(value, to: 0...Self.maximumSleepHours) }
    }

    func setHappeningCount(_ value: Int) {
        updateState { $0.happeningCount = min(max(value, 0), Self.maximumHappenings) }
    }

    func setSpentColors(_ value: Int) {
        updateState { $0.spentColors = min(max(value, 0), Self.maximumSpentColors) }
    }

    func remix() {
        updateState { $0.remixSeed &+= 1 }
    }

    func beginLead(
        _ gesture: LeadGestureSample,
        isGridVisible: Bool,
        isVoiceOverRunning: Bool
    ) {
        leadAvailabilityChanged(
            isGridVisible: isGridVisible,
            isVoiceOverRunning: isVoiceOverRunning
        )
        guard soundState == .on, isLeadAvailable else { return }
        isLeadHeld = true
        playback.beginLead(gesture)
    }

    func updateLead(_ gesture: LeadGestureSample) {
        guard soundState == .on, isLeadAvailable, isLeadHeld else { return }
        playback.updateLead(gesture)
    }

    func leadAvailabilityChanged(
        isGridVisible: Bool,
        isVoiceOverRunning: Bool
    ) {
        isLeadAvailable = !isGridVisible && !isVoiceOverRunning
        if !isLeadAvailable { endLead() }
    }

    func endLead() {
        guard isLeadHeld else { return }
        isLeadHeld = false
        playback.endLead()
    }

    func setHappeningPadLifecycleActive(_ isActive: Bool) {
        if isActive {
            activateHappeningPadLifecycle()
        } else if happeningPadLifecycleIsActive || !happeningPadTasks.isEmpty {
            cancelHappeningPadTasks(deactivate: true)
        }
    }

    @discardableResult
    func acceptLifecycleEvent(_ event: DayObjectsLabLifecycleEvent) -> DayObjectsLabLifecycleIntent {
        lifecycleEventGeneration &+= 1
        let intent = DayObjectsLabLifecycleIntent(
            generation: lifecycleEventGeneration,
            event: event
        )
        if !event.isActive {
            acceptedSoundButtonIntent = nil
            disableDiagnostics()
        }
        setHappeningPadLifecycleActive(event.isActive)
        return intent
    }

    func completeLifecycleEvent(_ intent: DayObjectsLabLifecycleIntent) async {
        guard intent.generation == lifecycleEventGeneration,
              intent.event.requiresAudioStop else { return }
        await stop(includingSampleOnly: true)
    }

    func viewDidAppear() {
        _ = acceptLifecycleEvent(.viewAppeared)
    }
    func viewDidDisappear() async {
        let intent = acceptLifecycleEvent(.viewDisappeared)
        await completeLifecycleEvent(intent)
    }
    func turnSoundOff() async {
        acceptedSoundButtonIntent = nil
        cancelHappeningPadTasks(deactivate: false)
        disableDiagnostics()
        await stop(includingSampleOnly: true)
    }
    func sceneActivityChanged(isActive: Bool) async {
        let intent = acceptLifecycleEvent(isActive ? .sceneActive : .sceneInactive)
        await completeLifecycleEvent(intent)
    }
    func interruptionBegan() async {
        let intent = acceptLifecycleEvent(.interruptionBegan)
        await completeLifecycleEvent(intent)
    }
    func interruptionEnded() async {
        let intent = acceptLifecycleEvent(.interruptionEnded)
        await completeLifecycleEvent(intent)
    }

    func sceneInput(
        dayKey: String,
        reduceMotion: Bool,
        motionEnergyOverride: Double? = nil,
        visualClarityOverride: Double? = nil,
        uiExclusionRegion: DayObjectNormalizedRect = .dayObjectsLabControls,
        canvasCoverage: DayObjectCanvasCoverage? = nil,
        paletteCategories: Set<ModernPaletteCategory> = []
    ) -> DayObjectSceneInput {
        let derived = DayObjectSceneInput.labPreview(
            dayKey: dayKey,
            eventIDs: happeningIDs,
            stepsProgress: normalizedInput.stepsProgress,
            sleepProgress: normalizedInput.sleepProgress,
            reduceMotion: reduceMotion,
            uiExclusionRegion: uiExclusionRegion
        )
        return .init(
            dayKey: derived.dayKey,
            identity: derived.identity,
            eventIDs: derived.eventIDs,
            motionEnergy: motionEnergyOverride ?? derived.motionEnergy,
            visualClarity: visualClarityOverride ?? derived.visualClarity,
            reduceMotion: derived.reduceMotion,
            uiExclusionRegion: derived.uiExclusionRegion,
            canvasCoverage: canvasCoverage,
            paletteCategories: paletteCategories
        )
    }

    private func updateState(_ mutation: (inout DayObjectsLabMusicState) -> Void) {
        let oldPlan = currentPlan
        var nextState = state
        mutation(&nextState)
        state = nextState
        let nextPlan = Self.makePlan(for: nextState)
        currentPlan = nextPlan
        guard soundState == .on else { return }

        routePlaybackChange(from: oldPlan, to: nextPlan)
    }

    private func routePlaybackChange(from oldPlan: DayMusicPlan, to nextPlan: DayMusicPlan) {
        let change = DayMusicPlanDiffer.change(from: oldPlan, to: nextPlan)
        change.removedHappeningIDs.forEach(playback.removeHappening)
        change.addedHappenings.forEach { playback.addHappening($0, playBirth: true) }
        if let continuous = change.continuousPlan {
            playback.applyContinuous(continuous)
        } else if !change.addedHappenings.isEmpty || !change.removedHappeningIDs.isEmpty {
            // A count-only edit still changes per-voice mix compensation.
            playback.applyContinuous(nextPlan)
        }
        if let structural = change.structuralPlan {
            playback.scheduleStructuralPlan(structural)
        } else if playback.metrics.pendingRemixCount > 0 {
            playback.scheduleStructuralPlan(nextPlan)
        }
    }

    private func stop(includingSampleOnly: Bool = false) async {
        disableDiagnostics()
        if let stopTask {
            await stopTask.value
            return
        }
        guard soundState != .off || includingSampleOnly else { return }
        lifecycleGeneration &+= 1
        soundState = .off
        endLead()
        let id = UUID()
        stopID = id
        let task = Task { @MainActor [playback] in await playback.stop() }
        stopTask = task
        await task.value
        guard stopID == id else { return }
        stopTask = nil
        stopID = nil
    }

    private func auditionHappening(
        _ recipeID: HappeningSoundRecipeID,
        generation: UInt64
    ) async throws {
        guard happeningPadLifecycleIsActive,
              stopTask == nil,
              generation == happeningPadGeneration else { throw CancellationError() }
        guard !unavailableHappeningRecipeIDs.contains(recipeID) else {
            throw HappeningSamplePoolError.recipeUnavailable(recipeID)
        }
        try Task.checkCancellation()
        do {
            try await playback.auditionHappening(recipeID)
            try Task.checkCancellation()
            guard happeningPadLifecycleIsActive,
                  generation == happeningPadGeneration else { throw CancellationError() }
        } catch {
            if Self.isPermanentHappeningFailure(error) {
                unavailableHappeningRecipeIDs.insert(recipeID)
            }
            throw error
        }
    }

    private func finishHappeningPadTask(
        _ recipeID: HappeningSoundRecipeID,
        operationID: UUID
    ) {
        guard happeningPadTasks[recipeID]?.id == operationID else { return }
        happeningPadTasks.removeValue(forKey: recipeID)
        loadingHappeningRecipeIDs.remove(recipeID)
    }

    private func cancelHappeningPadTasks(deactivate: Bool) {
        happeningPadGeneration &+= 1
        if deactivate { happeningPadLifecycleIsActive = false }
        let tasks = happeningPadTasks.values.map(\.task)
        happeningPadTasks.removeAll()
        loadingHappeningRecipeIDs.removeAll()
        tasks.forEach { $0.cancel() }
    }

    private func invalidateDiagnosticActions() {
        diagnosticActionGeneration &+= 1
        diagnosticActionTask?.cancel()
        diagnosticActionTask = nil
    }

    private func activateHappeningPadLifecycle() {
        guard !happeningPadLifecycleIsActive else { return }
        happeningPadGeneration &+= 1
        happeningPadLifecycleIsActive = true
    }

    private static func isPermanentHappeningFailure(_ error: Error) -> Bool {
        switch error {
        case HappeningSamplePoolError.recipeUnavailable,
             HappeningSamplePoolError.resourceUnavailable:
            true
        default:
            false
        }
    }

    private static func makePlan(for state: DayObjectsLabMusicState) -> DayMusicPlan {
        DeterministicMusicDirector.makePlan(
            input: .init(
                countedSteps: state.steps,
                stepGoal: state.stepGoal,
                countedSleepHours: state.sleepHours,
                sleepGoalHours: state.sleepGoalHours,
                happeningIDs: happeningIDs(count: state.happeningCount),
                spentColors: state.spentColors
            ),
            remixSeed: state.remixSeed
        )
    }

    private static func happeningIDs(count: Int) -> [String] {
        guard count > 0 else { return [] }
        return (1...count).map { String(format: "lab-happening-%02d", $0) }
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static let pitchClassNames = [
        "C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B",
    ]

    private static func modeName(_ mode: DayMusicMode) -> String {
        switch mode {
        case .dorian: "Dorian"
        case .aeolian: "Aeolian"
        case .mixolydian: "Mixolydian"
        case .majorPentatonic: "major pentatonic"
        }
    }
}

struct DayObjectsBusMeterRow: Equatable, Sendable {
    let role: DayObjectsRoleBus
    let peakDBFS: Double
    let rmsDBFS: Double
    let activeVoiceCount: Int

    init(role: DayObjectsRoleBus, metrics: DayObjectsRoleBusMetrics) {
        self.role = role
        peakDBFS = metrics.peakDBFS
        rmsDBFS = metrics.rmsDBFS
        activeVoiceCount = metrics.activeVoiceCount
    }
}

struct DayObjectsMasterMeterRow: Equatable, Sendable {
    let peakDBFS: Double
    let rmsDBFS: Double
    let estimatedLimiterReductionDB: Double

    init(peakDBFS: Double, rmsDBFS: Double, estimatedLimiterReductionDB: Double) {
        self.peakDBFS = peakDBFS
        self.rmsDBFS = rmsDBFS
        self.estimatedLimiterReductionDB = estimatedLimiterReductionDB
    }

    init(metrics: DayObjectsMasterMetrics) {
        self.init(
            peakDBFS: metrics.peakDBFS,
            rmsDBFS: metrics.rmsDBFS,
            estimatedLimiterReductionDB: metrics.estimatedLimiterReductionDB
        )
    }
}
#endif
