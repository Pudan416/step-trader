#if DEBUG || INTERNAL_BUILD
import Foundation

enum PlaybackWorldBankConfiguration {
    static let playbackWorld = DayObjectsInstrumentBankConfiguration(
        tonalPools: [
            .init(name: PoolName.drone.rawValue, capacity: 2, reservesLeadVoice: false),
            .init(name: PoolName.primaryPad.rawValue, capacity: 8, reservesLeadVoice: false),
            .init(name: PoolName.secondaryPadOrKeys.rawValue, capacity: 6, reservesLeadVoice: false),
            .init(name: PoolName.happenings.rawValue, capacity: 6, reservesLeadVoice: false),
            .init(name: PoolName.lead.rawValue, capacity: 1, reservesLeadVoice: true),
        ],
        pianoVoiceCount: 6,
        drumOverlapCounts: [
            .kickSoft: 2,
            .kickFull: 2,
            .hatClosed: 6,
            .hatOpen: 3,
            .shaker: 4,
            .clapSoft: 3,
            .stick: 3,
            .organicHigh: 4,
            .organicLow: 4,
        ]
    )

    enum PoolName: String, CaseIterable, Sendable {
        case drone
        case primaryPad = "primary-pad"
        case secondaryPadOrKeys = "secondary-pad-or-keys"
        case happenings
        case lead
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
}

@MainActor
final class PlaybackWorldBank {
    let instrumentBank: DayObjectsInstrumentBankProtocol

    var drums: DayObjectsDrumBankProtocol { instrumentBank.drums }
    var piano: DayObjectsPianoPoolProtocol { instrumentBank.piano }

    var metrics: PlaybackWorldBankMetrics {
        let tonalMetrics = pools.values.map(\.metrics)
        let pianoMetrics = piano.metrics
        return .init(
            allocatedTonalVoiceCount: tonalMetrics.reduce(0) { $0 + $1.allocatedVoiceCount },
            allocatedPianoVoiceCount: pianoMetrics.allocatedPlayerCount,
            allocatedDrumPlayerCount: drums.metrics.allocatedPlayerCount,
            activeTonalVoiceCount: tonalMetrics.reduce(0) { $0 + $1.activeVoiceCount },
            activePianoVoiceCount: pianoMetrics.activeNoteCount
        )
    }

    private var pools: [PlaybackWorldBankConfiguration.PoolName: DayObjectsTonalVoicePoolProtocol] = [:]
    private(set) var isPrepared = false

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
}
#endif
