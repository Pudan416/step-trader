#if DEBUG || INTERNAL_BUILD
enum DayObjectsSoundWorld: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case feltAndWood
    case livingField
    case metalAndCurrent
    case electricDream

    var displayName: String {
        switch self {
        case .feltAndWood: "Acoustic Oddities"
        case .livingField: "Living Field"
        case .metalAndCurrent: "Industrial Ritual"
        case .electricDream: "Electric Dream"
        }
    }

    var guestNeighbors: [DayObjectsSoundWorld] {
        switch self {
        case .feltAndWood: [.livingField, .metalAndCurrent]
        case .livingField: [.feltAndWood, .electricDream]
        case .metalAndCurrent: [.electricDream, .feltAndWood]
        case .electricDream: [.livingField, .metalAndCurrent]
        }
    }

    var harmonyInstrumentIDs: Set<String> {
        switch self {
        case .feltAndWood, .livingField:
            ["pad.forgotten-stories", "keys.bb-slow-poly", "keys.jec-polaroids-2"]
        case .metalAndCurrent, .electricDream:
            ["pad.interstellar", "pad.whispering-sands", "keys.maschinenmensch"]
        }
    }

    var bassInstrumentIDs: Set<String> {
        switch self {
        case .feltAndWood, .livingField: ["bass.hey-jakob", "bass.jec-hollores-2"]
        case .metalAndCurrent, .electricDream: ["bass.analog-boom", "bass.bassliner"]
        }
    }

    var leadInstrumentIDs: Set<String> {
        switch self {
        case .feltAndWood, .livingField: ["lead.jec-softwah-2"]
        case .metalAndCurrent, .electricDream: ["lead.verbacious", "lead.bb-silver-screen"]
        }
    }

    var happeningRecipeRawIDs: Set<Int> {
        switch self {
        case .feltAndWood, .livingField:
            [4, 7, 9, 10, 11, 12, 15, 16, 17, 18, 24, 29, 30, 31, 32, 33, 34, 39, 40]
        case .metalAndCurrent, .electricDream:
            [1, 2, 3, 5, 6, 8, 13, 14, 19, 20, 21, 22, 23, 25, 26, 27, 28, 35, 36, 37, 38, 41, 42]
        }
    }
}
#endif
