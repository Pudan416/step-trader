import Foundation

struct AppUnlockSettings: Codable, Equatable {
    var entryCostSteps: Int
    var dayPassCostSteps: Int
    var allowedWindows: Set<AccessWindow> = [.minutes10, .minutes30, .hour1]
    var minuteTariffEnabled: Bool = false
    var familyControlsModeEnabled: Bool = false
    
    init(entryCostSteps: Int, dayPassCostSteps: Int, allowedWindows: Set<AccessWindow> = [.minutes10, .minutes30, .hour1], minuteTariffEnabled: Bool = false, familyControlsModeEnabled: Bool = false) {
        self.entryCostSteps = entryCostSteps
        self.dayPassCostSteps = dayPassCostSteps
        self.allowedWindows = allowedWindows.isEmpty ? [.minutes10, .minutes30, .hour1] : allowedWindows
        self.minuteTariffEnabled = minuteTariffEnabled
        self.familyControlsModeEnabled = familyControlsModeEnabled
    }
    
    enum CodingKeys: String, CodingKey {
        case entryCostSteps, dayPassCostSteps, allowedWindows, minuteTariffEnabled, familyControlsModeEnabled
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entryCostSteps = try c.decode(Int.self, forKey: .entryCostSteps)
        dayPassCostSteps = try c.decode(Int.self, forKey: .dayPassCostSteps)
        minuteTariffEnabled = try c.decodeIfPresent(Bool.self, forKey: .minuteTariffEnabled) ?? false
        familyControlsModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .familyControlsModeEnabled) ?? false
        if let rawArray = try? c.decode([String].self, forKey: .allowedWindows) {
            allowedWindows = Set(rawArray.compactMap { AccessWindow(rawValue: $0) })
        }
        if allowedWindows.isEmpty {
            allowedWindows = [.minutes10, .minutes30, .hour1]
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(entryCostSteps, forKey: .entryCostSteps)
        try c.encode(dayPassCostSteps, forKey: .dayPassCostSteps)
        try c.encode(allowedWindows, forKey: .allowedWindows)
        try c.encode(minuteTariffEnabled, forKey: .minuteTariffEnabled)
        try c.encode(familyControlsModeEnabled, forKey: .familyControlsModeEnabled)
    }
}
