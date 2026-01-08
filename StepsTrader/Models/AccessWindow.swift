import Foundation

enum AccessWindow: String, CaseIterable, Sendable, Codable {
    case single
    case minutes5
    case hour1
    case day1

    var displayName: String {
        switch self {
        case .single: return "Один раз"
        case .minutes5: return "5 минут"
        case .hour1: return "1 час"
        case .day1: return "До конца дня"
        }
    }
}
