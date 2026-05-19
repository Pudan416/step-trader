import Foundation

enum EnergyCategory: String, CaseIterable, Codable, Identifiable {
    case body      // Body (steps + movement activities)
    case mind      // Mind (attention + rest)
    case heart     // Heart (feelings + connection)

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "activity":                self = .body
        case "creativity", "recovery", "rest": self = .mind
        case "joys":                    self = .heart
        default:
            if let value = EnergyCategory(rawValue: raw) {
                self = value
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown EnergyCategory: \(raw)")
            }
        }
    }
}
