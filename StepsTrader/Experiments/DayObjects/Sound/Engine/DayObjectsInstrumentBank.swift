#if DEBUG || INTERNAL_BUILD
import AudioKit
import AudioKitEX
import Foundation

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
                    piano: pianoAdapter.adapter
                )
            },
            engine: DayObjectsAudioKitInstrumentBankEngine()
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
            engine.stop()
            engine.detach()
            self.prepared = nil
            throw DayObjectsInstrumentBankError.startFailed
        }
    }

    func stop() async {
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
    func releaseAll() { adapter.releaseAll() }
}

private final class DayObjectsAudioKitPianoPoolAdapter: DayObjectsPianoPoolProtocol {
    let adapter: DayObjectsAudioKitFeltPiano
    init(_ adapter: DayObjectsAudioKitFeltPiano) { self.adapter = adapter }
    var metrics: DayObjectsFeltPianoMetrics { adapter.piano.metrics }
    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken? { adapter.piano.noteOn(midiNote, velocity: velocity) }
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
    let room: Reverb
    let reverb: Reverb
    let masterTrim: Fader
    let limiter: PeakLimiter
    private let tonalPools: [DayObjectsAudioKitTonalPool]
    private let drums: DayObjectsAudioKitDrumBank
    private let piano: DayObjectsAudioKitFeltPiano

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

    init(tonalPools: [DayObjectsAudioKitTonalPool], drums: DayObjectsAudioKitDrumBank, piano: DayObjectsAudioKitFeltPiano) {
        self.tonalPools = tonalPools
        self.drums = drums
        self.piano = piano
        tonalBus = Mixer(tonalPools.map(\.output) + [piano.output], name: "Day Objects tonal bus")
        drumBus = Mixer([drums.output], name: "Day Objects drum bus")
        tonalTrim = Fader(tonalBus, gain: AUValue(DayObjectsAudioParameters.linearGain(decibels: -10)))
        drumTrim = Fader(drumBus, gain: AUValue(DayObjectsAudioParameters.linearGain(decibels: -12)))
        programBus = Mixer([tonalTrim, drumTrim], name: "Day Objects program bus")
        room = Reverb(programBus, dryWetMix: 0.12)
        reverb = Reverb(room, dryWetMix: 0.10)
        masterTrim = Fader(reverb, gain: AUValue(DayObjectsAudioParameters.linearGain(decibels: -8)))
        limiter = PeakLimiter(masterTrim)
    }

    func synchronizeForStart() throws {
        tonalPools.forEach { $0.synchronizeGraphIfAttached() }
    }

    private static func decibels(_ gain: AUValue) -> Double { 20 * log10(Double(gain)) }
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
#endif
