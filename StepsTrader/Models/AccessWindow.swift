import Foundation

enum AccessWindow: String, CaseIterable, Sendable, Codable {
    case minutes10
    case minutes30
    case hour1

    var displayName: String {
        switch self {
        case .minutes10: "10 min"
        case .minutes30: "30 min"
        case .hour1: "1 hour"
        }
    }
    
    var minutes: Int {
        switch self {
        case .minutes10: 10
        case .minutes30: 30
        case .hour1: 60
        }
    }
    
    /// Label for "spend colors" options: friendly name + time note
    var spendColorsLabel: String {
        switch self {
        case .minutes10: "a bit (10 min)"
        case .minutes30: "quite a bit (30 min)"
        case .hour1: "some time (1 hour)"
        }
    }
}
