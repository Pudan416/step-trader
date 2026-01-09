import Foundation
import ManagedSettings
import ManagedSettingsUI
import UIKit

// MARK: - Shield UI Configuration
// Shows a button to open DOOM CTRL for paying an entry
final class ShieldConfigurationProvider: NSObject {
    
    private struct AppUnlockSettings: Codable {
        let entryCostSteps: Int
        let dayPassCostSteps: Int
    }
    
    // Get current balance and entry cost from App Group
    private func getStepsInfo(for bundleId: String?) -> (balance: Int, entryCost: Int, dayPassCost: Int, dayPassActive: Bool) {
        let userDefaults = UserDefaults.stepsTrader()
        let balance = userDefaults.integer(forKey: "stepsBalance")
        let fallbackCost: Int
        switch userDefaults.string(forKey: "entryCostTariff") {
        case "medium": fallbackCost = 500
        case "hard": fallbackCost = 1000
        default: fallbackCost = 100
        }
        
        var entryCost = fallbackCost
        var dayPassCost = fallbackCost * 5
        
        if let data = userDefaults.data(forKey: "appUnlockSettings_v1"),
           let decoded = try? JSONDecoder().decode([String: AppUnlockSettings].self, from: data),
           let bundleId,
           let settings = decoded[bundleId] {
            entryCost = settings.entryCostSteps
            dayPassCost = settings.dayPassCostSteps
        }
        
        var dayPassActive = false
        if let data = userDefaults.data(forKey: "appDayPassGrants_v1"),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data),
           let bundleId,
           let date = decoded[bundleId] {
            dayPassActive = Calendar.current.isDateInToday(date)
        }
        
        return (balance, entryCost, dayPassCost, dayPassActive)
    }
    
    // Common configuration builder
    private func makeConfiguration(title: String, subtitle: String?, bundleId: String?) -> ShieldConfiguration {
        let info = getStepsInfo(for: bundleId)
        
        var lines: [String] = []
        lines.append("Balance: \(info.balance) steps")
        if info.dayPassActive {
            lines.append("Day pass active today")
        } else {
            lines.append("Entry: \(info.entryCost) steps")
            lines.append("Day pass: \(info.dayPassCost) steps")
        }
        let balanceText = lines.joined(separator: "\n")
        
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            icon: UIImage(systemName: "shoeprints.fill"),
            title: ShieldConfiguration.Label(text: title, color: .white),
            subtitle: ShieldConfiguration.Label(text: balanceText, color: .white),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Pay to unlock", color: .white),
            primaryButtonBackgroundColor: info.balance >= info.entryCost ? .blue : .red,
            secondaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: .white)
        )
    }

    // MARK: - Shield Configuration Methods
    func configuration(shielding application: Application) -> ShieldConfiguration {
        return makeConfiguration(title: "DOOM CTRL",
                                 subtitle: nil,
                                 bundleId: application.bundleIdentifier)
    }

    func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        return configuration(shielding: application)
    }

    func configuration(shielding category: ActivityCategory) -> ShieldConfiguration {
        return makeConfiguration(title: "Category blocked",
                                 subtitle: nil,
                                 bundleId: nil)
    }

    func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        return makeConfiguration(title: "Website blocked",
                                 subtitle: nil,
                                 bundleId: nil)
    }

    // MARK: - Shield Action Methods
    func handle(action: ShieldAction, for application: Application) {
        openPayDeepLink(for: application.bundleIdentifier)
    }

    func handle(action: ShieldAction, for application: Application, in category: ActivityCategory) {
        openPayDeepLink(for: application.bundleIdentifier)
    }

    func handle(action: ShieldAction, for category: ActivityCategory) {
        openPayDeepLink(for: nil)
    }

    func handle(action: ShieldAction, for webDomain: WebDomain) {
        openPayDeepLink(for: nil)
    }

    private func openPayDeepLink(for bundleIdentifier: String?) {
        // Anti-loop guard: don't re-open instantly if just launched
        let g = UserDefaults.stepsTrader()
        let now = Date()
        if let last = g.object(forKey: "payGateLastOpen") as? Date,
           now.timeIntervalSince(last) < 1 {
            return
        }
        g.set(now, forKey: "payGateLastOpen")

        let target = bundleIdentifier ?? "com.burbn.instagram"
        guard let encodedTarget = target.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed)
        else { return }

        guard let url = URL(string: "steps-trader://pay?target=\(encodedTarget)") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
