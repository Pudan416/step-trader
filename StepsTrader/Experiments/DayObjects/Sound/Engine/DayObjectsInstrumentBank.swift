#if DEBUG || INTERNAL_BUILD
import AudioKit
import AudioKitEX
import AudioToolbox
import AVFoundation
import Foundation
import SoundpipeAudioKit

@MainActor
final class DayObjectsInstrumentBank: DayObjectsInstrumentBankProtocol {
    enum PreparationLevel: Equatable, Sendable {
        case sampleOnly(Set<HappeningSoundRecipeID>)
        case fullMusic(DayObjectsInstrumentBankConfiguration)
    }

    typealias TonalInstrumentLoader = () throws -> [DayObjectsInstrumentID: NormalizedSynthVoice]
    typealias TonalPoolFactory = (DayObjectsTonalPoolSpecification, [DayObjectsInstrumentID: NormalizedSynthVoice]) throws -> DayObjectsTonalVoicePoolProtocol
    typealias DrumBankFactory = ([DayObjectsDrumVoice: Int]) throws -> DayObjectsDrumBankProtocol
    typealias PianoPoolFactory = (Int) throws -> DayObjectsPianoPoolProtocol
    typealias HappeningPoolFactory = () -> DayObjectsHappeningSamplePoolProtocol
    typealias GraphFactory = ([DayObjectsTonalVoicePoolProtocol], DayObjectsDrumBankProtocol?, DayObjectsPianoPoolProtocol?, DayObjectsHappeningSamplePoolProtocol) throws -> DayObjectsInstrumentBankGraph

    let descriptors: [DayObjectsInstrumentDescriptor]
    private let descriptorByID: [DayObjectsInstrumentID: DayObjectsInstrumentDescriptor]
    private let tonalInstrumentLoader: TonalInstrumentLoader
    private let tonalPoolFactory: TonalPoolFactory
    private let drumBankFactory: DrumBankFactory
    private let pianoPoolFactory: PianoPoolFactory
    private let happeningPoolFactory: HappeningPoolFactory
    private let graphFactory: GraphFactory
    private let engine: DayObjectsInstrumentBankEngine
    private let inactiveDrums = DayObjectsInactiveDrumBank()
    private let inactivePiano = DayObjectsInactivePianoPool()
    private let inactiveHappenings = DayObjectsInactiveHappeningSamplePool()
    private var prepared: PreparedState?
    private var successfulEngineStartCount = 0
    private var holdsLivePlaybackLease = false
    private var holdsOfflinePlaybackLease = false

    var drums: DayObjectsDrumBankProtocol { prepared?.drums ?? inactiveDrums }
    var piano: DayObjectsPianoPoolProtocol { prepared?.piano ?? inactivePiano }
    var happenings: DayObjectsHappeningSamplePoolProtocol { prepared?.happenings ?? inactiveHappenings }
    var preparationLevel: PreparationLevel? { prepared?.level }
    var outputGainMetrics: DayObjectsBankOutputGainMetrics {
        prepared?.graph.outputGainMetrics ?? .unsupported
    }
    var bassDuckGainMetrics: BassDuckGainMetrics {
        prepared?.graph.bassDuckGainMetrics ?? .unsupported
    }

    var metrics: DayObjectsInstrumentBankMetrics {
        .init(
            state: prepared?.state ?? .unprepared,
            tonalPoolCount: prepared?.tonalPools.count ?? 0,
            graph: prepared?.graph.layout,
            allocationFingerprint: prepared?.graph.allocationFingerprint,
            drumMetrics: drums.metrics,
            pianoMetrics: piano.metrics,
            happeningMetrics: happenings.metrics,
            engineTopology: engine.topologyMetrics,
            engineInstanceCount: 1,
            engineStartCount: successfulEngineStartCount
        )
    }

    init(
        descriptors: [DayObjectsInstrumentDescriptor],
        tonalInstrumentLoader: @escaping TonalInstrumentLoader,
        tonalPoolFactory: @escaping TonalPoolFactory,
        drumBankFactory: @escaping DrumBankFactory,
        pianoPoolFactory: @escaping PianoPoolFactory,
        happeningPoolFactory: @escaping HappeningPoolFactory,
        graphFactory: @escaping GraphFactory,
        engine: DayObjectsInstrumentBankEngine
    ) {
        self.descriptors = descriptors
        descriptorByID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
        self.tonalInstrumentLoader = tonalInstrumentLoader
        self.tonalPoolFactory = tonalPoolFactory
        self.drumBankFactory = drumBankFactory
        self.pianoPoolFactory = pianoPoolFactory
        self.happeningPoolFactory = happeningPoolFactory
        self.graphFactory = graphFactory
        self.engine = engine
    }

    convenience init(
        bundle: Bundle = .main,
        audioHostTimeProvider: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        let happenings = DayObjectsHappeningSamplePool(bundle: bundle)
        self.init(
            bundle: bundle,
            engine: DayObjectsAudioKitInstrumentBankEngine(happenings: happenings),
            happenings: happenings,
            audioHostTimeProvider: audioHostTimeProvider
        )
    }

    private convenience init(
        bundle: Bundle,
        engine: DayObjectsInstrumentBankEngine,
        happenings: DayObjectsHappeningSamplePool,
        audioHostTimeProvider: @escaping () -> TimeInterval
    ) {
        let descriptors = DayObjectsInstrumentManifest.defaultDescriptors
        self.init(
            descriptors: descriptors,
            tonalInstrumentLoader: {
                let records = try DayObjectsInstrumentManifest.loadSynthOneRecords(from: bundle)
                let tonalDescriptors = descriptors.filter { $0.category != .drums && $0.category != .piano }
                return Dictionary(uniqueKeysWithValues: zip(tonalDescriptors, records).map { descriptor, record in
                    (descriptor.id, DayObjectsAudioParameters.clamped(SynthOnePresetAdapter.convert(record).voice))
                })
            },
            tonalPoolFactory: { specification, instruments in
                // The prepared pool is detached and does not start an engine or audio session.
                return DayObjectsAudioKitTonalPoolAdapter(
                    DayObjectsAudioKitTonalPool(
                        specification: specification,
                        instruments: instruments,
                        hostTimeProvider: audioHostTimeProvider
                    )
                )
            },
            drumBankFactory: { overlapCounts in
                DayObjectsAudioKitDrumBankAdapter(.init(resourceResolver: { sample in
                    let filename = sample.rawValue as NSString
                    return bundle.url(forResource: filename.deletingPathExtension, withExtension: filename.pathExtension, subdirectory: "Drums")
                }, recipes: Self.drumRecipes(overlapCounts), hostTimeProvider: audioHostTimeProvider))
            },
            pianoPoolFactory: { requestedCount in
                let samples = try FeltPianoManifest.load(from: bundle)
                let adapter = DayObjectsAudioKitFeltPiano(samples: samples, recipe: Self.pianoRecipe(voiceCount: requestedCount), resourceResolver: { sample in
                    let filename = sample.filename as NSString
                    return bundle.url(forResource: filename.deletingPathExtension, withExtension: filename.pathExtension, subdirectory: "FeltPiano")
                })
                return DayObjectsAudioKitPianoPoolAdapter(adapter)
            },
            happeningPoolFactory: {
                happenings
            },
            graphFactory: { tonalPools, drums, piano, happenings in
                guard let tonalAdapters = tonalPools.compactMap({
                    (($0 as? DayObjectsCategoryValidatedTonalPool)?.pool as? DayObjectsAudioKitTonalPoolAdapter)?.adapter
                }) as [DayObjectsAudioKitTonalPool]?,
                      tonalAdapters.count == tonalPools.count,
                      drums == nil || drums is DayObjectsAudioKitDrumBankAdapter,
                      piano == nil || piano is DayObjectsAudioKitPianoPoolAdapter,
                      happenings is DayObjectsHappeningSamplePool
                else { throw DayObjectsInstrumentBankError.preparationFailed(.graph) }
                return DayObjectsAudioKitInstrumentBankGraph(
                    tonalPools: tonalAdapters,
                    drums: (drums as? DayObjectsAudioKitDrumBankAdapter)?.adapter,
                    piano: (piano as? DayObjectsAudioKitPianoPoolAdapter)?.adapter,
                    outputGainHostTimeProvider: audioHostTimeProvider
                )
            },
            engine: engine
        )
    }

    static func makePlaybackPair(
        bundle: Bundle = .main,
        startFailureProvider: @escaping () -> DayObjectsPlaybackBankPairStartFailure? = { nil },
        individualStartFailureProvider: @escaping () -> Error? = { nil },
        outputGainHostTimeProvider: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) -> DayObjectsPlaybackBankPair {
        let happenings = DayObjectsHappeningSamplePool(bundle: bundle)
        let sharedEngine = DayObjectsSharedInstrumentBankEngine(
            happenings: happenings,
            individualStartFailureProvider: individualStartFailureProvider
        )
        let bankA = DayObjectsInstrumentBank(
            bundle: bundle,
            engine: DayObjectsPairedInstrumentBankEngine(slot: .a, shared: sharedEngine),
            happenings: happenings,
            audioHostTimeProvider: outputGainHostTimeProvider
        )
        let bankB = DayObjectsInstrumentBank(
            bundle: bundle,
            engine: DayObjectsPairedInstrumentBankEngine(slot: .b, shared: sharedEngine),
            happenings: happenings,
            audioHostTimeProvider: outputGainHostTimeProvider
        )
        return DayObjectsPlaybackBankPair(
            bankA: bankA,
            bankB: bankB,
            sharedEngine: sharedEngine,
            startFailureProvider: startFailureProvider
        )
    }

    func prepare(configuration: DayObjectsInstrumentBankConfiguration) throws {
        try prepare(level: .fullMusic(configuration))
    }

    func prepare(level: PreparationLevel) throws {
        switch level {
        case let .sampleOnly(recipeIDs):
            try prepareSamples(recipeIDs)
        case let .fullMusic(configuration):
            try prepareFullMusic(configuration)
        }
    }

    private func prepareSamples(_ recipeIDs: Set<HappeningSoundRecipeID>) throws {
        if var prepared {
            try prepared.happenings.prepare(recipeIDs: recipeIDs)
            if case let .sampleOnly(existingIDs) = prepared.level {
                prepared.level = .sampleOnly(existingIDs.union(recipeIDs))
                self.prepared = prepared
            }
            return
        }

        let builtHappenings = happeningPoolFactory()
        do {
            try builtHappenings.prepare(recipeIDs: recipeIDs)
            let graph = try graphFactory([], nil, nil, builtHappenings)
            try engine.attach(graph: graph)
            prepared = .init(
                level: .sampleOnly(recipeIDs),
                configuration: nil,
                tonalPools: [:],
                drums: inactiveDrums,
                piano: inactivePiano,
                happenings: builtHappenings,
                graph: graph,
                state: .prepared
            )
        } catch let error as DayObjectsInstrumentBankError {
            builtHappenings.releaseAll()
            engine.stop()
            engine.detach()
            throw error
        } catch {
            builtHappenings.releaseAll()
            engine.stop()
            engine.detach()
            throw DayObjectsInstrumentBankError.preparationFailed(.graph)
        }
    }

    private func prepareFullMusic(_ configuration: DayObjectsInstrumentBankConfiguration) throws {
        if let prepared, let existingConfiguration = prepared.configuration {
            guard existingConfiguration == configuration else {
                throw DayObjectsInstrumentBankError.configurationChangedAfterPreparation
            }
            return
        }
        try validate(configuration)

        var builtTonalPools: [DayObjectsTonalVoicePoolProtocol] = []
        var builtDrums: DayObjectsDrumBankProtocol?
        var builtPiano: DayObjectsPianoPoolProtocol?
        let builtHappenings = prepared?.happenings ?? happeningPoolFactory()
        let previousPrepared = prepared
        do {
            try builtHappenings.prepare(recipeIDs: Set(HappeningSoundCatalog.recipes.map(\.id)))
            let instruments: [DayObjectsInstrumentID: NormalizedSynthVoice]
            do { instruments = try tonalInstrumentLoader() }
            catch { throw DayObjectsInstrumentBankError.preparationFailed(.tonalInstruments) }

            for specification in configuration.tonalPools {
                let rawPool: DayObjectsTonalVoicePoolProtocol
                do { rawPool = try tonalPoolFactory(specification, instruments) }
                catch { throw DayObjectsInstrumentBankError.preparationFailed(.tonalPools) }
                builtTonalPools.append(DayObjectsCategoryValidatedTonalPool(
                    pool: rawPool,
                    descriptors: descriptorByID,
                    preparedInstruments: instruments
                ))
            }

            do { builtDrums = try drumBankFactory(configuration.drumOverlapCounts) }
            catch { throw DayObjectsInstrumentBankError.preparationFailed(.drums) }
            do { builtPiano = try pianoPoolFactory(configuration.pianoVoiceCount) }
            catch { throw DayObjectsInstrumentBankError.preparationFailed(.piano) }
            guard let builtDrums, let builtPiano else { throw DayObjectsInstrumentBankError.preparationFailed(.graph) }

            let graph: DayObjectsInstrumentBankGraph
            do { graph = try graphFactory(builtTonalPools, builtDrums, builtPiano, builtHappenings) }
            catch { throw DayObjectsInstrumentBankError.preparationFailed(.graph) }
            do { try engine.attach(graph: graph) }
            catch { throw DayObjectsInstrumentBankError.preparationFailed(.engine) }

            prepared = .init(
                level: .fullMusic(configuration),
                configuration: configuration,
                tonalPools: Dictionary(uniqueKeysWithValues: zip(configuration.tonalPools.map(\.name), builtTonalPools)),
                drums: builtDrums,
                piano: builtPiano,
                happenings: builtHappenings,
                graph: graph,
                state: previousPrepared?.state ?? .prepared
            )
            if previousPrepared != nil { builtHappenings.releaseAll() }
        } catch let error as DayObjectsInstrumentBankError {
            release(builtTonalPools, builtDrums, builtPiano, previousPrepared == nil ? builtHappenings : nil)
            if previousPrepared == nil {
                engine.stop()
                engine.detach()
            }
            throw error
        } catch {
            release(builtTonalPools, builtDrums, builtPiano, previousPrepared == nil ? builtHappenings : nil)
            if previousPrepared == nil {
                engine.stop()
                engine.detach()
            }
            throw DayObjectsInstrumentBankError.preparationFailed(.graph)
        }
    }

    func tonalPool(named id: String) throws -> DayObjectsTonalVoicePoolProtocol {
        guard let prepared else { throw DayObjectsInstrumentBankError.notPrepared }
        guard let pool = prepared.tonalPools[id] else { throw DayObjectsInstrumentBankError.unknownTonalPool(id) }
        return pool
    }

    func start() throws {
        guard let prepared else { throw DayObjectsInstrumentBankError.notPrepared }
        guard prepared.state != .started else { return }
        try acquireLivePlaybackLease()
        do {
            if !prepared.isAttached {
                try engine.attach(graph: prepared.graph)
                self.prepared?.isAttached = true
            }
            try prepared.graph.synchronizeForStart()
            try engine.start()
            successfulEngineStartCount += 1
            self.prepared?.state = .started
        } catch {
            releaseLivePlaybackLease()
            if engine is any DayObjectsPairedInstrumentBankLifecycleGate {
                releaseWorldLocalVoices()
            } else {
                releaseAllIncludingSharedHappenings()
            }
            if engine is any DayObjectsPairedInstrumentBankLifecycleGate {
                self.prepared?.state = .prepared
                self.prepared?.isAttached = true
                throw DayObjectsInstrumentBankError.liveStartFailure(classifying: error)
            }
            engine.stop()
            engine.detach()
            self.prepared = nil
            throw DayObjectsInstrumentBankError.liveStartFailure(classifying: error)
        }
    }

    func stop() async {
        guard prepared?.state == .started else { return }
        if let pairedGate = engine as? any DayObjectsPairedInstrumentBankLifecycleGate {
            switch pairedGate.requestIndividualStop() {
            case .rejected:
                return
            case .worldStopped:
                releaseWorldLocalVoices()
            case .sharedRuntimeStopped:
                releaseAllIncludingSharedHappenings()
            }
            releaseLivePlaybackLease()
            prepared?.state = .prepared
            prepared?.isAttached = true
            return
        }
        releaseAllIncludingSharedHappenings()
        engine.stop()
        releaseLivePlaybackLease()
        if prepared != nil { prepared?.state = .prepared; prepared?.isAttached = true }
    }

    func releaseWorldLocalVoices() {
        guard let prepared else { return }
        prepared.graph.resetBassDuckGain()
        prepared.tonalPools.values.forEach { $0.releaseAll() }
        prepared.drums.releaseAll()
        prepared.piano.releaseAll()
    }

    func releaseAllIncludingSharedHappenings() {
        releaseWorldLocalVoices()
        guard let prepared else { return }
        prepared.happenings.releaseAll()
    }

    func setOutputGain(_ linearGain: Double, rampDurationSeconds: TimeInterval) {
        prepared?.graph.setOutputGain(
            linearGain,
            rampDurationSeconds: rampDurationSeconds
        )
    }

    func scheduleOutputGain(
        _ linearGain: Double,
        startingAtHostTime startHostTime: TimeInterval,
        endingAtHostTime endHostTime: TimeInterval
    ) {
        prepared?.graph.scheduleOutputGain(
            linearGain,
            startingAtHostTime: startHostTime,
            endingAtHostTime: endHostTime
        )
    }

    func scheduleBassDuck(_ command: BassDuckCommand) {
        prepared?.graph.scheduleBassDuck(command)
    }

    func resetBassDuckGain() {
        prepared?.graph.resetBassDuckGain()
    }

    var programEffectMetrics: DayObjectsProgramEffectMetrics {
        prepared?.graph.programEffectMetrics ?? .unsupported
    }

    var diagnosticMeterSnapshot: DayObjectsDiagnosticMeterSnapshot {
        prepared?.graph.diagnosticMeterSnapshot ?? .silent
    }

    func diagnosticMeterSnapshot(atHostTime hostTime: TimeInterval) -> DayObjectsDiagnosticMeterSnapshot {
        prepared?.graph.diagnosticMeterSnapshot(atHostTime: hostTime) ?? .silent
    }

    var offlineLimiterInputPeakDBFS: Double {
        prepared?.graph.offlineLimiterInputPeakDBFS ?? -120
    }

    func applyMix(_ state: DayObjectsMixState) {
        prepared?.graph.applyMix(state)
    }

    func beginOfflineRendering(
        format: AVAudioFormat,
        maximumFrameCount: AVAudioFrameCount
    ) throws {
        guard let prepared else { throw DayObjectsInstrumentBankError.notPrepared }
        guard prepared.state != .started else {
            throw DayObjectsInstrumentBankError.offlineRenderingConflictsWithLivePlayback
        }
        guard !holdsOfflinePlaybackLease else {
            throw DayObjectsInstrumentBankError.offlineRenderingConflictsWithLivePlayback
        }
        try acquireOfflinePlaybackLease()
        do {
            try prepared.graph.synchronizeForStart()
            try engine.beginOfflineRendering(
                format: format,
                maximumFrameCount: maximumFrameCount
            )
        } catch {
            releaseOfflinePlaybackLease()
            throw error
        }
    }

    func renderOffline(
        _ numberOfFrames: AVAudioFrameCount,
        to buffer: AVAudioPCMBuffer
    ) throws -> AVAudioEngineManualRenderingStatus {
        try engine.renderOffline(numberOfFrames, to: buffer)
    }

    func endOfflineRendering() {
        releaseAllIncludingSharedHappenings()
        engine.endOfflineRendering()
        releaseOfflinePlaybackLease()
    }

    fileprivate func acquireLivePlaybackLease() throws {
        guard !holdsLivePlaybackLease else { return }
        try DayObjectsAudioPlaybackLease.shared.acquireLive(owner: self)
        holdsLivePlaybackLease = true
    }

    fileprivate func releaseLivePlaybackLease() {
        guard holdsLivePlaybackLease else { return }
        DayObjectsAudioPlaybackLease.shared.releaseLive(owner: self)
        holdsLivePlaybackLease = false
    }

    private func acquireOfflinePlaybackLease() throws {
        try DayObjectsAudioPlaybackLease.shared.acquireOffline(owner: self)
        holdsOfflinePlaybackLease = true
    }

    private func releaseOfflinePlaybackLease() {
        guard holdsOfflinePlaybackLease else { return }
        DayObjectsAudioPlaybackLease.shared.releaseOffline(owner: self)
        holdsOfflinePlaybackLease = false
    }

    fileprivate func synchronizePreparedGraphForPlaybackPair() throws {
        guard let prepared else { throw DayObjectsInstrumentBankError.notPrepared }
        try prepared.graph.synchronizeForStart()
    }

    fileprivate func markPlaybackPairPrepared() {
        guard prepared != nil else { return }
        prepared?.state = .prepared
        prepared?.isAttached = true
    }

    fileprivate func markPlaybackPairStarted() {
        guard prepared != nil else { return }
        prepared?.state = .started
        prepared?.isAttached = true
    }

    private func validate(_ configuration: DayObjectsInstrumentBankConfiguration) throws {
        var seen = Set<String>()
        for name in configuration.tonalPools.map(\.name) where !seen.insert(name).inserted {
            throw DayObjectsInstrumentBankError.duplicateTonalPoolName(name)
        }
        guard (1...8).contains(configuration.pianoVoiceCount) else { throw DayObjectsInstrumentBankError.invalidPianoVoiceCount }
        if let invalid = configuration.drumOverlapCounts.filter({ !(1...8).contains($0.value) }).map(\.key).sorted(by: { $0.rawValue < $1.rawValue }).first {
            throw DayObjectsInstrumentBankError.invalidDrumOverlap(invalid)
        }
    }

    private func release(
        _ tonalPools: [DayObjectsTonalVoicePoolProtocol],
        _ drums: DayObjectsDrumBankProtocol?,
        _ piano: DayObjectsPianoPoolProtocol?,
        _ happenings: DayObjectsHappeningSamplePoolProtocol? = nil
    ) {
        tonalPools.forEach { $0.releaseAll() }
        drums?.releaseAll()
        piano?.releaseAll()
        happenings?.releaseAll()
    }

    private struct PreparedState {
        var level: PreparationLevel
        let configuration: DayObjectsInstrumentBankConfiguration?
        let tonalPools: [String: DayObjectsTonalVoicePoolProtocol]
        let drums: DayObjectsDrumBankProtocol
        let piano: DayObjectsPianoPoolProtocol
        let happenings: DayObjectsHappeningSamplePoolProtocol
        let graph: DayObjectsInstrumentBankGraph
        var state: DayObjectsInstrumentBankState
        var isAttached: Bool = true
    }

    private static func drumRecipes(_ requested: [DayObjectsDrumVoice: Int]) -> [DayObjectsDrumVoice: DayObjectsDrumRecipe] {
        Dictionary(uniqueKeysWithValues: DayObjectsDrumVoice.allCases.map { voice in
            let base = DayObjectsDrumRecipe.recipe(for: voice)
            let overlap = requested[voice] ?? base.overlapCount
            return (voice, .init(voice: base.voice, primarySample: base.primarySample, fallbackSample: base.fallbackSample, synthesis: base.synthesis, sinePitchDrop: base.sinePitchDrop, noiseAmplitude: base.noiseAmplitude, overlapCount: overlap, transientFilterCutoffHz: base.transientFilterCutoffHz, noiseFilterCutoffHz: base.noiseFilterCutoffHz, highPassCutoffHz: base.highPassCutoffHz, outputTrimDecibels: base.outputTrimDecibels, variation: base.variation, allowsPitchDrift: base.allowsPitchDrift, allowsBroadbandSustainedNoise: base.allowsBroadbandSustainedNoise, usesSawOscillator: base.usesSawOscillator, delayFeedback: base.delayFeedback))
        })
    }

    private static func pianoRecipe(voiceCount: Int) -> DayObjectsFeltPianoRecipe {
        let base = DayObjectsFeltPianoRecipe.default
        return .init(attackSeconds: base.attackSeconds, releaseSeconds: base.releaseSeconds, lowPassCutoffHz: base.lowPassCutoffHz, mechanicalOnsetHighPassHz: base.mechanicalOnsetHighPassHz, mechanicalNoiseGain: base.mechanicalNoiseGain, noteTrimDB: base.noteTrimDB, roomSend: base.roomSend, reverbSend: base.reverbSend, maximumPolyphony: voiceCount)
    }
}

private final class DayObjectsCategoryValidatedTonalPool: DayObjectsTonalVoicePoolProtocol {
    let pool: DayObjectsTonalVoicePoolProtocol
    let descriptors: [DayObjectsInstrumentID: DayObjectsInstrumentDescriptor]
    let preparedInstruments: [DayObjectsInstrumentID: NormalizedSynthVoice]

    init(pool: DayObjectsTonalVoicePoolProtocol, descriptors: [DayObjectsInstrumentID: DayObjectsInstrumentDescriptor], preparedInstruments: [DayObjectsInstrumentID: NormalizedSynthVoice]) {
        self.pool = pool
        self.descriptors = descriptors
        self.preparedInstruments = preparedInstruments
    }

    var metrics: DayObjectsTonalPoolMetrics { pool.metrics }

    func prepareInstrument(_ id: DayObjectsInstrumentID) throws {
        guard let descriptor = descriptors[id] else { throw DayObjectsInstrumentBankError.unknownInstrument(id) }
        guard descriptor.category != .drums, descriptor.category != .piano else {
            throw DayObjectsInstrumentBankError.invalidTonalInstrumentCategory(descriptor.category)
        }
        guard preparedInstruments[id] != nil else { throw DayObjectsInstrumentBankError.unknownInstrument(id) }
        try pool.prepareInstrument(id)
    }

    func prepareInstruments(_ ids: [DayObjectsInstrumentID]) throws {
        for id in ids {
            guard let descriptor = descriptors[id] else { throw DayObjectsInstrumentBankError.unknownInstrument(id) }
            guard descriptor.category != .drums, descriptor.category != .piano else {
                throw DayObjectsInstrumentBankError.invalidTonalInstrumentCategory(descriptor.category)
            }
            guard preparedInstruments[id] != nil else { throw DayObjectsInstrumentBankError.unknownInstrument(id) }
        }
        try pool.prepareInstruments(ids)
    }

    func noteOn(_ request: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken? {
        guard let descriptor = descriptors[request.instrumentID], descriptor.category != .drums, descriptor.category != .piano, preparedInstruments[request.instrumentID] != nil else { return nil }
        return pool.noteOn(request)
    }
    func noteOn(
        _ request: DayObjectsTonalNoteRequest,
        atHostTime hostTime: TimeInterval
    ) -> DayObjectsVoiceToken? {
        guard let descriptor = descriptors[request.instrumentID], descriptor.category != .drums, descriptor.category != .piano, preparedInstruments[request.instrumentID] != nil else { return nil }
        return pool.noteOn(request, atHostTime: hostTime)
    }
    func update(_ token: DayObjectsVoiceToken, with update: DayObjectsVoiceUpdate) { pool.update(token, with: update) }
    func noteOff(_ token: DayObjectsVoiceToken) { pool.noteOff(token) }
    func releaseAll() { pool.releaseAll() }
}

private final class DayObjectsInactiveDrumBank: DayObjectsDrumBankProtocol {
    var metrics: DayObjectsDrumBankMetrics { .init(allocatedPlayerCount: 0, enabledVoiceCount: 0) }
    func hit(_ voice: DayObjectsDrumVoice, velocity: Double) {}
    func releaseAll() {}
}

private final class DayObjectsInactivePianoPool: DayObjectsPianoPoolProtocol {
    var metrics: DayObjectsFeltPianoMetrics { .init(allocatedPlayerCount: 0, activeNoteCount: 0, maximumPolyphony: 0) }
    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken? { nil }
    func noteOff(_ token: DayObjectsFeltPianoToken) {}
    func releaseAll() {}
}

private final class DayObjectsAudioKitTonalPoolAdapter: DayObjectsTonalVoicePoolProtocol {
    let adapter: DayObjectsAudioKitTonalPool
    init(_ adapter: DayObjectsAudioKitTonalPool) { self.adapter = adapter }
    var metrics: DayObjectsTonalPoolMetrics { adapter.pool.metrics }
    func prepareInstrument(_ id: DayObjectsInstrumentID) throws { try adapter.pool.prepareInstrument(id) }
    func prepareInstruments(_ ids: [DayObjectsInstrumentID]) throws { try adapter.pool.prepareInstruments(ids) }
    func noteOn(_ request: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken? { adapter.pool.noteOn(request) }
    func noteOn(
        _ request: DayObjectsTonalNoteRequest,
        atHostTime hostTime: TimeInterval
    ) -> DayObjectsVoiceToken? {
        adapter.pool.noteOn(request, atHostTime: hostTime)
    }
    func update(_ token: DayObjectsVoiceToken, with update: DayObjectsVoiceUpdate) { adapter.pool.update(token, with: update) }
    func noteOff(_ token: DayObjectsVoiceToken) { adapter.pool.noteOff(token) }
    func releaseAll() { adapter.pool.releaseAll() }
}

private final class DayObjectsAudioKitDrumBankAdapter: DayObjectsDrumBankProtocol {
    let adapter: DayObjectsAudioKitDrumBank
    init(_ adapter: DayObjectsAudioKitDrumBank) { self.adapter = adapter }
    var metrics: DayObjectsDrumBankMetrics { adapter.bank.metrics }
    func hit(_ voice: DayObjectsDrumVoice, velocity: Double) { adapter.bank.hit(voice, velocity: velocity) }
    func schedule(_ hit: DayObjectsScheduledDrumHit) { adapter.bank.schedule(hit) }
    func releaseAll() { adapter.releaseAll() }
}

private final class DayObjectsAudioKitPianoPoolAdapter: DayObjectsPianoPoolProtocol {
    let adapter: DayObjectsAudioKitFeltPiano
    init(_ adapter: DayObjectsAudioKitFeltPiano) { self.adapter = adapter }
    var metrics: DayObjectsFeltPianoMetrics { adapter.piano.metrics }
    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken? { adapter.piano.noteOn(midiNote, velocity: velocity) }
    func noteOn(_ request: DayObjectsPianoNoteRequest) -> DayObjectsFeltPianoToken? {
        adapter.room.dryWetMix = AUValue(min(max(request.roomSend, 0), 1))
        adapter.reverb.dryWetMix = AUValue(min(max(request.reverbSend, 0), 1))
        return adapter.piano.noteOn(request)
    }
    func updateExpression(_ token: DayObjectsFeltPianoToken, expression: Double) {
        adapter.piano.updateExpression(token, expression: expression)
    }
    func update(_ token: DayObjectsFeltPianoToken, with update: DayObjectsPianoVoiceUpdate) {
        adapter.update(token, with: update)
    }
    func noteOff(_ token: DayObjectsFeltPianoToken) { _ = adapter.piano.noteOff(token) }
    func releaseAll() { adapter.piano.stop() }
}

final class DayObjectsAudioKitInstrumentBankGraph: DayObjectsInstrumentBankGraph {
    var layout: DayObjectsInstrumentBankGraphLayout {
        .init(
            tonalBusCount: 3,
            drumBusCount: 1,
            sharedSpatialEffectCount: 0,
            tonalBusGainDB: 0,
            drumBusGainDB: 0,
            masterTrimDB: 0,
            finalPeakLimiterCount: 0,
            roleBuses: [.rhythm, .bass, .harmony, .lead],
            parallelSpatialReturnCount: 0
        )
    }
    let rhythmBus: Mixer
    let bassBus: Mixer
    let harmonyBus: Mixer
    let leadBus: Mixer
    let rhythmWorldTrim: Fader
    let bassWorldTrim: Fader
    let harmonyWorldTrim: Fader
    let leadWorldTrim: Fader
    private let worldTrims: [Fader]
    /// A preallocated, world-local duck stage fed by the completed Bass tone
    /// chain and placed before the world's direct/spatial role output split.
    let bassTrim: Fader?
    private let bassHighPass: HighPassFilter?
    private let bassLowBand: LowPassFilter?
    private let bassLowBandMono: Fader?
    private let bassHighBand: HighPassFilter?
    private let bassHighBandSlope: HighPassFilter?
    private let bassRecombine: Mixer?
    private let bassSaturation: TanhDistortion?
    private let tonalPools: [DayObjectsAudioKitTonalPool]
    private let drums: DayObjectsAudioKitDrumBank?
    private let piano: DayObjectsAudioKitFeltPiano?
    private var outputGainTarget = 1.0
    private var outputGainRampDuration: TimeInterval = 0
    private var outputGainRampCount = 0
    private var lastScheduledOutputGainAutomation: DayObjectsBankOutputGainAutomation?
    private var bassDuckScheduledSegmentCount = 0
    private var bassDuckResetCount = 0
    private var bassDuckEnvelopeClearedForReuse = true
    private var lastBassDuckAttack: BassDuckGainAutomation?
    private var lastBassDuckHold: BassDuckGainAutomation?
    private var lastBassDuckRelease: BassDuckGainAutomation?
    private let outputGainHostTimeProvider: () -> TimeInterval
    private let outputGainSampleRateProvider: () -> Double
    private var currentProgramEffectMetrics = DayObjectsProgramEffectMetrics.unsupported
    private weak var persistentMaster: DayObjectsPersistentMasterGraph?

    var programEffectMetrics: DayObjectsProgramEffectMetrics { currentProgramEffectMetrics }

    var diagnosticMeterSnapshot: DayObjectsDiagnosticMeterSnapshot {
        guard let persistentMaster else { return .silent }
        let snapshots = persistentMaster.meterSnapshots(graphs: [self])
        return .init(roleBusMetrics: snapshots.0, masterMetrics: snapshots.1)
    }

    func diagnosticMeterSnapshot(atHostTime hostTime: TimeInterval) -> DayObjectsDiagnosticMeterSnapshot {
        guard let persistentMaster else { return .silent }
        let snapshots = persistentMaster.meterSnapshots(graphs: [self], now: hostTime)
        return .init(roleBusMetrics: snapshots.0, masterMetrics: snapshots.1)
    }

    var offlineLimiterInputPeakDBFS: Double {
        persistentMaster?.offlineLimiterInputPeakDBFS ?? -120
    }

    var outputGainMetrics: DayObjectsBankOutputGainMetrics {
        .init(
            isSupported: true,
            targetLinearGain: outputGainTarget,
            lastRampDurationSeconds: outputGainRampDuration,
            rampCount: outputGainRampCount,
            lastScheduledAutomation: lastScheduledOutputGainAutomation,
            affectedRoles: [.rhythm, .bass, .harmony, .lead]
        )
    }

    var bassDuckGainMetrics: BassDuckGainMetrics {
        guard bassTrim != nil else { return .unsupported }
        return .init(
            isSupported: true,
            scheduledSegmentCount: bassDuckScheduledSegmentCount,
            resetCount: bassDuckResetCount,
            isEnvelopeClearedForReuse: bassDuckEnvelopeClearedForReuse,
            lastAttack: lastBassDuckAttack,
            lastHold: lastBassDuckHold,
            lastRelease: lastBassDuckRelease
        )
    }

    var allocationFingerprint: DayObjectsInstrumentBankAllocationFingerprint {
        let drumMetrics = drums?.metrics
        let pianoMetrics = piano?.metrics
        return .init(
            tonalNodeIdentities: tonalPools.flatMap(\.voiceNodeIdentities),
            drumPreloadedSampleCount: drumMetrics?.preloadedSampleCount ?? 0,
            drumAllocatedNodeCount: drumMetrics?.allocatedNodeCount ?? 0,
            drumFixedPlayerCount: drumMetrics?.fixedPlayerCount ?? 0,
            pianoPreloadedSampleCount: pianoMetrics?.preloadedSampleCount ?? 0,
            pianoLoadedPlayerCount: pianoMetrics?.loadedPlayerCount ?? 0,
            pianoFixedBackendCount: pianoMetrics?.fixedBackendCount ?? 0
        )
    }

    var fixedLocalNodes: [Node] {
        var nodes: [Node] = [
            rhythmBus, bassBus, harmonyBus, leadBus,
            rhythmWorldTrim, bassWorldTrim, harmonyWorldTrim, leadWorldTrim,
        ]
        let bassNodes: [Node?] = [
            bassHighPass, bassLowBand, bassLowBandMono, bassHighBand, bassHighBandSlope,
            bassRecombine, bassSaturation, bassTrim,
        ]
        nodes.append(contentsOf: bassNodes.compactMap { $0 })
        return nodes
    }

    var bassNamedNodes: [String: Node] {
        var result: [String: Node] = [:]
        if let bassPool = tonalPools.first(where: {
            $0.name == PlaybackWorldBankConfiguration.PoolName.bass.rawValue
        }) { result["source"] = bassPool.output }
        result["highPass27"] = bassHighPass
        result["lowPass140"] = bassLowBand
        result["lowBandMono"] = bassLowBandMono
        result["highPass140"] = bassHighBand
        result["highPass140Slope"] = bassHighBandSlope
        result["recombine"] = bassRecombine
        result["saturation"] = bassSaturation
        result["duck"] = bassTrim
        result["worldBassBus"] = bassBus
        result["worldBassTrim"] = bassWorldTrim
        return result
    }

    fileprivate init(
        tonalPools: [DayObjectsAudioKitTonalPool],
        drums: DayObjectsAudioKitDrumBank?,
        piano: DayObjectsAudioKitFeltPiano?,
        outputGainHostTimeProvider: @escaping () -> TimeInterval,
        outputGainSampleRateProvider: @escaping () -> Double = {
            let rate = AVAudioSession.sharedInstance().sampleRate
            return rate > 0 ? rate : 48_000
        }
    ) {
        self.tonalPools = tonalPools
        self.drums = drums
        self.piano = piano
        self.outputGainHostTimeProvider = outputGainHostTimeProvider
        self.outputGainSampleRateProvider = outputGainSampleRateProvider
        let bassPool = tonalPools.first(where: {
            $0.name == PlaybackWorldBankConfiguration.PoolName.bass.rawValue
        })
        let preparedBassHighPass = bassPool.map { HighPassFilter($0.output, cutoffFrequency: 27, resonance: 0) }
        let preparedBassLowBand = preparedBassHighPass.map { LowPassFilter($0, cutoffFrequency: 140, resonance: 0) }
        let preparedBassLowBandMono = preparedBassLowBand.map { lowBand -> Fader in
            let mono = Fader(lowBand, gain: 1)
            mono.$mixToMono.parameter.value = 1
            return mono
        }
        let preparedBassHighBand = preparedBassHighPass.map { HighPassFilter($0, cutoffFrequency: 140, resonance: 0) }
        let preparedBassHighBandSlope = preparedBassHighBand.map { HighPassFilter($0, cutoffFrequency: 140, resonance: 0) }
        let preparedBassRecombine: Mixer? = {
            guard let low = preparedBassLowBandMono, let high = preparedBassHighBandSlope else { return nil }
            return Mixer([low, high], name: "Day Objects world bass crossover recombine")
        }()
        let preparedBassSaturation = preparedBassRecombine.map {
            TanhDistortion(
                $0, pregain: 1.18, postgain: 0.94,
                positiveShapeParameter: 0, negativeShapeParameter: 0,
                dryWetMix: 0.12
            )
        }
        let preparedBassTrim = preparedBassSaturation.map { Fader($0, gain: 1) }
        bassHighPass = preparedBassHighPass
        bassLowBand = preparedBassLowBand
        bassLowBandMono = preparedBassLowBandMono
        bassHighBand = preparedBassHighBand
        bassHighBandSlope = preparedBassHighBandSlope
        bassRecombine = preparedBassRecombine
        bassSaturation = preparedBassSaturation
        bassTrim = preparedBassTrim
        var harmonyInputs: [Node] = []
        var leadInputs: [Node] = []
        for pool in tonalPools {
            switch pool.name {
            case PlaybackWorldBankConfiguration.PoolName.bass.rawValue:
                break
            case PlaybackWorldBankConfiguration.PoolName.lead.rawValue:
                leadInputs.append(pool.output)
            default:
                harmonyInputs.append(pool.output)
            }
        }
        if let piano { harmonyInputs.append(piano.output) }
        rhythmBus = Mixer(drums.map { [$0.output] } ?? [], name: "Day Objects world rhythm output")
        bassBus = Mixer(preparedBassTrim.map { [$0] } ?? [], name: "Day Objects world bass output")
        harmonyBus = Mixer(harmonyInputs, name: "Day Objects world harmony output")
        leadBus = Mixer(leadInputs, name: "Day Objects world lead output")
        rhythmWorldTrim = Fader(rhythmBus, gain: 1)
        bassWorldTrim = Fader(bassBus, gain: 1)
        harmonyWorldTrim = Fader(harmonyBus, gain: 1)
        leadWorldTrim = Fader(leadBus, gain: 1)
        worldTrims = [rhythmWorldTrim, bassWorldTrim, harmonyWorldTrim, leadWorldTrim]
    }

    func bind(to persistentMaster: DayObjectsPersistentMasterGraph) {
        self.persistentMaster = persistentMaster
    }

    func output(for role: DayObjectsRoleBus) -> Node? {
        switch role {
        case .rhythm: rhythmWorldTrim
        case .bass: bassWorldTrim
        case .harmony: harmonyWorldTrim
        case .happenings: nil
        case .lead: leadWorldTrim
        }
    }

    func activeVoiceCount(for role: DayObjectsRoleBus) -> Int {
        switch role {
        case .rhythm:
            drums?.bank.metrics.activePlayerCount ?? 0
        case .happenings:
            0
        case .bass:
            tonalPools.first { $0.name == PlaybackWorldBankConfiguration.PoolName.bass.rawValue }?.pool.metrics.activeVoiceCount ?? 0
        case .harmony:
            tonalPools.filter {
                $0.name != PlaybackWorldBankConfiguration.PoolName.bass.rawValue
                    && $0.name != PlaybackWorldBankConfiguration.PoolName.lead.rawValue
            }.reduce(piano?.piano.metrics.activeNoteCount ?? 0) { $0 + $1.pool.metrics.activeVoiceCount }
        case .lead:
            tonalPools.first { $0.name == PlaybackWorldBankConfiguration.PoolName.lead.rawValue }?.pool.metrics.activeVoiceCount ?? 0
        }
    }

    func applyMix(_ state: DayObjectsMixState) {
        currentProgramEffectMetrics = .init(isSupported: true, state: state)
        persistentMaster?.applyMix(state)
    }

    func setOutputGain(_ linearGain: Double, rampDurationSeconds: TimeInterval) {
        let target = min(max(linearGain.isFinite ? linearGain : 0, 0), 1)
        let duration = max(rampDurationSeconds.isFinite ? rampDurationSeconds : 0, 0)
        outputGainTarget = target
        outputGainRampDuration = duration
        outputGainRampCount += 1
        lastScheduledOutputGainAutomation = nil
        for trim in worldTrims {
            trim.$leftGain.ramp(to: AUValue(target), duration: Float(duration))
            trim.$rightGain.ramp(to: AUValue(target), duration: Float(duration))
        }
    }

    func scheduleOutputGain(
        _ linearGain: Double,
        startingAtHostTime startHostTime: TimeInterval,
        endingAtHostTime endHostTime: TimeInterval
    ) {
        let target = min(max(linearGain.isFinite ? linearGain : 0, 0), 1)
        let nowValue = outputGainHostTimeProvider()
        let now = nowValue.isFinite ? nowValue : 0
        let requestedStart = startHostTime.isFinite ? startHostTime : now
        let requestedEndValue = endHostTime.isFinite ? endHostTime : requestedStart
        let requestedEnd = max(requestedEndValue, requestedStart)
        let wasForcedImmediate = requestedEnd <= now
        let effectiveStart = wasForcedImmediate ? now : max(requestedStart, now)
        let effectiveEnd = wasForcedImmediate ? now : max(requestedEnd, effectiveStart)

        let automation = DayObjectsBankOutputGainAutomation(
            targetLinearGain: target,
            requestedStartHostTimeSeconds: requestedStart,
            requestedEndHostTimeSeconds: requestedEnd,
            effectiveStartHostTimeSeconds: effectiveStart,
            effectiveEndHostTimeSeconds: effectiveEnd,
            wasForcedImmediate: wasForcedImmediate
        )
        outputGainTarget = target
        outputGainRampDuration = effectiveEnd - effectiveStart
        outputGainRampCount += 1
        lastScheduledOutputGainAutomation = automation

        if wasForcedImmediate {
            for trim in worldTrims {
                trim.$leftGain.parameter.value = AUValue(target)
                trim.$rightGain.parameter.value = AUValue(target)
            }
            return
        }

        for trim in worldTrims {
            schedule(trim.$leftGain, target: AUValue(target), startingAtHostTime: effectiveStart, endingAtHostTime: effectiveEnd, now: now)
            schedule(trim.$rightGain, target: AUValue(target), startingAtHostTime: effectiveStart, endingAtHostTime: effectiveEnd, now: now)
        }
    }

    func scheduleBassDuck(_ command: BassDuckCommand) {
        guard let bassTrim else { return }
        let attenuation = min(max(command.maximumAttenuationDecibels.isFinite ? command.maximumAttenuationDecibels : 0, 0), 5)
        let duckedGain = Self.linearGain(decibels: -attenuation)
        let attackStart = command.hostTimeSeconds.isFinite ? command.hostTimeSeconds : outputGainHostTimeProvider()
        let attackEnd = attackStart + max(command.attackSeconds.isFinite ? command.attackSeconds : 0, 0)
        let holdEnd = attackEnd + max(command.holdSeconds.isFinite ? command.holdSeconds : 0, 0)
        let releaseEnd = holdEnd + max(command.releaseSeconds.isFinite ? command.releaseSeconds : 0, 0)
        let nowValue = outputGainHostTimeProvider()
        let now = nowValue.isFinite ? nowValue : 0

        lastBassDuckAttack = scheduleBassGain(
            bassTrim,
            stage: .attack,
            target: duckedGain,
            requestedStart: attackStart,
            requestedEnd: attackEnd,
            now: now
        )
        lastBassDuckHold = scheduleBassGain(
            bassTrim,
            stage: .hold,
            target: duckedGain,
            requestedStart: attackEnd,
            requestedEnd: holdEnd,
            now: now
        )
        lastBassDuckRelease = scheduleBassGain(
            bassTrim,
            stage: .release,
            target: 1,
            requestedStart: holdEnd,
            requestedEnd: releaseEnd,
            now: now
        )
        bassDuckScheduledSegmentCount += 3
        bassDuckEnvelopeClearedForReuse = false
    }

    func resetBassDuckGain() {
        guard let bassTrim else { return }
        // Reset clears queued AU parameter events before returning this fixed
        // world-local trim to unity for a stop, reconfiguration, or reuse.
        bassTrim.avAudioNode.auAudioUnit.reset()
        bassTrim.$leftGain.parameter.value = 1
        bassTrim.$rightGain.parameter.value = 1
        bassDuckResetCount += 1
        bassDuckEnvelopeClearedForReuse = true
        lastBassDuckAttack = nil
        lastBassDuckHold = nil
        lastBassDuckRelease = nil
    }

    func synchronizeForStart() throws {
        tonalPools.forEach { $0.synchronizeGraphIfAttached() }
        if let highPass = bassHighPass {
            setImmediately(highPass.$cutoffFrequency, to: 27)
            setImmediately(highPass.$resonance, to: 0)
        }
        if let lowBand = bassLowBand {
            setImmediately(lowBand.$cutoffFrequency, to: 140)
            setImmediately(lowBand.$resonance, to: 0)
        }
        if let mono = bassLowBandMono {
            setImmediately(mono.$mixToMono, to: 1)
        }
        for highBand in [bassHighBand, bassHighBandSlope].compactMap({ $0 }) {
            setImmediately(highBand.$cutoffFrequency, to: 140)
            setImmediately(highBand.$resonance, to: 0)
        }
        if let saturation = bassSaturation {
            setImmediately(saturation.$pregain, to: 1.18)
            setImmediately(saturation.$postgain, to: 0.94)
            setImmediately(saturation.$positiveShapeParameter, to: 0)
            setImmediately(saturation.$negativeShapeParameter, to: 0)
            setImmediately(saturation.$dryWetMix, to: 0.12)
        }
    }

    private static func decibels(_ gain: AUValue) -> Double { 20 * log10(Double(gain)) }
    private static func linearGain(decibels: Double) -> Double { pow(10, decibels / 20) }

    private func schedule(
        _ parameter: NodeParameter,
        target: AUValue,
        startingAtHostTime startHostTime: TimeInterval,
        endingAtHostTime endHostTime: TimeInterval,
        now: TimeInterval
    ) {
        let sampleRate = max(outputGainSampleRateProvider(), 1)
        let startOffset = max(startHostTime - now, 0) * sampleRate
        let duration = max(endHostTime - startHostTime, 0) * sampleRate
        let maximumFrameCount = Double(AUAudioFrameCount.max)
        parameter.avAudioNode.auAudioUnit.scheduleParameterBlock(
            AUEventSampleTimeImmediate + AUEventSampleTime(min(startOffset, Double(Int64.max))),
            AUAudioFrameCount(min(duration, maximumFrameCount)),
            parameter.parameter.address,
            target
        )
    }

    private func setImmediately(_ parameter: NodeParameter, to value: AUValue) {
        parameter.avAudioNode.auAudioUnit.scheduleParameterBlock(
            AUEventSampleTimeImmediate,
            0,
            parameter.parameter.address,
            min(max(value, parameter.range.lowerBound), parameter.range.upperBound)
        )
    }

    private func scheduleBassGain(
        _ trim: Fader,
        stage: BassDuckGainStage,
        target: Double,
        requestedStart: TimeInterval,
        requestedEnd: TimeInterval,
        now: TimeInterval
    ) -> BassDuckGainAutomation {
        let safeStart = requestedStart.isFinite ? requestedStart : now
        let safeEnd = max(requestedEnd.isFinite ? requestedEnd : safeStart, safeStart)
        let wasForcedImmediate = safeEnd <= now
        let effectiveStart = wasForcedImmediate ? now : max(safeStart, now)
        let effectiveEnd = wasForcedImmediate ? now : max(safeEnd, effectiveStart)
        let automation = BassDuckGainAutomation(
            stage: stage,
            targetLinearGain: target,
            requestedStartHostTimeSeconds: safeStart,
            requestedEndHostTimeSeconds: safeEnd,
            effectiveStartHostTimeSeconds: effectiveStart,
            effectiveEndHostTimeSeconds: effectiveEnd,
            wasForcedImmediate: wasForcedImmediate
        )
        if wasForcedImmediate {
            trim.$leftGain.parameter.value = AUValue(target)
            trim.$rightGain.parameter.value = AUValue(target)
        } else {
            schedule(trim.$leftGain, target: AUValue(target), startingAtHostTime: effectiveStart, endingAtHostTime: effectiveEnd, now: now)
            schedule(trim.$rightGain, target: AUValue(target), startingAtHostTime: effectiveStart, endingAtHostTime: effectiveEnd, now: now)
        }
        return automation
    }
}

final class DayObjectsMasterOutputGainNode: Node {
    let input: Node
    var connections: [Node] { [input] }
    let avAudioNode: AVAudioNode
    private let mixer = AVAudioMixerNode()
    private let configuredLinearGain: Float
    var linearGain: Float { mixer.outputVolume }

    init(input: Node, decibels: Double) {
        self.input = input
        avAudioNode = mixer
        let bounded = min(max(decibels.isFinite ? decibels : -120, -120), 0)
        configuredLinearGain = Float(pow(10, bounded / 20))
        applyConfiguredGain()
    }

    func applyConfiguredGain() {
        mixer.outputVolume = configuredLinearGain
    }
}

@MainActor
final class DayObjectsPersistentMasterGraph {
    static let masterTrimDecibels = -6.0
    /// Measured path calibration keeps the published and physical master trim
    /// identical while bringing every role's direct and spatial paths into the
    /// production loudness window.
    static let rhythmPathCalibrationDecibels = 10.40
    static let bassPathCalibrationDecibels = 10.40
    static let harmonyPathCalibrationDecibels = 10.40
    static let happeningsPathCalibrationDecibels = 10.40
    static let leadPathCalibrationDecibels = 10.40
    static let masterHighPassHz = 22.0
    static let glueRatio = 1.5
    static let nominalMaximumGlueReductionDB = 1.5
    static let limiterCeilingDBFS = -1.35
    private static let rhythmReturnSendCalibration = 8.0
    private static let harmonyReturnSendCalibration = 2.0
    private static let happeningsReturnSendCalibration = 3.4
    private static let maximumCalibratedReturnGain = 12.0
    private static let silentRoleMetrics = DayObjectsFiveRoleBusMetrics(
        rhythm: .init(peakDBFS: -120, rmsDBFS: -120, activeVoiceCount: 0),
        bass: .init(peakDBFS: -120, rmsDBFS: -120, activeVoiceCount: 0),
        harmony: .init(peakDBFS: -120, rmsDBFS: -120, activeVoiceCount: 0),
        happenings: .init(peakDBFS: -120, rmsDBFS: -120, activeVoiceCount: 0),
        lead: .init(peakDBFS: -120, rmsDBFS: -120, activeVoiceCount: 0)
    )

    let rhythmBus = Mixer(name: "Day Objects rhythm bus")
    let bassBus = Mixer(name: "Day Objects bass bus")
    let harmonyBus = Mixer(name: "Day Objects harmony bus")
    let happeningsBus: Mixer
    let leadBus = Mixer(name: "Day Objects lead bus")

    let rhythmCompressor: DynamicRangeCompressor
    let harmonyHighPass: HighPassFilter
    let leadUpperMidSoftener: PeakingParametricEqualizerFilter
    let leadUpperMidBand: BandPassFilter
    let leadUpperMidCompressor: DynamicsProcessor
    let leadUpperMidBlend: Fader
    let leadToneMixer: Mixer

    let rhythmDirect: Fader
    let bassDirect: Fader
    let harmonyDirect: Fader
    let happeningsDirect: Fader
    let leadDirect: Fader

    let rhythmSend: Fader
    let rhythmReturnLowCut: HighPassFilter
    let rhythmRoomReturn: CostelloReverb
    let bassSend: Fader
    let bassReturnLowCut: HighPassFilter
    let bassShortReturn: CostelloReverb
    let harmonySend: Fader
    let harmonyReturnLowCut: HighPassFilter
    let harmonyHallReturn: CostelloReverb
    let happeningsSend: Fader
    let happeningsReturnLowCut: HighPassFilter
    let happeningsCathedralReturn: CostelloReverb
    let leadSend: Fader
    let leadDelaySend: Fader
    let leadReturnLowCut: HighPassFilter
    let leadDelayReturnLowCut: HighPassFilter
    let leadDelayReturn: VariableDelay
    let leadReverbReturn: CostelloReverb

    let masterMixer: Mixer
    let masterHighPass: HighPassFilter
    let glueCompressor: DynamicRangeCompressor
    let masterSaturation: TanhDistortion
    let masterTrim: Fader
    let limiter: PeakLimiter
    let finalOutput: DayObjectsMasterOutputGainNode

    private let rhythmMeter = DayObjectsBusMeter()
    private let bassMeter = DayObjectsBusMeter()
    private let harmonyMeter = DayObjectsBusMeter()
    private let happeningsMeter = DayObjectsBusMeter()
    private let leadMeter = DayObjectsBusMeter()
    private let preLimiterMeter = DayObjectsBusMeter()
    private let masterMeter = DayObjectsBusMeter()
    private let happenings: DayObjectsHappeningSamplePool
    private var tapsAreInstalled = false
    private var meterTapInstallationCount = 0
    private var meterResetCount = 0
    private var currentMasterTrimDecibels = DayObjectsPersistentMasterGraph.masterTrimDecibels
    private var lastPublishedAt: TimeInterval = -.infinity
    private var publishedRoleMetrics = DayObjectsPersistentMasterGraph.silentRoleMetrics
    private var publishedMasterMetrics = DayObjectsMasterMetrics(
        peakDBFS: -120,
        rmsDBFS: -120,
        estimatedLimiterReductionDB: 0
    )

    init(happenings: DayObjectsHappeningSamplePool) {
        self.happenings = happenings
        happeningsBus = Mixer([happenings.output], name: "Day Objects happenings bus")

        rhythmCompressor = DynamicRangeCompressor(
            rhythmBus,
            ratio: 2,
            threshold: -10,
            attackDuration: 0.025,
            releaseDuration: 0.14,
            gain: 1,
            dryWetMix: 1
        )
        harmonyHighPass = HighPassFilter(harmonyBus, cutoffFrequency: 72, resonance: 0)
        leadUpperMidSoftener = PeakingParametricEqualizerFilter(
            leadBus,
            centerFrequency: 3_200,
            gain: -5,
            q: 1.1
        )
        leadUpperMidBand = BandPassFilter(
            leadBus,
            centerFrequency: 3_200,
            bandwidth: 1_900
        )
        leadUpperMidCompressor = DynamicsProcessor(
            leadUpperMidBand,
            threshold: -18,
            headRoom: 3,
            expansionRatio: 1,
            expansionThreshold: 1,
            attackTime: 0.008,
            releaseTime: 0.09,
            masterGain: 0
        )
        leadUpperMidBlend = Fader(leadUpperMidCompressor, gain: 0.42)
        leadToneMixer = Mixer([leadUpperMidSoftener, leadUpperMidBlend], name: "Day Objects lead dynamic upper-mid recombine")

        rhythmDirect = Fader(rhythmCompressor, gain: 1)
        bassDirect = Fader(bassBus, gain: 1)
        harmonyDirect = Fader(harmonyHighPass, gain: 1)
        happeningsDirect = Fader(happeningsBus, gain: 1)
        leadDirect = Fader(leadToneMixer, gain: 1)

        rhythmSend = Fader(rhythmCompressor, gain: 0.08)
        rhythmReturnLowCut = HighPassFilter(rhythmSend, cutoffFrequency: 150, resonance: 0)
        rhythmRoomReturn = CostelloReverb(rhythmReturnLowCut, balance: 1, feedback: 0.42, cutoffFrequency: 6_500)
        bassSend = Fader(bassBus, gain: 0.05)
        bassReturnLowCut = HighPassFilter(bassSend, cutoffFrequency: 120, resonance: 0)
        bassShortReturn = CostelloReverb(bassReturnLowCut, balance: 1, feedback: 0.36, cutoffFrequency: 5_500)
        harmonySend = Fader(harmonyHighPass, gain: 0.28)
        harmonyReturnLowCut = HighPassFilter(harmonySend, cutoffFrequency: 160, resonance: 0)
        harmonyHallReturn = CostelloReverb(harmonyReturnLowCut, balance: 1, feedback: 0.72, cutoffFrequency: 5_800)
        happeningsSend = Fader(happeningsBus, gain: 0.34)
        happeningsReturnLowCut = HighPassFilter(happeningsSend, cutoffFrequency: 180, resonance: 0)
        happeningsCathedralReturn = CostelloReverb(happeningsReturnLowCut, balance: 1, feedback: 0.84, cutoffFrequency: 5_200)
        leadSend = Fader(leadToneMixer, gain: 0.38)
        leadDelaySend = Fader(leadToneMixer, gain: 0.24)
        leadReturnLowCut = HighPassFilter(leadSend, cutoffFrequency: 140, resonance: 0)
        leadDelayReturnLowCut = HighPassFilter(leadDelaySend, cutoffFrequency: 140, resonance: 0)
        leadDelayReturn = VariableDelay(leadDelayReturnLowCut, time: 0.28, feedback: 0.32, maximumTime: 2, dryWetMix: 1)
        leadReverbReturn = CostelloReverb(leadReturnLowCut, balance: 1, feedback: 0.62, cutoffFrequency: 6_000)

        masterMixer = Mixer([
            rhythmDirect,
            rhythmRoomReturn,
            bassDirect,
            bassShortReturn,
            harmonyDirect,
            harmonyHallReturn,
            happeningsDirect,
            happeningsCathedralReturn,
            leadDirect,
            leadDelayReturn,
            leadReverbReturn,
        ], name: "Day Objects common master")
        masterHighPass = HighPassFilter(masterMixer, cutoffFrequency: AUValue(Self.masterHighPassHz), resonance: 0)
        glueCompressor = DynamicRangeCompressor(
            masterHighPass,
            ratio: AUValue(Self.glueRatio),
            threshold: -4.5,
            attackDuration: 0.03,
            releaseDuration: 0.2,
            gain: 1,
            dryWetMix: 1
        )
        masterSaturation = TanhDistortion(
            glueCompressor,
            pregain: 1.12,
            postgain: 0.94,
            positiveShapeParameter: 0,
            negativeShapeParameter: 0,
            dryWetMix: 0.10
        )
        masterTrim = Fader(
            masterSaturation,
            gain: AUValue(pow(10, Self.masterTrimDecibels / 20))
        )
        limiter = PeakLimiter(masterTrim, attackTime: 0.012, decayTime: 0.024, preGain: 0)
        finalOutput = DayObjectsMasterOutputGainNode(
            input: limiter,
            decibels: Self.limiterCeilingDBFS
        )
    }

    func topologyMetrics(
        graphs: [DayObjectsAudioKitInstrumentBankGraph],
        audioEngine: AVAudioEngine? = nil
    ) -> DayObjectsInstrumentBankEngineTopologyMetrics {
        let commonMaster = ObjectIdentifier(masterMixer)
        var namedNodes: [String: Node] = [
            "master.mixer": masterMixer,
            "master.highPass": masterHighPass,
            "master.glue": glueCompressor,
            "master.saturation": masterSaturation,
            "master.trim": masterTrim,
            "master.limiter": limiter,
            "master.finalOutput": finalOutput,
            "lead.bus": leadBus,
            "lead.upperMidBand": leadUpperMidBand,
            "lead.upperMidDynamics": leadUpperMidCompressor,
            "lead.upperMidBlend": leadUpperMidBlend,
            "lead.staticNotch": leadUpperMidSoftener,
            "lead.recombine": leadToneMixer,
            "bass.sharedBus": bassBus,
            "bass.direct": bassDirect,
            "bass.send": bassSend,
        ]
        for (index, graph) in graphs.enumerated() {
            for (name, node) in graph.bassNamedNodes {
                namedNodes["bank\(index).bass.\(name)"] = node
            }
        }
        let physicalNodes = fixedNodes + graphs.flatMap(\.fixedLocalNodes)
        let physicalConnections = Set(physicalNodes.flatMap { destination in
            destination.connections.map {
                DayObjectsGraphConnection(
                    source: ObjectIdentifier($0),
                    destination: ObjectIdentifier(destination)
                )
            }
        })
        let attachedAudioNodes = audioEngine.map {
            Set($0.attachedNodes.map(ObjectIdentifier.init))
        } ?? []
        let audioEngineConnections: Set<DayObjectsGraphConnection>
        if let audioEngine {
            audioEngineConnections = Set(audioEngine.attachedNodes.flatMap { source in
                (0..<Int(source.numberOfOutputs)).flatMap { bus in
                    audioEngine.outputConnectionPoints(
                        for: source,
                        outputBus: AVAudioNodeBus(bus)
                    ).compactMap { point in
                        point.node.map {
                            DayObjectsGraphConnection(
                                source: ObjectIdentifier(source),
                                destination: ObjectIdentifier($0)
                            )
                        }
                    }
                }
            })
        } else {
            audioEngineConnections = []
        }
        return .init(
            persistentMasterNodeIdentities: fixedNodeIdentities,
            finalPeakLimiterIdentities: [ObjectIdentifier(limiter)],
            roleBusIdentities: [
                .rhythm: ObjectIdentifier(rhythmBus),
                .bass: ObjectIdentifier(bassBus),
                .harmony: ObjectIdentifier(harmonyBus),
                .happenings: ObjectIdentifier(happeningsBus),
                .lead: ObjectIdentifier(leadBus),
            ],
            parallelSpatialReturnIdentities: [
                ObjectIdentifier(rhythmRoomReturn),
                ObjectIdentifier(bassShortReturn),
                ObjectIdentifier(harmonyHallReturn),
                ObjectIdentifier(happeningsCathedralReturn),
                ObjectIdentifier(leadDelayReturn),
                ObjectIdentifier(leadReverbReturn),
            ],
            commonMasterIdentity: commonMaster,
            roleMasterDestinations: [
                .rhythm: commonMaster,
                .bass: commonMaster,
                .harmony: commonMaster,
                .happenings: commonMaster,
                .lead: commonMaster,
            ],
            happeningsUsesWorldTrim: false,
            masterHighPassHz: Self.masterHighPassHz,
            glueCompressorRatio: Self.glueRatio,
            nominalMaximumGlueReductionDB: Self.nominalMaximumGlueReductionDB,
            limiterCeilingDBFS: Self.limiterCeilingDBFS,
            roleHighPassHz: [.bass: 27, .harmony: 72],
            bassUsesMonoCompatibleLowBand: true,
            bassUsesMildSaturation: true,
            physicalConnections: physicalConnections,
            namedNodeIdentities: namedNodes.mapValues(ObjectIdentifier.init),
            meterTapNodeIdentities: meterTapNodes.map(ObjectIdentifier.init),
            meterTapInstallationCount: meterTapInstallationCount,
            masterSaturationIdentity: ObjectIdentifier(masterSaturation),
            finalOutputIdentity: ObjectIdentifier(finalOutput),
            leadUpperMidDynamicsIdentity: ObjectIdentifier(leadUpperMidCompressor),
            acceptedParameterValues: [
                "master.trim.leftLinear": Double(masterTrim.$leftGain.parameter.value),
                "master.trim.rightLinear": Double(masterTrim.$rightGain.parameter.value),
                "master.glue.ratio": Double(glueCompressor.$ratio.parameter.value),
                "master.glue.thresholdDB": Double(glueCompressor.$threshold.parameter.value),
                "master.saturation.dryWet": Double(masterSaturation.$dryWetMix.parameter.value),
                "master.limiter.preGainDB": Double(limiter.$preGain.parameter.value),
                "master.finalOutput.linear": Double(finalOutput.linearGain),
                "lead.upperMid.centerHz": Double(leadUpperMidBand.$centerFrequency.parameter.value),
                "lead.upperMid.thresholdDB": Double(leadUpperMidCompressor.$threshold.parameter.value),
                "lead.direct.leftLinear": Double(leadDirect.$leftGain.parameter.value),
                "lead.direct.rightLinear": Double(leadDirect.$rightGain.parameter.value),
                "lead.reverbSend.leftLinear": Double(leadSend.$leftGain.parameter.value),
                "lead.reverbSend.rightLinear": Double(leadSend.$rightGain.parameter.value),
                "lead.delaySend.leftLinear": Double(leadDelaySend.$leftGain.parameter.value),
                "lead.delaySend.rightLinear": Double(leadDelaySend.$rightGain.parameter.value),
            ],
            avAudioEngineAttachedNodeIdentities: attachedAudioNodes,
            avAudioEngineConnections: audioEngineConnections,
            avAudioEngineConnectionCount: audioEngineConnections.count
        )
    }

    var fixedNodeIdentities: [ObjectIdentifier] {
        fixedNodes.map(ObjectIdentifier.init)
    }

    var fixedNodes: [Node] {
        [
            rhythmBus, bassBus, harmonyBus, happeningsBus, leadBus,
            rhythmCompressor, harmonyHighPass, leadUpperMidSoftener,
            leadUpperMidBand, leadUpperMidCompressor, leadUpperMidBlend, leadToneMixer,
            rhythmDirect, bassDirect, harmonyDirect, happeningsDirect, leadDirect,
            rhythmSend, rhythmReturnLowCut, rhythmRoomReturn,
            bassSend, bassReturnLowCut, bassShortReturn,
            harmonySend, harmonyReturnLowCut, harmonyHallReturn,
            happeningsSend, happeningsReturnLowCut, happeningsCathedralReturn,
            leadSend, leadDelaySend, leadReturnLowCut, leadDelayReturnLowCut,
            leadDelayReturn, leadReverbReturn,
            masterMixer, masterHighPass, glueCompressor, masterSaturation,
            masterTrim, limiter, finalOutput,
        ]
    }

    private var meterTapNodes: [Node] {
        [rhythmBus, bassBus, harmonyBus, happeningsBus, leadBus, masterTrim, finalOutput]
    }

    var meterTapCapturedScalarSampleCounts: [String: UInt64] {
        [
            "rhythm": rhythmMeter.capturedSampleCount,
            "bass": bassMeter.capturedSampleCount,
            "harmony": harmonyMeter.capturedSampleCount,
            "happenings": happeningsMeter.capturedSampleCount,
            "lead": leadMeter.capturedSampleCount,
            "preLimiter": preLimiterMeter.capturedSampleCount,
            "finalOutput": masterMeter.capturedSampleCount,
        ]
    }

    var limiterMeterTimelineDiagnostics: (pre: [(Int64, UInt64, Double)], post: [(Int64, UInt64, Double)], latency: Int64) {
        let rate = max(finalOutput.avAudioNode.outputFormat(forBus: 0).sampleRate, 1)
        return (
            preLimiterMeter.capturedTimelineRanges.map { ($0.sampleTime, $0.frameCount, $0.peak) },
            masterMeter.capturedTimelineRanges.map { ($0.sampleTime, $0.frameCount, $0.peak) },
            Int64((limiter.avAudioNode.auAudioUnit.latency * rate).rounded())
        )
    }

    var actualMasterTrimDecibels: Double {
        let gain = Double(masterTrim.$leftGain.parameter.value)
        guard gain.isFinite, gain > 0 else { return -120 }
        return 20 * log10(gain)
    }

    var offlineLimiterInputPeakDBFS: Double {
        preLimiterMeter.snapshot(activeVoiceCount: 0).peakDBFS
    }

    func add(_ graph: DayObjectsAudioKitInstrumentBankGraph) {
        graph.bind(to: self)
        for role in [DayObjectsRoleBus.rhythm, .bass, .harmony, .lead] {
            if let output = graph.output(for: role) {
                bus(for: role).addInput(output)
            }
        }
    }

    func remove(_ graph: DayObjectsAudioKitInstrumentBankGraph) {
        for role in [DayObjectsRoleBus.rhythm, .bass, .harmony, .lead] {
            if let output = graph.output(for: role) {
                bus(for: role).removeInput(output)
            }
        }
    }

    func applyMix(_ state: DayObjectsMixState) {
        let duration = min(max(state.rampDurationSeconds.isFinite ? state.rampDurationSeconds : 0, 0), 2)
        apply(
            state.buses.rhythm,
            direct: rhythmDirect,
            send: rhythmSend,
            decay: rhythmRoomReturn.$feedback,
            pathCalibrationDecibels: Self.rhythmPathCalibrationDecibels,
            returnSendCalibration: Self.rhythmReturnSendCalibration,
            duration: duration
        )
        apply(
            state.buses.bass,
            direct: bassDirect,
            send: bassSend,
            decay: bassShortReturn.$feedback,
            pathCalibrationDecibels: Self.bassPathCalibrationDecibels,
            duration: duration
        )
        apply(
            state.buses.harmony,
            direct: harmonyDirect,
            send: harmonySend,
            decay: harmonyHallReturn.$feedback,
            pathCalibrationDecibels: Self.harmonyPathCalibrationDecibels,
            returnSendCalibration: Self.harmonyReturnSendCalibration,
            duration: duration
        )
        apply(
            state.buses.happenings,
            direct: happeningsDirect,
            send: happeningsSend,
            decay: happeningsCathedralReturn.$feedback,
            pathCalibrationDecibels: Self.happeningsPathCalibrationDecibels,
            returnSendCalibration: Self.happeningsReturnSendCalibration,
            duration: duration
        )
        apply(
            state.buses.lead,
            direct: leadDirect,
            send: leadSend,
            decay: leadReverbReturn.$feedback,
            pathCalibrationDecibels: Self.leadPathCalibrationDecibels,
            duration: duration
        )
        let leadIsExplicitlyMuted = state.buses.lead.directTargetDecibels <= -60
        let leadPathCalibration = Self.linearGain(for: Self.leadPathCalibrationDecibels)
        ramp(
            leadDelaySend,
            to: leadIsExplicitlyMuted
                ? 0
                : boundedReturnGain((state.buses.lead.secondarySendLevel ?? 0) * leadPathCalibration),
            duration: leadIsExplicitlyMuted ? 0 : duration
        )
        transition(leadDelayReturn.$feedback, to: boundedDelay(state.buses.lead.secondaryDecay ?? 0.32), duration: duration)
        let requestedMasterDB = min(
            max(
                state.masterTargetDecibelsBeforeLimiter.isFinite
                    ? state.masterTargetDecibelsBeforeLimiter
                    : -60,
                -60
            ),
            Self.masterTrimDecibels
        )
        currentMasterTrimDecibels = requestedMasterDB
        ramp(masterTrim, to: pow(10, requestedMasterDB / 20), duration: duration)
    }

    func startMeters() {
        synchronizeFixedProcessors()
        resetMeterWindows()
    }

    private func synchronizeFixedProcessors() {
        setImmediately(masterHighPass.$cutoffFrequency, to: AUValue(Self.masterHighPassHz))
        setImmediately(masterHighPass.$resonance, to: 0)
        setImmediately(glueCompressor.$ratio, to: AUValue(Self.glueRatio))
        setImmediately(glueCompressor.$threshold, to: -4.5)
        setImmediately(glueCompressor.$attackDuration, to: 0.03)
        setImmediately(glueCompressor.$releaseDuration, to: 0.2)
        setImmediately(glueCompressor.$gain, to: 1)
        setImmediately(glueCompressor.$dryWetMix, to: 1)
        setImmediately(leadUpperMidSoftener.$centerFrequency, to: 3_200)
        setImmediately(leadUpperMidSoftener.$gain, to: -5)
        setImmediately(leadUpperMidSoftener.$q, to: 1.1)
        setImmediately(leadUpperMidBand.$centerFrequency, to: 3_200)
        setImmediately(leadUpperMidBand.$bandwidth, to: 1_900)
        setImmediately(leadUpperMidCompressor.$threshold, to: -18)
        setImmediately(leadUpperMidCompressor.$headRoom, to: 3)
        setImmediately(leadUpperMidCompressor.$expansionRatio, to: 1)
        setImmediately(leadUpperMidCompressor.$expansionThreshold, to: 1)
        setImmediately(leadUpperMidCompressor.$attackTime, to: 0.008)
        setImmediately(leadUpperMidCompressor.$releaseTime, to: 0.09)
        setImmediately(leadUpperMidCompressor.$masterGain, to: 0)
        setImmediately(leadUpperMidBlend.$leftGain, to: 0.42)
        setImmediately(leadUpperMidBlend.$rightGain, to: 0.42)
        setImmediately(masterSaturation.$pregain, to: 1.12)
        setImmediately(masterSaturation.$postgain, to: 0.94)
        setImmediately(masterSaturation.$positiveShapeParameter, to: 0)
        setImmediately(masterSaturation.$negativeShapeParameter, to: 0)
        setImmediately(masterSaturation.$dryWetMix, to: 0.10)
        setImmediately(limiter.$attackTime, to: 0.012)
        setImmediately(limiter.$decayTime, to: 0.024)
        setImmediately(limiter.$preGain, to: 0)
        let trimGain = AUValue(pow(10, currentMasterTrimDecibels / 20))
        setImmediately(masterTrim.$leftGain, to: trimGain)
        setImmediately(masterTrim.$rightGain, to: trimGain)
        finalOutput.applyConfiguredGain()
    }

    func stopMeters() {
        resetMeterWindows()
    }

    func prepareMeters() {
        guard !tapsAreInstalled else { return }
        // AVAudioEngine attachment resets AVAudioMixerNode.outputVolume to unity.
        synchronizeFixedProcessors()
        installTap(on: rhythmBus, meter: rhythmMeter)
        installTap(on: bassBus, meter: bassMeter)
        installTap(on: harmonyBus, meter: harmonyMeter)
        installTap(on: happeningsBus, meter: happeningsMeter)
        installTap(on: leadBus, meter: leadMeter)
        installTap(on: masterTrim, meter: preLimiterMeter)
        installTap(on: finalOutput, meter: masterMeter)
        tapsAreInstalled = true
        meterTapInstallationCount += 1
    }

    private func resetMeterWindows() {
        [rhythmMeter, bassMeter, harmonyMeter, happeningsMeter, leadMeter,
         preLimiterMeter, masterMeter].forEach { $0.reset() }
        publishedRoleMetrics = Self.silentRoleMetrics
        publishedMasterMetrics = .init(peakDBFS: -120, rmsDBFS: -120, estimatedLimiterReductionDB: 0)
        lastPublishedAt = -.infinity
        meterResetCount += 1
    }

    func meterSnapshots(
        graphs: [DayObjectsAudioKitInstrumentBankGraph],
        happeningVoiceCount: Int? = nil,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> (DayObjectsFiveRoleBusMetrics, DayObjectsMasterMetrics) {
        guard now - lastPublishedAt >= 0.1 else {
            return (publishedRoleMetrics, publishedMasterMetrics)
        }
        lastPublishedAt = now
        let rhythmCount = graphs.reduce(0) { $0 + $1.activeVoiceCount(for: .rhythm) }
        let bassCount = graphs.reduce(0) { $0 + $1.activeVoiceCount(for: .bass) }
        let harmonyCount = graphs.reduce(0) { $0 + $1.activeVoiceCount(for: .harmony) }
        let leadCount = graphs.reduce(0) { $0 + $1.activeVoiceCount(for: .lead) }
        publishedRoleMetrics = .init(
            rhythm: rhythmMeter.snapshot(activeVoiceCount: rhythmCount),
            bass: bassMeter.snapshot(activeVoiceCount: bassCount),
            harmony: harmonyMeter.snapshot(activeVoiceCount: harmonyCount),
            happenings: happeningsMeter.snapshot(
                activeVoiceCount: happeningVoiceCount ?? happenings.metrics.activeVoiceCount
            ),
            lead: leadMeter.snapshot(activeVoiceCount: leadCount)
        )
        let limiterLatencyFrames = Int64((
            limiter.avAudioNode.auAudioUnit.latency
                * max(finalOutput.avAudioNode.outputFormat(forBus: 0).sampleRate, 1)
        ).rounded())
        let alignedWindowLimiterReductionEstimate = preLimiterMeter.estimatedReduction(
            comparedTo: masterMeter,
            latencyFrames: limiterLatencyFrames,
            fixedOutputGainDB: Self.limiterCeilingDBFS
        )
        publishedMasterMetrics = masterMeter.masterSnapshot(
            estimatedLimiterReductionDB: alignedWindowLimiterReductionEstimate
        )
        return (publishedRoleMetrics, publishedMasterMetrics)
    }

    func consumeMeterSamplesForTesting(role: DayObjectsRoleBus, amplitude: Float) {
        let samples = [amplitude, -amplitude]
        switch role {
        case .rhythm: rhythmMeter.consume(left: samples, right: samples)
        case .bass: bassMeter.consume(left: samples, right: samples)
        case .harmony: harmonyMeter.consume(left: samples, right: samples)
        case .happenings: happeningsMeter.consume(left: samples, right: samples)
        case .lead: leadMeter.consume(left: samples, right: samples)
        }
        preLimiterMeter.consume(left: samples, right: samples)
        masterMeter.consume(left: samples, right: samples)
        lastPublishedAt = -.infinity
    }

    func bus(for role: DayObjectsRoleBus) -> Mixer {
        return switch role {
        case .rhythm: rhythmBus
        case .bass: bassBus
        case .harmony: harmonyBus
        case .happenings: happeningsBus
        case .lead: leadBus
        }
    }

    private func apply(
        _ parameters: DayObjectsRoleBusMixParameters,
        direct: Fader,
        send: Fader,
        decay: NodeParameter,
        pathCalibrationDecibels: Double,
        returnSendCalibration: Double = 1,
        duration: TimeInterval
    ) {
        let directDB = min(max(parameters.directTargetDecibels.isFinite ? parameters.directTargetDecibels : -60, -60), 0)
        // Diagnostic isolation publishes -60 dB for every non-soloed role.
        // Treat that sentinel as a hard mute on both paths so parallel returns
        // cannot leak a nominally isolated role into the capture.
        let isExplicitlyMuted = directDB <= -60
        let pathCalibration = Self.linearGain(for: pathCalibrationDecibels)
        let pathDuration = isExplicitlyMuted ? 0 : duration
        ramp(direct, to: isExplicitlyMuted ? 0 : pow(10, directDB / 20) * pathCalibration, duration: pathDuration)
        ramp(
            send,
            to: isExplicitlyMuted
                ? 0
                : boundedReturnGain(parameters.sendLevel * returnSendCalibration * pathCalibration),
            duration: pathDuration
        )
        transition(decay, to: boundedUnit(parameters.decay), duration: duration)
    }

    private func ramp(_ fader: Fader, to value: Double, duration: TimeInterval) {
        guard duration > 0 else {
            fader.$leftGain.parameter.value = AUValue(value)
            fader.$rightGain.parameter.value = AUValue(value)
            return
        }
        fader.$leftGain.ramp(to: AUValue(value), duration: Float(duration))
        fader.$rightGain.ramp(to: AUValue(value), duration: Float(duration))
    }

    private func transition(_ parameter: NodeParameter, to value: Double, duration: TimeInterval) {
        guard duration > 0, parameter.parameter.flags.contains(.flag_CanRamp) else {
            parameter.parameter.value = AUValue(value)
            return
        }
        parameter.ramp(to: AUValue(value), duration: Float(duration))
    }

    private func boundedUnit(_ value: Double) -> Double {
        min(max(value.isFinite ? value : 0, 0), DayObjectsAudioParameters.maximumReverbFeedback)
    }

    private func boundedReturnGain(_ value: Double) -> Double {
        min(max(value.isFinite ? value : 0, 0), Self.maximumCalibratedReturnGain)
    }

    private static func linearGain(for decibels: Double) -> Double {
        pow(10, decibels / 20)
    }

    private func boundedDelay(_ value: Double) -> Double {
        min(max(value.isFinite ? value : 0, 0), DayObjectsAudioParameters.maximumDelayFeedback)
    }

    private func setImmediately(_ parameter: NodeParameter, to value: AUValue) {
        parameter.avAudioNode.auAudioUnit.scheduleParameterBlock(
            AUEventSampleTimeImmediate,
            0,
            parameter.parameter.address,
            min(max(value, parameter.range.lowerBound), parameter.range.upperBound)
        )
    }

    private func installTap(on node: Node, meter: DayObjectsBusMeter) {
        node.avAudioNode.installTap(onBus: 0, bufferSize: 1_024, format: nil) { [meter] buffer, time in
            guard let channels = buffer.floatChannelData else { return }
            let channelCount = Int(buffer.format.channelCount)
            guard channelCount > 0 else { return }
            meter.consume(
                left: UnsafePointer(channels[0]),
                right: channelCount > 1 ? UnsafePointer(channels[1]) : nil,
                frameCount: Int(buffer.frameLength),
                sampleTime: time.sampleTime
            )
        }
    }
}

private final class DayObjectsAudioKitInstrumentBankEngine: DayObjectsInstrumentBankEngine {
    private let engine = AudioEngine()
    private let masterGraph: DayObjectsPersistentMasterGraph
    private var graph: DayObjectsAudioKitInstrumentBankGraph?
    private var isOfflineRendering = false

    var topologyMetrics: DayObjectsInstrumentBankEngineTopologyMetrics {
        masterGraph.topologyMetrics(
            graphs: graph.map { [$0] } ?? [],
            audioEngine: engine.avEngine
        )
    }

    init(happenings: DayObjectsHappeningSamplePool) {
        masterGraph = DayObjectsPersistentMasterGraph(happenings: happenings)
        engine.output = masterGraph.finalOutput
        masterGraph.prepareMeters()
    }

    func attach(graph: any DayObjectsInstrumentBankGraph) throws {
        guard let graph = graph as? DayObjectsAudioKitInstrumentBankGraph else {
            throw DayObjectsInstrumentBankError.preparationFailed(.engine)
        }
        if let existing = self.graph, existing !== graph {
            masterGraph.remove(existing)
        }
        masterGraph.add(graph)
        try graph.synchronizeForStart()
        self.graph = graph
    }

    func detach() {
        if let graph { masterGraph.remove(graph) }
        graph = nil
    }
    func start() throws {
        masterGraph.startMeters()
        do { try engine.start() }
        catch { masterGraph.stopMeters(); throw error }
    }
    func stop() {
        engine.stop()
        masterGraph.stopMeters()
    }

    func beginOfflineRendering(
        format: AVAudioFormat,
        maximumFrameCount: AVAudioFrameCount
    ) throws {
        guard graph != nil else { throw DayObjectsInstrumentBankError.notPrepared }
        guard !engine.avEngine.isRunning, !engine.avEngine.isInManualRenderingMode else {
            throw DayObjectsInstrumentBankError.offlineRenderingConflictsWithLivePlayback
        }
        do {
            engine.avEngine.reset()
            try engine.avEngine.enableManualRenderingMode(
                .offline,
                format: format,
                maximumFrameCount: maximumFrameCount
            )
            masterGraph.startMeters()
            try engine.start()
            isOfflineRendering = true
        } catch {
            engine.stop()
            if engine.avEngine.isInManualRenderingMode {
                engine.avEngine.disableManualRenderingMode()
            }
            masterGraph.stopMeters()
            throw error
        }
    }

    func renderOffline(
        _ numberOfFrames: AVAudioFrameCount,
        to buffer: AVAudioPCMBuffer
    ) throws -> AVAudioEngineManualRenderingStatus {
        guard isOfflineRendering else {
            throw DayObjectsInstrumentBankError.offlineRenderingNotStarted
        }
        return try engine.avEngine.renderOffline(numberOfFrames, to: buffer)
    }

    func endOfflineRendering() {
        guard isOfflineRendering || engine.avEngine.isInManualRenderingMode else { return }
        engine.stop()
        if engine.avEngine.isInManualRenderingMode {
            engine.avEngine.disableManualRenderingMode()
        }
        masterGraph.stopMeters()
        isOfflineRendering = false
    }
}

enum DayObjectsPlaybackBankPairLifecycleState: Equatable, Sendable {
    case unprepared
    case prepared
    case started
}

enum DayObjectsPlaybackBankPairStartFailure: Equatable, Sendable {
    case secondBankSynchronization
    case sharedEngineStart
}

struct DayObjectsPlaybackBankPairMetrics: Equatable, Sendable {
    let attachedBankCount: Int
    let sharedAudioEngineCount: Int
    let finalPeakLimiterCount: Int
    let sharedMasterTrimDecibels: Double
    let fixedSharedNodeCount: Int
    let fixedSharedNodeIdentities: [ObjectIdentifier]
    let happeningFixedPlayerIdentities: [ObjectIdentifier]
    let happeningDecodedBufferIdentities: [ObjectIdentifier]
    let happeningDecodedByteCount: Int
    let finalPeakLimiterIdentities: [ObjectIdentifier]
    let lifecycleState: DayObjectsPlaybackBankPairLifecycleState
    let sharedEngineIsRunning: Bool
    let sharedEngineStartCount: Int
    let sharedEngineStopCount: Int
    let individualStartedBankCount: Int
    let allocationFingerprint: [DayObjectsInstrumentBankAllocationFingerprint?]
    let roleBusMetrics: DayObjectsFiveRoleBusMetrics
    let masterMetrics: DayObjectsMasterMetrics
    let meterTapCapturedScalarSampleCounts: [String: UInt64]
}

@MainActor
final class DayObjectsPlaybackBankPair {
    let bankA: DayObjectsInstrumentBank
    let bankB: DayObjectsInstrumentBank
    private let sharedEngine: DayObjectsSharedInstrumentBankEngine
    private let startFailureProvider: () -> DayObjectsPlaybackBankPairStartFailure?
    private var lifecycleState: DayObjectsPlaybackBankPairLifecycleState = .unprepared
    private var holdsLivePlaybackLease = false

    var metrics: DayObjectsPlaybackBankPairMetrics {
        sharedEngine.metrics(
            lifecycleState: lifecycleState,
            allocationFingerprint: [
                bankA.metrics.allocationFingerprint,
                bankB.metrics.allocationFingerprint,
            ]
        )
    }

    fileprivate init(
        bankA: DayObjectsInstrumentBank,
        bankB: DayObjectsInstrumentBank,
        sharedEngine: DayObjectsSharedInstrumentBankEngine,
        startFailureProvider: @escaping () -> DayObjectsPlaybackBankPairStartFailure?
    ) {
        self.bankA = bankA
        self.bankB = bankB
        self.sharedEngine = sharedEngine
        self.startFailureProvider = startFailureProvider
    }

    func prepare(configuration: DayObjectsInstrumentBankConfiguration) throws {
        try bankA.prepare(configuration: configuration)
        try bankB.prepare(configuration: configuration)
        if sharedEngine.hasPairOwnership {
            bankA.markPlaybackPairStarted()
            bankB.markPlaybackPairStarted()
            lifecycleState = .started
        } else {
            lifecycleState = .prepared
        }
    }

    func start() throws {
        guard lifecycleState != .unprepared else {
            throw DayObjectsInstrumentBankError.notPrepared
        }
        guard lifecycleState != .started else { return }
        let promotesBankAOwner = sharedEngine.canPromoteBankAOwnershipToPair
        guard sharedEngine.canAcquirePairOwnership || promotesBankAOwner else {
            throw DayObjectsInstrumentBankError.startFailed
        }
        try acquireLivePlaybackLease()

        let injectedFailure = startFailureProvider()
        do {
            try bankA.synchronizePreparedGraphForPlaybackPair()
            if injectedFailure == .secondBankSynchronization {
                throw DayObjectsInstrumentBankError.startFailed
            }
            try bankB.synchronizePreparedGraphForPlaybackPair()
            if injectedFailure == .sharedEngineStart {
                throw DayObjectsInstrumentBankError.startFailed
            }
            if promotesBankAOwner {
                try sharedEngine.promoteBankAOwnershipToPair()
            } else {
                try sharedEngine.startPair()
            }
            bankA.markPlaybackPairStarted()
            bankB.markPlaybackPairStarted()
            lifecycleState = .started
        } catch {
            releaseLivePlaybackLease()
            if promotesBankAOwner {
                bankA.releaseWorldLocalVoices()
                bankB.releaseWorldLocalVoices()
                sharedEngine.demotePairOwnershipToBankA()
                bankA.markPlaybackPairStarted()
                bankB.markPlaybackPairPrepared()
            } else {
                bankA.releaseAllIncludingSharedHappenings()
                bankB.releaseWorldLocalVoices()
                sharedEngine.rollbackFailedPairStart()
                bankA.markPlaybackPairPrepared()
                bankB.markPlaybackPairPrepared()
            }
            lifecycleState = .prepared
            throw DayObjectsInstrumentBankError.liveStartFailure(classifying: error)
        }
    }

    func demoteToBankASampleOnlyOwnership() {
        guard lifecycleState == .started else { return }
        guard (try? bankA.acquireLivePlaybackLease()) != nil else { return }
        sharedEngine.demotePairOwnershipToBankA()
        releaseLivePlaybackLease()
        bankA.markPlaybackPairStarted()
        bankB.markPlaybackPairPrepared()
        lifecycleState = .prepared
    }

    func stop() {
        guard lifecycleState == .started else { return }
        bankA.releaseAllIncludingSharedHappenings()
        bankB.releaseWorldLocalVoices()
        sharedEngine.stopPair()
        releaseLivePlaybackLease()
        bankA.releaseLivePlaybackLease()
        bankB.releaseLivePlaybackLease()
        bankA.markPlaybackPairPrepared()
        bankB.markPlaybackPairPrepared()
        lifecycleState = .prepared
    }

    func consumeMeterSamplesForTesting(role: DayObjectsRoleBus, amplitude: Float) {
        sharedEngine.consumeMeterSamplesForTesting(role: role, amplitude: amplitude)
    }

    private func acquireLivePlaybackLease() throws {
        guard !holdsLivePlaybackLease else { return }
        try DayObjectsAudioPlaybackLease.shared.acquireLive(owner: self)
        holdsLivePlaybackLease = true
    }

    private func releaseLivePlaybackLease() {
        guard holdsLivePlaybackLease else { return }
        DayObjectsAudioPlaybackLease.shared.releaseLive(owner: self)
        holdsLivePlaybackLease = false
    }
}

private enum DayObjectsPlaybackBankSlot: Hashable { case a, b }

private enum DayObjectsPairedInstrumentBankStopResult {
    case rejected
    case worldStopped
    case sharedRuntimeStopped
}

@MainActor
private protocol DayObjectsPairedInstrumentBankLifecycleGate: AnyObject {
    func requestIndividualStop() -> DayObjectsPairedInstrumentBankStopResult
}

@MainActor
private final class DayObjectsPairedInstrumentBankEngine: DayObjectsInstrumentBankEngine,
    DayObjectsPairedInstrumentBankLifecycleGate {
    private let slot: DayObjectsPlaybackBankSlot
    private let shared: DayObjectsSharedInstrumentBankEngine

    init(slot: DayObjectsPlaybackBankSlot, shared: DayObjectsSharedInstrumentBankEngine) {
        self.slot = slot
        self.shared = shared
    }

    var topologyMetrics: DayObjectsInstrumentBankEngineTopologyMetrics {
        shared.topologyMetrics
    }

    func attach(graph: any DayObjectsInstrumentBankGraph) throws {
        try shared.attach(graph: graph, slot: slot)
    }
    func detach() { shared.releaseAttachmentRequest(slot: slot) }
    func start() throws { try shared.requestIndividualStart(slot: slot) }
    func stop() { _ = shared.requestIndividualStop(slot: slot) }
    func requestIndividualStop() -> DayObjectsPairedInstrumentBankStopResult {
        shared.requestIndividualStop(slot: slot)
    }
}

@MainActor
private final class DayObjectsSharedInstrumentBankEngine {
    private let engine = AudioEngine()
    private var graphs: [DayObjectsPlaybackBankSlot: DayObjectsAudioKitInstrumentBankGraph] = [:]
    private var attachedSlots: Set<DayObjectsPlaybackBankSlot> = []
    private let masterGraph: DayObjectsPersistentMasterGraph
    private let happenings: DayObjectsHappeningSamplePool
    private let individualStartFailureProvider: () -> Error?
    private var individuallyStartedSlots: Set<DayObjectsPlaybackBankSlot> = []
    private var pairIsRunning = false
    private var startCount = 0
    private var stopCount = 0
    var canAcquirePairOwnership: Bool {
        individuallyStartedSlots.isEmpty && !pairIsRunning
    }
    var hasPairOwnership: Bool { pairIsRunning }
    var canPromoteBankAOwnershipToPair: Bool {
        individuallyStartedSlots == [.a]
            && !pairIsRunning
            && attachedSlots.count == 2
            && engine.avEngine.isRunning
    }

    init(
        happenings: DayObjectsHappeningSamplePool,
        individualStartFailureProvider: @escaping () -> Error?
    ) {
        self.happenings = happenings
        self.individualStartFailureProvider = individualStartFailureProvider
        masterGraph = DayObjectsPersistentMasterGraph(happenings: happenings)
        engine.output = masterGraph.finalOutput
        masterGraph.prepareMeters()
    }

    var topologyMetrics: DayObjectsInstrumentBankEngineTopologyMetrics {
        masterGraph.topologyMetrics(
            graphs: Array(graphs.values),
            audioEngine: engine.avEngine
        )
    }

    func attach(
        graph: any DayObjectsInstrumentBankGraph,
        slot: DayObjectsPlaybackBankSlot
    ) throws {
        guard let graph = graph as? DayObjectsAudioKitInstrumentBankGraph else {
            throw DayObjectsInstrumentBankError.preparationFailed(.engine)
        }
        if let existing = graphs[slot], existing !== graph {
            masterGraph.remove(existing)
        }
        graphs[slot] = graph
        attachedSlots.insert(slot)
        masterGraph.add(graph)
        try graph.synchronizeForStart()
    }

    func releaseAttachmentRequest(slot: DayObjectsPlaybackBankSlot) {
        // Playback-pair graphs are retained for the pair's lifetime. An individual
        // bank cannot tear down the other slot's shared output topology.
        individuallyStartedSlots.remove(slot)
    }

    func requestIndividualStart(slot: DayObjectsPlaybackBankSlot) throws {
        guard !pairIsRunning else { throw DayObjectsInstrumentBankError.startFailed }
        guard !individuallyStartedSlots.contains(slot) else { return }
        guard attachedSlots.contains(slot) else {
            throw DayObjectsInstrumentBankError.notPrepared
        }
        if individuallyStartedSlots.isEmpty, !engine.avEngine.isRunning {
            masterGraph.startMeters()
            do {
                if let injectedFailure = individualStartFailureProvider() {
                    throw injectedFailure
                }
                try engine.start()
            }
            catch { masterGraph.stopMeters(); throw error }
            startCount += 1
        }
        individuallyStartedSlots.insert(slot)
    }

    func requestIndividualStop(slot: DayObjectsPlaybackBankSlot) -> DayObjectsPairedInstrumentBankStopResult {
        guard !pairIsRunning, individuallyStartedSlots.remove(slot) != nil else {
            return .rejected
        }
        if individuallyStartedSlots.isEmpty {
            stopEngineIfRunning()
            return .sharedRuntimeStopped
        }
        return .worldStopped
    }

    func startPair() throws {
        guard attachedSlots.count == 2 else {
            throw DayObjectsInstrumentBankError.notPrepared
        }
        guard !pairIsRunning else { return }
        if !engine.avEngine.isRunning {
            masterGraph.startMeters()
            do { try engine.start() }
            catch { masterGraph.stopMeters(); throw error }
            startCount += 1
        }
        pairIsRunning = true
    }

    func promoteBankAOwnershipToPair() throws {
        guard canPromoteBankAOwnershipToPair else {
            throw DayObjectsInstrumentBankError.startFailed
        }
        individuallyStartedSlots.remove(.a)
        pairIsRunning = true
    }

    func demotePairOwnershipToBankA() {
        guard pairIsRunning else { return }
        pairIsRunning = false
        individuallyStartedSlots = [.a]
    }

    func stopPair() {
        guard pairIsRunning else { return }
        pairIsRunning = false
        stopEngineIfRunning()
    }

    func rollbackFailedPairStart() {
        pairIsRunning = false
        stopEngineIfRunning()
    }

    func metrics(
        lifecycleState: DayObjectsPlaybackBankPairLifecycleState,
        allocationFingerprint: [DayObjectsInstrumentBankAllocationFingerprint?]
    ) -> DayObjectsPlaybackBankPairMetrics {
        let fixedNodeIdentities = masterGraph.fixedNodeIdentities
        let happeningMetrics = happenings.metrics
        let meterSnapshots = masterGraph.meterSnapshots(
            graphs: Array(graphs.values),
            happeningVoiceCount: happeningMetrics.activeVoiceCount
        )
        return .init(
            attachedBankCount: attachedSlots.count,
            sharedAudioEngineCount: 1,
            finalPeakLimiterCount: 1,
            sharedMasterTrimDecibels: masterGraph.actualMasterTrimDecibels,
            fixedSharedNodeCount: fixedNodeIdentities.count,
            fixedSharedNodeIdentities: fixedNodeIdentities,
            happeningFixedPlayerIdentities: happeningMetrics.fixedPlayerIdentities,
            happeningDecodedBufferIdentities: happeningMetrics.decodedBufferIdentities,
            happeningDecodedByteCount: happeningMetrics.decodedByteCount,
            finalPeakLimiterIdentities: [ObjectIdentifier(masterGraph.limiter)],
            lifecycleState: lifecycleState,
            sharedEngineIsRunning: engine.avEngine.isRunning,
            sharedEngineStartCount: startCount,
            sharedEngineStopCount: stopCount,
            individualStartedBankCount: individuallyStartedSlots.count,
            allocationFingerprint: allocationFingerprint,
            roleBusMetrics: meterSnapshots.0,
            masterMetrics: meterSnapshots.1,
            meterTapCapturedScalarSampleCounts: masterGraph.meterTapCapturedScalarSampleCounts
        )
    }

    func consumeMeterSamplesForTesting(role: DayObjectsRoleBus, amplitude: Float) {
        masterGraph.consumeMeterSamplesForTesting(role: role, amplitude: amplitude)
    }

    private func stopEngineIfRunning() {
        if engine.avEngine.isRunning {
            engine.stop()
            masterGraph.stopMeters()
            stopCount += 1
        }
    }
}
#endif
