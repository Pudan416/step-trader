import AudioKit
import AudioKitEX
import AudioToolbox
import AVFoundation
import Foundation
import SoundpipeAudioKit

final class DayObjectsAudioKitInstrumentBankEngine: DayObjectsInstrumentBankEngine {
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
