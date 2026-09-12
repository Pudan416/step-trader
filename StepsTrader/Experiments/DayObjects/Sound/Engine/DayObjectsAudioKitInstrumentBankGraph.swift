import AudioKit
import AudioKitEX
import AudioToolbox
import AVFoundation
import Foundation
import SoundpipeAudioKit

final class DayObjectsAudioKitInstrumentBankGraph: DayObjectsInstrumentBankGraph {
    private static let bassSaturationPregain: AUValue = 1.06
    private static let bassSaturationPostgain: AUValue = 0.96
    private static let bassSaturationDryWet: AUValue = 0.06

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

    func advanceOfflineModulation() {
        tonalPools.forEach { $0.advanceOfflineModulation() }
    }
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

    var bassSaturationParameterValues: [String: Double] {
        guard let bassSaturation else { return [:] }
        return [
            "bass.saturation.pregain": Double(bassSaturation.$pregain.parameter.value),
            "bass.saturation.postgain": Double(bassSaturation.$postgain.parameter.value),
            "bass.saturation.dryWet": Double(bassSaturation.$dryWetMix.parameter.value),
        ]
    }

    init(
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
                $0,
                pregain: Self.bassSaturationPregain,
                postgain: Self.bassSaturationPostgain,
                positiveShapeParameter: 0, negativeShapeParameter: 0,
                dryWetMix: Self.bassSaturationDryWet
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
            setImmediately(saturation.$pregain, to: Self.bassSaturationPregain)
            setImmediately(saturation.$postgain, to: Self.bassSaturationPostgain)
            setImmediately(saturation.$positiveShapeParameter, to: 0)
            setImmediately(saturation.$negativeShapeParameter, to: 0)
            setImmediately(saturation.$dryWetMix, to: Self.bassSaturationDryWet)
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
