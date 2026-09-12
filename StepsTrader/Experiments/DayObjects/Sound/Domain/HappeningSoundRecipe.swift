import Foundation

struct HappeningSoundRecipeID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: Int

    init?(rawValue: Int) {
        guard (1...42).contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int.self)
        guard let id = HappeningSoundRecipeID(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Happening sound recipe IDs must be in 1...42"
            )
        }
        self = id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct HappeningSampleSource: Equatable, Codable, Sendable {
    let resourceName: String
    let rootMIDI: UInt8
    let sha256: String
}

enum HappeningRecipeFamily: String, Codable, CaseIterable, Sendable {
    case synthPluck
    case acousticMallet
    case acousticBell
    case softOneShot
    case texture
}

enum HappeningPaletteKind: String, Codable, CaseIterable, Sendable {
    case synth
    case organic
    case hybrid
}

enum HappeningPitchBehavior: Equatable, Codable, Sendable {
    case tonal(preferredRange: ClosedRange<UInt8>)
    case resonantNoise(
        referenceMIDI: UInt8,
        preferredRange: ClosedRange<UInt8>,
        resonatorTargetPitchClasses: [UInt8]
    )
    case unpitched
}

struct HappeningSoundRecipe: Equatable, Codable, Sendable {
    let id: HappeningSoundRecipeID
    let label: String
    let workingName: String
    let paletteKind: HappeningPaletteKind
    let topology: String
    let attackTopology: String
    let tailTopology: String
    let family: HappeningRecipeFamily
    let sources: [HappeningSampleSource]
    let pitch: HappeningPitchBehavior
    let gainDB: Double
    let attackSeconds: Double
    let releaseSeconds: Double
    let delayMix: Double
    let delayFeedback: Double
    let reverbMix: Double
    let filterStartHz: Double
    let filterEndHz: Double

    init(
        id: HappeningSoundRecipeID,
        label: String,
        workingName: String = "Test happening",
        paletteKind: HappeningPaletteKind = .hybrid,
        topology: String = "test-fixture",
        attackTopology: String = "test-attack",
        tailTopology: String = "test-tail",
        family: HappeningRecipeFamily,
        sources: [HappeningSampleSource],
        pitch: HappeningPitchBehavior,
        gainDB: Double,
        attackSeconds: Double,
        releaseSeconds: Double,
        delayMix: Double,
        delayFeedback: Double,
        reverbMix: Double,
        filterStartHz: Double,
        filterEndHz: Double
    ) {
        self.id = id
        self.label = label
        self.workingName = workingName
        self.paletteKind = paletteKind
        self.topology = topology
        self.attackTopology = attackTopology
        self.tailTopology = tailTopology
        self.family = family
        self.sources = sources
        self.pitch = pitch
        self.gainDB = gainDB
        self.attackSeconds = attackSeconds
        self.releaseSeconds = releaseSeconds
        self.delayMix = delayMix
        self.delayFeedback = delayFeedback
        self.reverbMix = reverbMix
        self.filterStartHz = filterStartHz
        self.filterEndHz = filterEndHz
    }
}
