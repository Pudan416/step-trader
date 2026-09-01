#if DEBUG || INTERNAL_BUILD
import Foundation

struct HappeningSoundRecipeID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: Int

    init?(rawValue: Int) {
        guard (1...30).contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int.self)
        guard let id = HappeningSoundRecipeID(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Happening sound recipe IDs must be in 1...30"
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
}
#endif
