#if DEBUG || INTERNAL_BUILD
import AudioKit
import AudioKitEX
import AudioToolbox
import AVFoundation
import Foundation
import SoundpipeAudioKit

@MainActor
final class DayObjectsInstrumentBank: DayObjectsInstrumentBankProtocol {
    typealias TonalInstrumentLoader = () throws -> [DayObjectsInstrumentID: NormalizedSynthVoice]
    typealias TonalPoolFactory = (DayObjectsTonalPoolSpecification, [DayObjectsInstrumentID: NormalizedSynthVoice]) throws -> DayObjectsTonalVoicePoolProtocol
    typealias DrumBankFactory = ([DayObjectsDrumVoice: Int]) throws -> DayObjectsDrumBankProtocol
    typealias PianoPoolFactory = (Int) throws -> DayObjectsPianoPoolProtocol
    typealias GraphFactory = ([DayObjectsTonalVoicePoolProtocol], DayObjectsDrumBankProtocol, DayObjectsPianoPoolProtocol) throws -> DayObjectsInstrumentBankGraph

    let descriptors: [DayObjectsInstrumentDescriptor]
    private let descriptorByID: [DayObjectsInstrumentID: DayObjectsInstrumentDescriptor]
    private let tonalInstrumentLoader: TonalInstrumentLoader
    private let tonalPoolFactory: TonalPoolFactory
    private let drumBankFactory: DrumBankFactory
    private let pianoPoolFactory: PianoPoolFactory
    private let graphFactory: GraphFactory
    private let engine: DayObjectsInstrumentBankEngine
    private let inactiveDrums = DayObjectsInactiveDrumBank()
    private let inactivePiano = DayObjectsInactivePianoPool()
    private var prepared: PreparedState?

    var drums: DayObjectsDrumBankProtocol { prepared?.drums ?? inactiveDrums }
    var piano: DayObjectsPianoPoolProtocol { prepared?.piano ?? inactivePiano }
    var outputGainMetrics: DayObjectsBankOutputGainMetrics {
        prepared?.graph.outputGainMetrics ?? .unsupported
    }

    var metrics: DayObjectsInstrumentBankMetrics {
        .init(
            state: prepared?.state ?? .unprepared,
            tonalPoolCount: prepared?.tonalPools.count ?? 0,
            graph: prepared?.graph.layout,
            allocationFingerprint: prepared?.graph.allocationFingerprint,
            drumMetrics: drums.metrics,
            pianoMetrics: piano.metrics
        )
    }

    init(
        descriptors: [DayObjectsInstrumentDescriptor],
        tonalInstrumentLoader: @escaping TonalInstrumentLoader,
        tonalPoolFactory: @escaping TonalPoolFactory,
        drumBankFactory: @escaping DrumBankFactory,
        pianoPoolFactory: @escaping PianoPoolFactory,
        graphFactory: @escaping GraphFactory,
        engine: DayObjectsInstrumentBankEngine
    ) {
        self.descriptors = descriptors
        descriptorByID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
        self.tonalInstrumentLoader = tonalInstrumentLoader
        self.tonalPoolFactory = tonalPoolFactory
        self.drumBankFactory = drumBankFactory
        self.pianoPoolFactory = pianoPoolFactory
        self.graphFactory = graphFactory
        self.engine = engine
    }

    convenience init(bundle: Bundle = .main) {
        self.init(
            bundle: bundle,
            engine: DayObjectsAudioKitInstrumentBankEngine(),
            outputGainHostTimeProvider: { ProcessInfo.processInfo.systemUptime }
        )
    }

    private convenience init(
        bundle: Bundle,
        engine: DayObjectsInstrumentBankEngine,
        outputGainHostTimeProvider: @escaping () -> TimeInterval
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
                    DayObjectsAudioKitTonalPool(specification: specification, instruments: instruments)
                )
            },
            drumBankFactory: { overlapCounts in
                DayObjectsAudioKitDrumBankAdapter(.init(resourceResolver: { sample in
                    let filename = sample.rawValue as NSString
                    return bundle.url(forResource: filename.deletingPathExtension, withExtension: filename.pathExtension, subdirectory: "Drums")
                }, recipes: Self.drumRecipes(overlapCounts)))
            },
            pianoPoolFactory: { requestedCount in
                let samples = try FeltPianoManifest.load(from: bundle)
                let adapter = DayObjectsAudioKitFeltPiano(samples: samples, recipe: Self.pianoRecipe(voiceCount: requestedCount), resourceResolver: { sample in
                    let filename = sample.filename as NSString
                    return bundle.url(forResource: filename.deletingPathExtension, withExtension: filename.pathExtension, subdirectory: "FeltPiano")
                })
                return DayObjectsAudioKitPianoPoolAdapter(adapter)
            },
            graphFactory: { tonalPools, drums, piano in
                guard let tonalAdapters = tonalPools.compactMap({
                    (($0 as? DayObjectsCategoryValidatedTonalPool)?.pool as? DayObjectsAudioKitTonalPoolAdapter)?.adapter
                }) as [DayObjectsAudioKitTonalPool]?,
                      tonalAdapters.count == tonalPools.count,
                      let drumAdapter = drums as? DayObjectsAudioKitDrumBankAdapter,
                      let pianoAdapter = piano as? DayObjectsAudioKitPianoPoolAdapter
                else { throw DayObjectsInstrumentBankError.preparationFailed(.graph) }
                return DayObjectsAudioKitInstrumentBankGraph(
                    tonalPools: tonalAdapters,
                    drums: drumAdapter.adapter,
                    piano: pianoAdapter.adapter,
                    outputGainHostTimeProvider: outputGainHostTimeProvider
                )
            },
            engine: engine
        )
    }

    static func makePlaybackPair(
        bundle: Bundle = .main,
        startFailureProvider: @escaping () -> DayObjectsPlaybackBankPairStartFailure? = { nil },
        outputGainHostTimeProvider: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) -> DayObjectsPlaybackBankPair {
        let sharedEngine = DayObjectsSharedInstrumentBankEngine()
        let bankA = DayObjectsInstrumentBank(
            bundle: bundle,
            engine: DayObjectsPairedInstrumentBankEngine(slot: .a, shared: sharedEngine),
            outputGainHostTimeProvider: outputGainHostTimeProvider
        )
        let bankB = DayObjectsInstrumentBank(
            bundle: bundle,
            engine: DayObjectsPairedInstrumentBankEngine(slot: .b, shared: sharedEngine),
            outputGainHostTimeProvider: outputGainHostTimeProvider
        )
        return DayObjectsPlaybackBankPair(
            bankA: bankA,
            bankB: bankB,
            sharedEngine: sharedEngine,
            startFailureProvider: startFailureProvider
        )
    }

    func prepare(configuration: DayObjectsInstrumentBankConfiguration) throws {
        if let prepared {
            guard prepared.configuration == configuration else {
                throw DayObjectsInstrumentBankError.configurationChangedAfterPreparation
            }
            return
        }
        try validate(configuration)

        var builtTonalPools: [DayObjectsTonalVoicePoolProtocol] = []
        var builtDrums: DayObjectsDrumBankProtocol?
        var builtPiano: DayObjectsPianoPoolProtocol?
        do {
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
            do { graph = try graphFactory(builtTonalPools, builtDrums, builtPiano) }
            catch { throw DayObjectsInstrumentBankError.preparationFailed(.graph) }
            do { try engine.attach(graph: graph) }
            catch { throw DayObjectsInstrumentBankError.preparationFailed(.engine) }

            prepared = .init(
                configuration: configuration,
                tonalPools: Dictionary(uniqueKeysWithValues: zip(configuration.tonalPools.map(\.name), builtTonalPools)),
                drums: builtDrums,
                piano: builtPiano,
                graph: graph,
                state: .prepared
            )
        } catch let error as DayObjectsInstrumentBankError {
            release(builtTonalPools, builtDrums, builtPiano)
            engine.stop()
            engine.detach()
            throw error
        } catch {
            release(builtTonalPools, builtDrums, builtPiano)
            engine.stop()
            engine.detach()
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
        do {
            if !prepared.isAttached {
                try engine.attach(graph: prepared.graph)
                self.prepared?.isAttached = true
            }
            try prepared.graph.synchronizeForStart()
            try engine.start()
            self.prepared?.state = .started
        } catch {
            releaseAll()
            if engine is any DayObjectsPairedInstrumentBankLifecycleGate {
                self.prepared?.state = .prepared
                self.prepared?.isAttached = true
                throw DayObjectsInstrumentBankError.startFailed
            }
            engine.stop()
            engine.detach()
            self.prepared = nil
            throw DayObjectsInstrumentBankError.startFailed
        }
    }

    func stop() async {
        if let pairedGate = engine as? any DayObjectsPairedInstrumentBankLifecycleGate {
            guard prepared?.state == .started else { return }
            guard pairedGate.requestIndividualStop() else { return }
            releaseAll()
            prepared?.state = .prepared
            prepared?.isAttached = true
            return
        }
        releaseAll()
        engine.stop()
        engine.detach()
        if prepared != nil { prepared?.state = .prepared; prepared?.isAttached = false }
    }

    func releaseAll() {
        guard let prepared else { return }
        prepared.tonalPools.values.forEach { $0.releaseAll() }
        prepared.drums.releaseAll()
        prepared.piano.releaseAll()
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

    var programEffectMetrics: DayObjectsProgramEffectMetrics {
        prepared?.graph.programEffectMetrics ?? .unsupported
    }

    func applyProgramEffects(
        masterLinearGain: Double,
        delayFeedback: Double,
        reverbFeedback: Double,
        rampDurationSeconds: TimeInterval
    ) {
        prepared?.graph.applyProgramEffects(
            masterLinearGain: masterLinearGain,
            delayFeedback: delayFeedback,
            reverbFeedback: reverbFeedback,
            rampDurationSeconds: rampDurationSeconds
        )
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
        _ piano: DayObjectsPianoPoolProtocol?
    ) {
        tonalPools.forEach { $0.releaseAll() }
        drums?.releaseAll()
        piano?.releaseAll()
    }

    private struct PreparedState {
        let configuration: DayObjectsInstrumentBankConfiguration
        let tonalPools: [String: DayObjectsTonalVoicePoolProtocol]
        let drums: DayObjectsDrumBankProtocol
        let piano: DayObjectsPianoPoolProtocol
        let graph: DayObjectsInstrumentBankGraph
        var state: DayObjectsInstrumentBankState
        var isAttached: Bool = true
    }

    private static func drumRecipes(_ requested: [DayObjectsDrumVoice: Int]) -> [DayObjectsDrumVoice: DayObjectsDrumRecipe] {
        Dictionary(uniqueKeysWithValues: DayObjectsDrumVoice.allCases.map { voice in
            let base = DayObjectsDrumRecipe.recipe(for: voice)
            let overlap = requested[voice] ?? base.overlapCount
            return (voice, .init(voice: base.voice, primarySample: base.primarySample, fallbackSample: base.fallbackSample, synthesis: base.synthesis, sinePitchDrop: base.sinePitchDrop, noiseAmplitude: base.noiseAmplitude, overlapCount: overlap, transientFilterCutoffHz: base.transientFilterCutoffHz, noiseFilterCutoffHz: base.noiseFilterCutoffHz, variation: base.variation, allowsPitchDrift: base.allowsPitchDrift, allowsBroadbandSustainedNoise: base.allowsBroadbandSustainedNoise, usesSawOscillator: base.usesSawOscillator, delayFeedback: base.delayFeedback))
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

private final class DayObjectsAudioKitInstrumentBankGraph: DayObjectsInstrumentBankGraph {
    var layout: DayObjectsInstrumentBankGraphLayout { .init(tonalBusCount: 1, drumBusCount: 1, sharedSpatialEffectCount: 2, tonalBusGainDB: Self.decibels(tonalTrim.leftGain), drumBusGainDB: Self.decibels(drumTrim.leftGain), masterTrimDB: Self.decibels(masterTrim.leftGain), finalPeakLimiterCount: 1) }
    let tonalBus: Mixer
    let drumBus: Mixer
    let tonalTrim: Fader
    let drumTrim: Fader
    let programBus: Mixer
    let delay: VariableDelay
    let reverb: CostelloReverb
    let masterTrim: Fader
    let worldTrim: Fader
    let limiter: PeakLimiter
    private let tonalPools: [DayObjectsAudioKitTonalPool]
    private let drums: DayObjectsAudioKitDrumBank
    private let piano: DayObjectsAudioKitFeltPiano
    private var outputGainTarget = 1.0
    private var outputGainRampDuration: TimeInterval = 0
    private var outputGainRampCount = 0
    private var lastScheduledOutputGainAutomation: DayObjectsBankOutputGainAutomation?
    private let outputGainHostTimeProvider: () -> TimeInterval
    private let outputGainSampleRateProvider: () -> Double
    private var currentProgramEffectMetrics = DayObjectsProgramEffectMetrics.unsupported

    var programEffectMetrics: DayObjectsProgramEffectMetrics { currentProgramEffectMetrics }

    var outputGainMetrics: DayObjectsBankOutputGainMetrics {
        .init(
            isSupported: true,
            targetLinearGain: outputGainTarget,
            lastRampDurationSeconds: outputGainRampDuration,
            rampCount: outputGainRampCount,
            lastScheduledAutomation: lastScheduledOutputGainAutomation
        )
    }

    var allocationFingerprint: DayObjectsInstrumentBankAllocationFingerprint {
        let drumMetrics = drums.metrics
        let pianoMetrics = piano.metrics
        return .init(
            tonalNodeIdentities: tonalPools.flatMap(\.voiceNodeIdentities),
            drumPreloadedSampleCount: drumMetrics.preloadedSampleCount,
            drumAllocatedNodeCount: drumMetrics.allocatedNodeCount,
            drumFixedPlayerCount: drumMetrics.fixedPlayerCount,
            pianoPreloadedSampleCount: pianoMetrics.preloadedSampleCount,
            pianoLoadedPlayerCount: pianoMetrics.loadedPlayerCount,
            pianoFixedBackendCount: pianoMetrics.fixedBackendCount
        )
    }

    init(
        tonalPools: [DayObjectsAudioKitTonalPool],
        drums: DayObjectsAudioKitDrumBank,
        piano: DayObjectsAudioKitFeltPiano,
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
        tonalBus = Mixer(tonalPools.map(\.output) + [piano.output], name: "Day Objects tonal bus")
        drumBus = Mixer([drums.output], name: "Day Objects drum bus")
        // These are bus trims, not per-voice output trims. The shared voice
        // sanitizer intentionally caps voice gain at -6 dB, so using it here
        // would silently turn every requested -3 dB bus stage into -6 dB.
        tonalTrim = Fader(tonalBus, gain: AUValue(Self.linearGain(decibels: -3)))
        drumTrim = Fader(drumBus, gain: AUValue(Self.linearGain(decibels: -3)))
        programBus = Mixer([tonalTrim, drumTrim], name: "Day Objects program bus")
        delay = VariableDelay(programBus, time: 0.28, feedback: 0.35, maximumTime: 2, dryWetMix: 0.14)
        reverb = CostelloReverb(delay, balance: 0.12, feedback: 0.72, cutoffFrequency: 8_000)
        masterTrim = Fader(reverb, gain: AUValue(Self.linearGain(decibels: -3)))
        worldTrim = Fader(masterTrim, gain: 1)
        limiter = PeakLimiter(worldTrim)
        currentProgramEffectMetrics = .init(
            isSupported: true,
            masterLinearGain: Double(masterTrim.leftGain),
            delayFeedback: Double(delay.feedback),
            reverbFeedback: Double(reverb.feedback),
            rampDurationSeconds: 0,
            delayFeedbackWasRamped: false,
            reverbFeedbackWasRamped: false,
            feedbackRampDurationSeconds: 0
        )
    }

    func applyProgramEffects(
        masterLinearGain: Double,
        delayFeedback: Double,
        reverbFeedback: Double,
        rampDurationSeconds: TimeInterval
    ) {
        let master = min(max(masterLinearGain.isFinite ? masterLinearGain : 0, 0), 1)
        let delayTarget = min(max(delayFeedback.isFinite ? delayFeedback : 0, 0), DayObjectsAudioParameters.maximumDelayFeedback)
        let reverbTarget = min(max(reverbFeedback.isFinite ? reverbFeedback : 0, 0), DayObjectsAudioParameters.maximumReverbFeedback)
        let duration = min(max(rampDurationSeconds.isFinite ? rampDurationSeconds : 0, 0), 2)
        masterTrim.$leftGain.ramp(to: AUValue(master), duration: Float(duration))
        masterTrim.$rightGain.ramp(to: AUValue(master), duration: Float(duration))
        let didRampDelay = applyParameterTransition(
            delay.$feedback,
            target: AUValue(delayTarget),
            duration: duration
        )
        let didRampReverb = applyParameterTransition(
            reverb.$feedback,
            target: AUValue(reverbTarget),
            duration: duration
        )
        currentProgramEffectMetrics = .init(
            isSupported: true,
            masterLinearGain: master,
            delayFeedback: delayTarget,
            reverbFeedback: reverbTarget,
            rampDurationSeconds: duration,
            delayFeedbackWasRamped: didRampDelay,
            reverbFeedbackWasRamped: didRampReverb,
            feedbackRampDurationSeconds: didRampDelay || didRampReverb ? duration : 0
        )
    }

    private func applyParameterTransition(
        _ parameter: NodeParameter,
        target: AUValue,
        duration: TimeInterval
    ) -> Bool {
        guard duration > 0, parameter.parameter.flags.contains(.flag_CanRamp) else {
            parameter.value = target
            return false
        }
        parameter.ramp(to: target, duration: Float(duration))
        return true
    }

    func setOutputGain(_ linearGain: Double, rampDurationSeconds: TimeInterval) {
        let target = min(max(linearGain.isFinite ? linearGain : 0, 0), 1)
        let duration = max(rampDurationSeconds.isFinite ? rampDurationSeconds : 0, 0)
        outputGainTarget = target
        outputGainRampDuration = duration
        outputGainRampCount += 1
        lastScheduledOutputGainAutomation = nil
        worldTrim.$leftGain.ramp(to: AUValue(target), duration: Float(duration))
        worldTrim.$rightGain.ramp(to: AUValue(target), duration: Float(duration))
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
            worldTrim.$leftGain.value = AUValue(target)
            worldTrim.$rightGain.value = AUValue(target)
            return
        }

        schedule(
            worldTrim.$leftGain,
            target: AUValue(target),
            startingAtHostTime: effectiveStart,
            endingAtHostTime: effectiveEnd,
            now: now
        )
        schedule(
            worldTrim.$rightGain,
            target: AUValue(target),
            startingAtHostTime: effectiveStart,
            endingAtHostTime: effectiveEnd,
            now: now
        )
    }

    func synchronizeForStart() throws {
        tonalPools.forEach { $0.synchronizeGraphIfAttached() }
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
}

private final class DayObjectsAudioKitInstrumentBankEngine: DayObjectsInstrumentBankEngine {
    private let engine = AudioEngine()

    func attach(graph: any DayObjectsInstrumentBankGraph) throws {
        guard let graph = graph as? DayObjectsAudioKitInstrumentBankGraph else {
            throw DayObjectsInstrumentBankError.preparationFailed(.engine)
        }
        engine.output = graph.limiter
    }

    func detach() { engine.output = nil }
    func start() throws { try engine.start() }
    func stop() { engine.stop() }
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
    let lifecycleState: DayObjectsPlaybackBankPairLifecycleState
    let sharedEngineIsRunning: Bool
    let sharedEngineStartCount: Int
    let sharedEngineStopCount: Int
    let individualStartedBankCount: Int
    let allocationFingerprint: [DayObjectsInstrumentBankAllocationFingerprint?]
}

@MainActor
final class DayObjectsPlaybackBankPair {
    let bankA: DayObjectsInstrumentBank
    let bankB: DayObjectsInstrumentBank
    private let sharedEngine: DayObjectsSharedInstrumentBankEngine
    private let startFailureProvider: () -> DayObjectsPlaybackBankPairStartFailure?
    private var lifecycleState: DayObjectsPlaybackBankPairLifecycleState = .unprepared

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
        lifecycleState = .prepared
    }

    func start() throws {
        guard lifecycleState != .unprepared else {
            throw DayObjectsInstrumentBankError.notPrepared
        }
        guard lifecycleState != .started else { return }
        guard sharedEngine.canAcquirePairOwnership else {
            throw DayObjectsInstrumentBankError.startFailed
        }

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
            try sharedEngine.startPair()
            bankA.markPlaybackPairStarted()
            bankB.markPlaybackPairStarted()
            lifecycleState = .started
        } catch {
            bankA.releaseAll()
            bankB.releaseAll()
            sharedEngine.rollbackFailedPairStart()
            bankA.markPlaybackPairPrepared()
            bankB.markPlaybackPairPrepared()
            lifecycleState = .prepared
            throw DayObjectsInstrumentBankError.startFailed
        }
    }

    func stop() {
        guard lifecycleState == .started else { return }
        bankA.releaseAll()
        bankB.releaseAll()
        sharedEngine.stopPair()
        bankA.markPlaybackPairPrepared()
        bankB.markPlaybackPairPrepared()
        lifecycleState = .prepared
    }
}

private enum DayObjectsPlaybackBankSlot: Hashable { case a, b }

@MainActor
private protocol DayObjectsPairedInstrumentBankLifecycleGate: AnyObject {
    func requestIndividualStop() -> Bool
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

    func attach(graph: any DayObjectsInstrumentBankGraph) throws {
        try shared.attach(graph: graph, slot: slot)
    }
    func detach() { shared.releaseAttachmentRequest(slot: slot) }
    func start() throws { try shared.requestIndividualStart(slot: slot) }
    func stop() { _ = shared.requestIndividualStop(slot: slot) }
    func requestIndividualStop() -> Bool {
        shared.requestIndividualStop(slot: slot)
    }
}

@MainActor
private final class DayObjectsSharedInstrumentBankEngine {
    private static let masterTrimDecibels = -3.0
    private let engine = AudioEngine()
    private var graphs: [DayObjectsPlaybackBankSlot: DayObjectsAudioKitInstrumentBankGraph] = [:]
    private var attachedSlots: Set<DayObjectsPlaybackBankSlot> = []
    private var outputMixer: Mixer?
    private var masterTrim: Fader?
    private var limiter: PeakLimiter?
    private var individuallyStartedSlots: Set<DayObjectsPlaybackBankSlot> = []
    private var pairIsRunning = false
    private var startCount = 0
    private var stopCount = 0
    var canAcquirePairOwnership: Bool {
        individuallyStartedSlots.isEmpty && !pairIsRunning
    }

    func attach(
        graph: any DayObjectsInstrumentBankGraph,
        slot: DayObjectsPlaybackBankSlot
    ) throws {
        guard let graph = graph as? DayObjectsAudioKitInstrumentBankGraph else {
            throw DayObjectsInstrumentBankError.preparationFailed(.engine)
        }
        if let existing = graphs[slot], existing !== graph {
            outputMixer = nil
            masterTrim = nil
            limiter = nil
        }
        graphs[slot] = graph
        attachedSlots.insert(slot)
        try connectIfComplete()
    }

    func releaseAttachmentRequest(slot: DayObjectsPlaybackBankSlot) {
        // Playback-pair graphs are retained for the pair's lifetime. An individual
        // bank cannot tear down the other slot's shared output topology.
        individuallyStartedSlots.remove(slot)
    }

    func requestIndividualStart(slot: DayObjectsPlaybackBankSlot) throws {
        guard !pairIsRunning else { throw DayObjectsInstrumentBankError.startFailed }
        guard !individuallyStartedSlots.contains(slot) else { return }
        guard attachedSlots.contains(slot), let limiter else {
            throw DayObjectsInstrumentBankError.notPrepared
        }
        engine.output = limiter
        if individuallyStartedSlots.isEmpty, !engine.avEngine.isRunning {
            try engine.start()
        }
        individuallyStartedSlots.insert(slot)
    }

    func requestIndividualStop(slot: DayObjectsPlaybackBankSlot) -> Bool {
        guard !pairIsRunning, individuallyStartedSlots.remove(slot) != nil else {
            return false
        }
        if individuallyStartedSlots.isEmpty {
            stopEngineIfRunning(countAsPairStop: false)
        }
        return true
    }

    func startPair() throws {
        guard attachedSlots.count == 2, let limiter else {
            throw DayObjectsInstrumentBankError.notPrepared
        }
        guard !pairIsRunning else { return }
        engine.output = limiter
        if !engine.avEngine.isRunning { try engine.start() }
        pairIsRunning = true
        startCount += 1
    }

    func stopPair() {
        guard pairIsRunning else { return }
        pairIsRunning = false
        stopEngineIfRunning(countAsPairStop: true)
    }

    func rollbackFailedPairStart() {
        pairIsRunning = false
        if engine.avEngine.isRunning { engine.stop() }
        engine.output = limiter
    }

    func metrics(
        lifecycleState: DayObjectsPlaybackBankPairLifecycleState,
        allocationFingerprint: [DayObjectsInstrumentBankAllocationFingerprint?]
    ) -> DayObjectsPlaybackBankPairMetrics {
        var fixedNodeIdentities: [ObjectIdentifier] = []
        if let outputMixer { fixedNodeIdentities.append(ObjectIdentifier(outputMixer)) }
        if let masterTrim { fixedNodeIdentities.append(ObjectIdentifier(masterTrim)) }
        if let limiter { fixedNodeIdentities.append(ObjectIdentifier(limiter)) }
        return .init(
            attachedBankCount: attachedSlots.count,
            sharedAudioEngineCount: 1,
            finalPeakLimiterCount: limiter == nil ? 0 : 1,
            sharedMasterTrimDecibels: Self.masterTrimDecibels,
            fixedSharedNodeCount: limiter == nil ? 0 : 3,
            fixedSharedNodeIdentities: fixedNodeIdentities,
            lifecycleState: lifecycleState,
            sharedEngineIsRunning: engine.avEngine.isRunning,
            sharedEngineStartCount: startCount,
            sharedEngineStopCount: stopCount,
            individualStartedBankCount: individuallyStartedSlots.count,
            allocationFingerprint: allocationFingerprint
        )
    }

    private func connectIfComplete() throws {
        guard attachedSlots.count == 2,
              let graphA = graphs[.a], let graphB = graphs[.b] else { return }
        if limiter == nil {
            let mixer = Mixer([graphA.limiter, graphB.limiter], name: "Day Objects shared worlds")
            let trim = Fader(
                mixer,
                gain: AUValue(pow(10, Self.masterTrimDecibels / 20))
            )
            outputMixer = mixer
            masterTrim = trim
            limiter = PeakLimiter(trim)
        }
        engine.output = limiter
    }

    private func stopEngineIfRunning(countAsPairStop: Bool) {
        if engine.avEngine.isRunning { engine.stop() }
        if countAsPairStop { stopCount += 1 }
        engine.output = limiter
    }
}
#endif
