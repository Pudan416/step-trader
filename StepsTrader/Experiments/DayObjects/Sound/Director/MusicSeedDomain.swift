#if DEBUG || INTERNAL_BUILD
struct MusicSeedDomain: Equatable, Sendable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension MusicSeedDomain {
    static let worldStyle = MusicSeedDomain("world.style")
    static let worldMood = MusicSeedDomain("world.mood")
    static let worldGuest = MusicSeedDomain("world.guest")
    static let worldKey = MusicSeedDomain("world.key")
    static let worldMode = MusicSeedDomain("world.mode")
    static let worldProgression = MusicSeedDomain("world.progression")
    static let rhythmFamily = MusicSeedDomain("rhythm.family")
    static let rhythmPattern = MusicSeedDomain("rhythm.pattern")
    static let rhythmHumanization = MusicSeedDomain("rhythm.humanization")
    static let grooveMode = MusicSeedDomain("groove.mode")
    static let grooveThinning = MusicSeedDomain("groove.thinning")
    static let bassInstrument = MusicSeedDomain("bass.instrument")
    static let bassPattern = MusicSeedDomain("bass.pattern")
    static let bassArticulation = MusicSeedDomain("bass.articulation")
    static let harmonyInstruments = MusicSeedDomain("harmony.instruments")
    static let effects = MusicSeedDomain("effects")

    static func happeningIdentity(stableID: String) -> MusicSeedDomain {
        MusicSeedDomain("happening.\(escapedStableID(stableID)).identity")
    }

    static func happeningSchedule(stableID: String) -> MusicSeedDomain {
        MusicSeedDomain("happening.\(escapedStableID(stableID)).schedule")
    }

    private static func escapedStableID(_ stableID: String) -> String {
        stableID.utf8.map { byte in
            switch byte {
            case 48...57, 65...90, 97...122, 45, 95:
                return String(UnicodeScalar(byte))
            default:
                return percentEscape(byte)
            }
        }.joined()
    }

    private static func percentEscape(_ byte: UInt8) -> String {
        let hexadecimal = "0123456789ABCDEF"
        let high = hexadecimal.index(hexadecimal.startIndex, offsetBy: Int(byte >> 4))
        let low = hexadecimal.index(hexadecimal.startIndex, offsetBy: Int(byte & 0x0F))
        return "%\(hexadecimal[high])\(hexadecimal[low])"
    }
}
#endif
