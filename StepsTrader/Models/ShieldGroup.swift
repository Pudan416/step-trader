import Foundation
#if canImport(FamilyControls)
import FamilyControls
#endif

extension AppModel {
    struct ShieldGroup: Identifiable, Codable {
        let id: String
        var name: String
        var selection: FamilyActivitySelection
        var settings: AppUnlockSettings
        var difficultyLevel: Int = 1 // Difficulty level (1-5)
        var enabledIntervals: Set<AccessWindow> = [.minutes5, .minutes15, .minutes30, .hour1, .hour2] // Enabled intervals
        
        init(id: String = UUID().uuidString, name: String, selection: FamilyActivitySelection = FamilyActivitySelection(), settings: AppUnlockSettings) {
            self.id = id
            self.name = name
            self.selection = selection
            self.settings = settings
            self.difficultyLevel = 1
            self.enabledIntervals = [.minutes5, .minutes15, .minutes30, .hour1, .hour2]
        }
        
        // Calculates cost for interval based on difficulty level
        func cost(for interval: AccessWindow) -> Int {
            // Base costs for each interval (at level 1)
            let baseCosts: [AccessWindow: Int] = [
                .minutes5: 2,
                .minutes15: 5,
                .minutes30: 10,
                .hour1: 20,
                .hour2: 40
            ]
            
            // Get base cost for interval
            let baseCost = baseCosts[interval] ?? 5
            
            // Multiply by difficulty level (1-5)
            // Level 1 = base cost, level 5 = base cost * 2.5
            let multiplier = 1.0 + (Double(difficultyLevel - 1) * 0.375) // 1.0, 1.375, 1.75, 2.125, 2.5
            
            return max(1, Int(Double(baseCost) * multiplier))
        }
        
        // Custom Codable implementation for FamilyActivitySelection
        enum CodingKeys: String, CodingKey {
            case id, name, selectionData, settings, minuteCost, difficultyLevel, enabledIntervals
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            settings = try container.decode(AppUnlockSettings.self, forKey: .settings)
            
            // Backward compatibility: convert minuteCost to difficultyLevel if present
            if let oldMinuteCost = try? container.decodeIfPresent(Int.self, forKey: .minuteCost) {
                difficultyLevel = oldMinuteCost
            } else {
                difficultyLevel = try container.decodeIfPresent(Int.self, forKey: .difficultyLevel) ?? 1
            }
            
            enabledIntervals = try container.decodeIfPresent(Set<AccessWindow>.self, forKey: .enabledIntervals) ?? [.minutes5, .minutes15, .minutes30, .hour1, .hour2]
            
            #if canImport(FamilyControls)
            if let data = try? container.decode(Data.self, forKey: .selectionData),
               let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
                selection = decoded
            } else {
                selection = FamilyActivitySelection()
            }
            #else
            selection = FamilyActivitySelection()
            #endif
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(settings, forKey: .settings)
            try container.encode(difficultyLevel, forKey: .difficultyLevel)
            try container.encode(enabledIntervals, forKey: .enabledIntervals)
            
            #if canImport(FamilyControls)
            if let data = try? JSONEncoder().encode(selection) {
                try container.encode(data, forKey: .selectionData)
            }
            #endif
        }
    }
}
