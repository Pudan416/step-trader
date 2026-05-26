import Foundation

enum Tariff: String, CaseIterable, Codable {
    case hard = "hard"     // 1000 steps = 1 minute
    case medium = "medium" // 500 steps = 1 minute
    case easy = "easy"     // 100 steps = 1 minute
    case free = "free"     // 0 steps = 1 minute (free entry tracking only)

    /// Backward-compatible decoding: accept legacy "lite" raw value.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw == "lite" {
            self = .easy
        } else if let value = Tariff(rawValue: raw) {
            self = value
        } else {
            self = .easy
        }
    }
    
    var stepsPerMinute: Double {
        switch self {
        case .free: 0
        case .easy: 100
        case .medium: 500
        case .hard: 1000
        }
    }
    
    var displayName: String {
        switch self {
        case .free: "Free"
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        }
    }
    
    var entryCostSteps: Int {
        switch self {
        case .free: 0
        case .easy: 10
        case .medium: 50
        case .hard: 100
        }
    }
    
    var description: String {
        switch self {
        case .free: "0 steps"
        case .easy: "10 steps"
        case .medium: "50 steps"
        case .hard: "100 steps"
        }
    }
}
