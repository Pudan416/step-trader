import Foundation

enum AccessWindow: String, CaseIterable, Sendable, Codable {
    case single
    case minutes5
    case minutes15
    case minutes30
    case hour1
    case hour2
    case day1

    var displayName: String {
        switch self {
        case .single: return "1 минута"
        case .minutes5: return "5 минут"
        case .minutes15: return "15 минут"
        case .minutes30: return "30 минут"
        case .hour1: return "1 час"
        case .hour2: return "2 часа"
        case .day1: return "До конца дня"
        }
    }
    
    var minutes: Int {
        switch self {
        case .single: return 1
        case .minutes5: return 5
        case .minutes15: return 15
        case .minutes30: return 30
        case .hour1: return 60
        case .hour2: return 120
        case .day1: return 1440 // 24 hours
        }
    }
}
