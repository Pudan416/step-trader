#if DEBUG || INTERNAL_BUILD
import AudioKit
import AudioKitEX
import AudioToolbox
import AVFoundation
import Foundation
import SoundpipeAudioKit

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
        var acceptedParameterValues: [String: Double] = [
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
        ]
        if let bassParameters = graphs.first?.bassSaturationParameterValues {
            acceptedParameterValues.merge(bassParameters) { _, latest in latest }
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
            acceptedParameterValues: acceptedParameterValues,
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
            Self.masterTrimDecibels + (state.worldGroupCalibration?.masterMakeupDB ?? 0)
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
#endif
