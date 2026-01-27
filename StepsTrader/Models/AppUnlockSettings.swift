import Foundation

extension AppModel {
    struct AppUnlockSettings: Codable, Equatable {
        var entryCostSteps: Int
        var dayPassCostSteps: Int
        var allowedWindows: Set<AccessWindow> = [.single, .minutes5, .minutes30, .hour1] // day pass off by default
        var minuteTariffEnabled: Bool = false
        var familyControlsModeEnabled: Bool = false
    }
}
