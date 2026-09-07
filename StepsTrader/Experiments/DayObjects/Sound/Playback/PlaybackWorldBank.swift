#if DEBUG || INTERNAL_BUILD
import Foundation

enum PlaybackWorldBankConfiguration {
    static let playbackWorld = DayObjectsInstrumentBankConfiguration(
        tonalPools: [
            .init(name: PoolName.drone.rawValue, capacity: 1, reservesLeadVoice: false),
            .init(name: PoolName.primaryPad.rawValue, capacity: 4, reservesLeadVoice: false),
            .init(name: PoolName.secondaryPadOrKeys.rawValue, capacity: 2, reservesLeadVoice: false),
            .init(name: PoolName.lead.rawValue, capacity: 1, reservesLeadVoice: true),
            .init(name: PoolName.bass.rawValue, capacity: 1, reservesLeadVoice: false),
        ],
        pianoVoiceCount: 2,
        drumOverlapCounts: [
            .kickSoft: 1,
            .kickFull: 1,
            .hatClosed: 2,
            .hatOpen: 1,
            .shaker: 1,
            .clapSoft: 1,
            .stick: 1,
            .organicHigh: 1,
            .organicLow: 1,
        ]
    )

    /// Phone playback uses the tonal keys already present in the harmony
    /// arrangement. Preloading two copies of all twelve felt-piano samples
    /// blocked the UI for several seconds before the first sound.
    static let mobilePlaybackWorld = DayObjectsInstrumentBankConfiguration(
        tonalPools: playbackWorld.tonalPools,
        pianoVoiceCount: 0,
        drumOverlapCounts: playbackWorld.drumOverlapCounts
    )

    enum PoolName: String, CaseIterable, Sendable {
        case drone
        case primaryPad = "primary-pad"
        case secondaryPadOrKeys = "secondary-pad-or-keys"
        case lead
        case bass
    }
}

extension DayObjectsInstrumentBankConfiguration {
    static let playbackWorld = PlaybackWorldBankConfiguration.playbackWorld
}

struct PlaybackWorldBankMetrics: Equatable, Sendable {
    let allocatedTonalVoiceCount: Int
    let allocatedPianoVoiceCount: Int
    let allocatedDrumPlayerCount: Int
    let activeTonalVoiceCount: Int
    let activePianoVoiceCount: Int
    let recycleCount: Int
}

@MainActor
final class PlaybackWorldBank: BassDuckBackend {
    let instrumentBank: DayObjectsInstrumentBankProtocol

    var drums: DayObjectsDrumBankProtocol { instrumentBank.drums }
    var piano: DayObjectsPianoPoolProtocol { instrumentBank.piano }
    var happenings: DayObjectsHappeningSamplePoolProtocol { instrumentBank.happenings }
    var outputGainMetrics: DayObjectsBankOutputGainMetrics {
        instrumentBank.outputGainMetrics
    }
    var bassDuckGainMetrics: BassDuckGainMetrics {
        instrumentBank.bassDuckGainMetrics
    }
    var programEffectMetrics: DayObjectsProgramEffectMetrics {
        instrumentBank.programEffectMetrics
    }

    var metrics: PlaybackWorldBankMetrics {
        let tonalMetrics = pools.values.map(\.metrics)
        let pianoMetrics = piano.metrics
        return .init(
            allocatedTonalVoiceCount: tonalMetrics.reduce(0) { $0 + $1.allocatedVoiceCount },
            allocatedPianoVoiceCount: pianoMetrics.allocatedPlayerCount,
            allocatedDrumPlayerCount: drums.metrics.allocatedPlayerCount,
            activeTonalVoiceCount: tonalMetrics.reduce(0) { $0 + $1.activeVoiceCount },
            activePianoVoiceCount: pianoMetrics.activeNoteCount,
            recycleCount: recycleCount
        )
    }

    private var pools: [PlaybackWorldBankConfiguration.PoolName: DayObjectsTonalVoicePoolProtocol] = [:]
    private(set) var isPrepared = false
    private(set) var recycleCount = 0

    init(instrumentBank: DayObjectsInstrumentBankProtocol) {
        self.instrumentBank = instrumentBank
    }

    func prepare() throws {
        try prepare(happeningRecipeIDs: nil)
    }

    func prepare(
        happeningRecipeIDs: Set<HappeningSoundRecipeID>,
        configuration: DayObjectsInstrumentBankConfiguration = .playbackWorld
    ) throws {
        try prepare(
            happeningRecipeIDs: Optional(happeningRecipeIDs),
            configuration: configuration
        )
    }

    private func prepare(
        happeningRecipeIDs: Set<HappeningSoundRecipeID>?,
        configuration: DayObjectsInstrumentBankConfiguration = .playbackWorld
    ) throws {
        guard !isPrepared else { return }
        if let happeningRecipeIDs,
           let focusedBank = instrumentBank as? DayObjectsInstrumentBank {
            try focusedBank.prepare(
                configuration: configuration,
                happeningRecipeIDs: happeningRecipeIDs
            )
        } else {
            try instrumentBank.prepare(configuration: configuration)
        }
        var preparedPools: [PlaybackWorldBankConfiguration.PoolName: DayObjectsTonalVoicePoolProtocol] = [:]
        for name in PlaybackWorldBankConfiguration.PoolName.allCases {
            preparedPools[name] = try instrumentBank.tonalPool(named: name.rawValue)
        }
        pools = preparedPools
        isPrepared = true
    }

    func tonalPool(for role: HarmonyRole) throws -> DayObjectsTonalVoicePoolProtocol {
        let name: PlaybackWorldBankConfiguration.PoolName
        switch role {
        case .drone:
            name = .drone
        case .primaryPad:
            name = .primaryPad
        case .secondaryPadOrKeys, .innerMotion:
            name = .secondaryPadOrKeys
        case .pianoOrKeysAccents:
            // Tonal keys must remain audible while the primary chord crossfades.
            // Felt-piano targets bypass this routing and retain their piano pool.
            name = .secondaryPadOrKeys
        }
        guard let pool = pools[name] else {
            throw DayObjectsInstrumentBankError.unknownTonalPool(name.rawValue)
        }
        return pool
    }

    func tonalPool(named name: PlaybackWorldBankConfiguration.PoolName) throws -> DayObjectsTonalVoicePoolProtocol {
        guard let pool = pools[name] else {
            throw DayObjectsInstrumentBankError.unknownTonalPool(name.rawValue)
        }
        return pool
    }

    func tonalPool(forBass instrumentID: DayObjectsInstrumentID) throws -> DayObjectsTonalVoicePoolProtocol {
        guard let descriptor = instrumentBank.descriptors.first(where: { $0.id == instrumentID }) else {
            throw DayObjectsInstrumentBankError.unknownInstrument(instrumentID)
        }
        guard descriptor.category == .bass else {
            throw DayObjectsInstrumentBankError.invalidTonalInstrumentCategory(descriptor.category)
        }
        return try tonalPool(named: .bass)
    }

    func releaseWorldLocalVoices() {
        instrumentBank.releaseWorldLocalVoices()
    }

    func releaseAllIncludingSharedHappenings() {
        instrumentBank.releaseAllIncludingSharedHappenings()
    }

    func recycleAfterTailsDrain() {
        guard isPrepared else { return }
        releaseWorldLocalVoices()
        recycleCount += 1
    }

    func setOutputGain(_ linearGain: Double, rampDurationSeconds: TimeInterval) {
        instrumentBank.setOutputGain(
            linearGain,
            rampDurationSeconds: rampDurationSeconds
        )
    }

    func scheduleOutputGain(
        _ linearGain: Double,
        startingAtHostTime startHostTime: TimeInterval,
        endingAtHostTime endHostTime: TimeInterval
    ) {
        instrumentBank.scheduleOutputGain(
            linearGain,
            startingAtHostTime: startHostTime,
            endingAtHostTime: endHostTime
        )
    }

    func apply(_ command: BassDuckCommand) {
        instrumentBank.scheduleBassDuck(command)
    }

    func resetBassDuckGain() {
        instrumentBank.resetBassDuckGain()
    }

    func applyMix(_ state: DayObjectsMixState) {
        instrumentBank.applyMix(state)
    }
}
#endif
