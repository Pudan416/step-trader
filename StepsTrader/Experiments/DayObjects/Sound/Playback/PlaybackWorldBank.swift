#if DEBUG || INTERNAL_BUILD
import Foundation

enum PlaybackWorldBankConfiguration {
    static let playbackWorld = DayObjectsInstrumentBankConfiguration(
        tonalPools: [
            .init(name: PoolName.drone.rawValue, capacity: 1, reservesLeadVoice: false),
            .init(name: PoolName.primaryPad.rawValue, capacity: 4, reservesLeadVoice: false),
            .init(name: PoolName.secondaryPadOrKeys.rawValue, capacity: 2, reservesLeadVoice: false),
            .init(name: PoolName.lead.rawValue, capacity: 1, reservesLeadVoice: true),
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

    enum PoolName: String, CaseIterable, Sendable {
        case drone
        case primaryPad = "primary-pad"
        case secondaryPadOrKeys = "secondary-pad-or-keys"
        case lead

        // Transitional source compatibility until Task 5 moves the existing
        // scheduler to the sample pool. This is an alias, not an allocated
        // Happening tonal pool, and therefore does not change allCases or the
        // fixed eight-voice tonal budget.
        static var happenings: Self { .secondaryPadOrKeys }
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
final class PlaybackWorldBank {
    let instrumentBank: DayObjectsInstrumentBankProtocol

    var drums: DayObjectsDrumBankProtocol { instrumentBank.drums }
    var piano: DayObjectsPianoPoolProtocol { instrumentBank.piano }
    var happenings: DayObjectsHappeningSamplePoolProtocol { instrumentBank.happenings }
    var outputGainMetrics: DayObjectsBankOutputGainMetrics {
        instrumentBank.outputGainMetrics
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
        guard !isPrepared else { return }
        try instrumentBank.prepare(configuration: .playbackWorld)
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
            name = .primaryPad
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

    func releaseAll() {
        instrumentBank.releaseAll()
    }

    func recycleAfterTailsDrain() {
        guard isPrepared else { return }
        releaseAll()
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

    func applyProgramEffects(
        masterLinearGain: Double,
        delayFeedback: Double,
        reverbFeedback: Double,
        rampDurationSeconds: TimeInterval
    ) {
        instrumentBank.applyProgramEffects(
            masterLinearGain: masterLinearGain,
            delayFeedback: delayFeedback,
            reverbFeedback: reverbFeedback,
            rampDurationSeconds: rampDurationSeconds
        )
    }
}
#endif
