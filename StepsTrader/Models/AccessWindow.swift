import Foundation

enum AccessWindow: String, CaseIterable, Sendable, Codable {
    case minutes10
    case minutes30
    case hour1

    var displayName: String {
        switch self {
        case .minutes10: return "10 min"
        case .minutes30: return "30 min"
        case .hour1: return "1 hour"
        }
    }
    
    var minutes: Int {
        switch self {
        case .minutes10: return 10
        case .minutes30: return 30
        case .hour1: return 60
        }
    }
    
    /// Label for "spend exp" options: friendly name + time note
    var spendExperienceLabel: String {
        switch self {
        case .minutes10: return "a bit (10 min)"
        case .minutes30: return "quite a bit (30 min)"
        case .hour1: return "some time (1 hour)"
        }
    }
}
