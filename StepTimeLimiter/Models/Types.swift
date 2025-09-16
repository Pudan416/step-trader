import Foundation

enum DifficultyLevel: String, CaseIterable {
    case easy = "EASY"
    case medium = "MEDIUM" 
    case hard = "HARD"
    case hardcore = "HARDCORE"
    
    var stepsPerMinute: Double {
        switch self {
        case .easy: return 500
        case .medium: return 1000
        case .hard: return 2000
        case .hardcore: return 5000
        }
    }
    
    var description: String {
        "\(rawValue): \(Int(stepsPerMinute)) шагов/мин"
    }
}