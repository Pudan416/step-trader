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
    private(set) var soundWorldCatalogError: Error?
    private let descriptorByID: [DayObjectsInstrumentID: DayObjectsInstrumentDescriptor]
    private let tonalInstrumentLoader: TonalInstrumentLoader
    private let tonalPoolFactory: TonalPoolFactory
    private let drumBankFactory: DrumBankFactory
    private let pianoPoolFactory: PianoPoolFactory
    private let happeningPoolFactory: HappeningPoolFactory
    private let graphFactory: GraphFactory
    private let engine: DayObjectsInstrumentBankEngine
    private var backgroundMusicBuilder: DayObjectsMusicResourceBuilder?
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
        soundWorldResources: DayObjectsSoundWorldResources? = nil,
        tonalVoiceProfile: DayObjectsTonalVoiceProfile = .fullFidelity,
        audioHostTimeProvider: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        let happenings = DayObjectsHappeningSamplePool(bundle: bundle, clock: audioHostTimeProvider)
        self.init(
            bundle: bundle,
            soundWorldResources: soundWorldResources,
            engine: DayObjectsAudioKitInstrumentBankEngine(happenings: happenings),
            happenings: happenings,
            tonalVoiceProfile: tonalVoiceProfile,
            audioHostTimeProvider: audioHostTimeProvider
        )
    }

    private convenience init(
        bundle: Bundle,
        soundWorldResources: DayObjectsSoundWorldResources? = nil,
        engine: DayObjectsInstrumentBankEngine,
        happenings: DayObjectsHappeningSamplePool,
        tonalVoiceProfile: DayObjectsTonalVoiceProfile = .fullFidelity,
        audioHostTimeProvider: @escaping () -> TimeInterval
    ) {
        let resources = soundWorldResources ?? DayObjectsSoundWorldResources(bundle: bundle)
        self.init(
            descriptors: resources.descriptors,
            tonalInstrumentLoader: {
                try resources.tonalInstruments()
            },
            tonalPoolFactory: { specification, instruments in
                // The prepared pool is detached and does not start an engine or audio session.
                return DayObjectsAudioKitTonalPoolAdapter(
                    DayObjectsAudioKitTonalPool(
                    specification: specification,
                    instruments: instruments,
                    voiceProfile: tonalVoiceProfile,
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
        soundWorldCatalogError = resources.catalogError
        backgroundMusicBuilder = DayObjectsMusicResourceBuilder { configuration in
            try Self.buildDetachedMusicResources(configuration, bundle: bundle, resources: resources,
                                                voiceProfile: tonalVoiceProfile, clock: audioHostTimeProvider)
        }
    }

    static func makePlaybackPair(
        bundle: Bundle = .main,
        soundWorldResources: DayObjectsSoundWorldResources? = nil,
        startFailureProvider: @escaping () -> DayObjectsPlaybackBankPairStartFailure? = { nil },
        individualStartFailureProvider: @escaping () -> Error? = { nil },
        outputGainHostTimeProvider: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) -> DayObjectsPlaybackBankPair {
        let resources = soundWorldResources ?? DayObjectsSoundWorldResources(bundle: bundle)
        let happenings = DayObjectsHappeningSamplePool(bundle: bundle)
        let sharedEngine = DayObjectsSharedInstrumentBankEngine(
            happenings: happenings,
            individualStartFailureProvider: individualStartFailureProvider
        )
        let bankA = DayObjectsInstrumentBank(
            bundle: bundle,
            soundWorldResources: resources,
            engine: DayObjectsPairedInstrumentBankEngine(slot: .a, shared: sharedEngine),
            happenings: happenings,
            audioHostTimeProvider: outputGainHostTimeProvider
        )
        let bankB = DayObjectsInstrumentBank(
            bundle: bundle,
            soundWorldResources: resources,
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
        try prepareFullMusic(
            configuration,
            initialHappeningRecipeIDs: Set(HappeningSoundCatalog.recipes.map(\.id))
        )
    }

    /// Prepares a complete music graph while decoding only the happenings the
    /// initial plan can actually play. `HappeningScheduler` prepares additions
    /// individually, so mobile playback does not need the entire catalog on its
    /// cold-start path.
    func prepare(
        configuration: DayObjectsInstrumentBankConfiguration,
        happeningRecipeIDs: Set<HappeningSoundRecipeID>
    ) throws {
        try prepareFullMusic(
            configuration,
            initialHappeningRecipeIDs: happeningRecipeIDs
        )
    }

    /// Only unattached resources leave the main actor. Graph ownership and commit
    /// stay serialized with start/stop, which await this preparation before teardown.
    func prepareForPlayback(
        configuration: DayObjectsInstrumentBankConfiguration,
        happeningRecipeIDs: Set<HappeningSoundRecipeID>
    ) async throws {
        if prepared?.configuration != nil || backgroundMusicBuilder == nil {
            try prepare(configuration: configuration, happeningRecipeIDs: happeningRecipeIDs)
            return
        }
        try validate(configuration)
        let resources = try await backgroundMusicBuilder!.build(configuration)
        try Task.checkCancellation()
        try prepareFullMusic(configuration, initialHappeningRecipeIDs: happeningRecipeIDs,
                             detachedResources: resources)
    }

    func prepare(level: PreparationLevel) throws {
        switch level {
        case let .sampleOnly(recipeIDs):
            try prepareSamples(recipeIDs)
        case let .fullMusic(configuration):
            try prepare(configuration: configuration)
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

    private func prepareFullMusic(
        _ configuration: DayObjectsInstrumentBankConfiguration,
        initialHappeningRecipeIDs: Set<HappeningSoundRecipeID>,
        detachedResources: DayObjectsDetachedMusicResources? = nil
    ) throws {
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
            try builtHappenings.prepare(recipeIDs: initialHappeningRecipeIDs)
            if let detachedResources {
                builtTonalPools = detachedResources.tonalPools
                builtDrums = detachedResources.drums
                builtPiano = detachedResources.piano
            } else {
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
                do {
                    builtPiano = configuration.pianoVoiceCount == 0
                        ? inactivePiano
                        : try pianoPoolFactory(configuration.pianoVoiceCount)
                } catch { throw DayObjectsInstrumentBankError.preparationFailed(.piano) }
            }
            guard let builtDrums, let builtPiano else { throw DayObjectsInstrumentBankError.preparationFailed(.graph) }

            let graph: DayObjectsInstrumentBankGraph
            do {
                graph = try graphFactory(
                    builtTonalPools,
                    builtDrums,
                    configuration.pianoVoiceCount == 0 ? nil : builtPiano,
                    builtHappenings
                )
            }
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

    func advanceOfflineModulation() {
        (prepared?.graph as? DayObjectsAudioKitInstrumentBankGraph)?.advanceOfflineModulation()
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

    func acquireLivePlaybackLease() throws {
        guard !holdsLivePlaybackLease else { return }
        try DayObjectsAudioPlaybackLease.shared.acquireLive(owner: self)
        holdsLivePlaybackLease = true
    }

    func releaseLivePlaybackLease() {
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

    func synchronizePreparedGraphForPlaybackPair() throws {
        guard let prepared else { throw DayObjectsInstrumentBankError.notPrepared }
        try prepared.graph.synchronizeForStart()
    }

    func markPlaybackPairPrepared() {
        guard prepared != nil else { return }
        prepared?.state = .prepared
        prepared?.isAttached = true
    }

    func markPlaybackPairStarted() {
        guard prepared != nil else { return }
        prepared?.state = .started
        prepared?.isAttached = true
    }

    private func validate(_ configuration: DayObjectsInstrumentBankConfiguration) throws {
        var seen = Set<String>()
        for name in configuration.tonalPools.map(\.name) where !seen.insert(name).inserted {
            throw DayObjectsInstrumentBankError.duplicateTonalPoolName(name)
        }
        guard (0...8).contains(configuration.pianoVoiceCount) else { throw DayObjectsInstrumentBankError.invalidPianoVoiceCount }
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

    nonisolated private static func buildDetachedMusicResources(
        _ configuration: DayObjectsInstrumentBankConfiguration,
        bundle: Bundle,
        resources: DayObjectsSoundWorldResources,
        voiceProfile: DayObjectsTonalVoiceProfile,
        clock: @escaping () -> TimeInterval
    ) throws -> DayObjectsDetachedMusicResources {
        let instruments: [DayObjectsInstrumentID: NormalizedSynthVoice]
        do { instruments = try resources.tonalInstruments() }
        catch { throw DayObjectsInstrumentBankError.preparationFailed(.tonalInstruments) }
        let descriptors = Dictionary(uniqueKeysWithValues: resources.descriptors.map { ($0.id, $0) })
        let pools: [DayObjectsTonalVoicePoolProtocol] = configuration.tonalPools.map { specification in
            DayObjectsCategoryValidatedTonalPool(
                pool: DayObjectsAudioKitTonalPoolAdapter(DayObjectsAudioKitTonalPool(
                    specification: specification, instruments: instruments,
                    voiceProfile: voiceProfile, hostTimeProvider: clock)),
                descriptors: descriptors, preparedInstruments: instruments
            )
        }
        let drums = DayObjectsAudioKitDrumBankAdapter(.init(resourceResolver: { sample in
            let filename = sample.rawValue as NSString
            return bundle.url(forResource: filename.deletingPathExtension,
                              withExtension: filename.pathExtension, subdirectory: "Drums")
        }, recipes: drumRecipes(configuration.drumOverlapCounts), hostTimeProvider: clock))
        let piano: DayObjectsPianoPoolProtocol
        if configuration.pianoVoiceCount == 0 {
            piano = DayObjectsInactivePianoPool()
        } else {
            do {
                let samples = try FeltPianoManifest.load(from: bundle)
                piano = DayObjectsAudioKitPianoPoolAdapter(DayObjectsAudioKitFeltPiano(
                    samples: samples, recipe: pianoRecipe(voiceCount: configuration.pianoVoiceCount),
                    resourceResolver: { sample in
                        let filename = sample.filename as NSString
                        return bundle.url(forResource: filename.deletingPathExtension,
                                          withExtension: filename.pathExtension, subdirectory: "FeltPiano")
                    }))
            } catch { throw DayObjectsInstrumentBankError.preparationFailed(.piano) }
        }
        return .init(tonalPools: pools, drums: drums, piano: piano)
    }

    nonisolated private static func drumRecipes(_ requested: [DayObjectsDrumVoice: Int]) -> [DayObjectsDrumVoice: DayObjectsDrumRecipe] {
        Dictionary(uniqueKeysWithValues: DayObjectsDrumVoice.allCases.map { voice in
            let base = DayObjectsDrumRecipe.recipe(for: voice)
            let overlap = requested[voice] ?? base.overlapCount
            return (voice, .init(voice: base.voice, primarySample: base.primarySample, fallbackSample: base.fallbackSample, synthesis: base.synthesis, sinePitchDrop: base.sinePitchDrop, noiseAmplitude: base.noiseAmplitude, overlapCount: overlap, transientFilterCutoffHz: base.transientFilterCutoffHz, noiseFilterCutoffHz: base.noiseFilterCutoffHz, highPassCutoffHz: base.highPassCutoffHz, outputTrimDecibels: base.outputTrimDecibels, variation: base.variation, allowsPitchDrift: base.allowsPitchDrift, allowsBroadbandSustainedNoise: base.allowsBroadbandSustainedNoise, usesSawOscillator: base.usesSawOscillator, delayFeedback: base.delayFeedback))
        })
    }

    nonisolated private static func pianoRecipe(voiceCount: Int) -> DayObjectsFeltPianoRecipe {
        let base = DayObjectsFeltPianoRecipe.default
        return .init(attackSeconds: base.attackSeconds, releaseSeconds: base.releaseSeconds, lowPassCutoffHz: base.lowPassCutoffHz, mechanicalOnsetHighPassHz: base.mechanicalOnsetHighPassHz, mechanicalNoiseGain: base.mechanicalNoiseGain, noteTrimDB: base.noteTrimDB, roomSend: base.roomSend, reverbSend: base.reverbSend, maximumPolyphony: voiceCount)
    }
}

/// Exclusive handoff: these nodes are constructed without an engine on the
/// resource queue, then used only by the receiving main-actor bank after await.
private struct DayObjectsDetachedMusicResources: @unchecked Sendable {
    let tonalPools: [DayObjectsTonalVoicePoolProtocol]
    let drums: DayObjectsDrumBankProtocol
    let piano: DayObjectsPianoPoolProtocol
}

/// The production builder captures immutable resource descriptions, never a bank
/// or its mutable playback state. One queue also bounds concurrent node creation.
private final class DayObjectsMusicResourceBuilder: @unchecked Sendable {
    private static let queue = DispatchQueue(label: "Nowhere.music.resources", qos: .userInitiated)
    private let make: (DayObjectsInstrumentBankConfiguration) throws -> DayObjectsDetachedMusicResources

    init(make: @escaping (DayObjectsInstrumentBankConfiguration) throws -> DayObjectsDetachedMusicResources) {
        self.make = make
    }

    func build(_ configuration: DayObjectsInstrumentBankConfiguration) async throws -> DayObjectsDetachedMusicResources {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            Self.queue.async { [self] in
                continuation.resume(with: Result { try autoreleasepool { try make(configuration) } })
            }
        }
    }
}
