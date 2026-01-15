import Foundation
import ManagedSettings
import ManagedSettingsUI
import UIKit

fileprivate func stepsTraderDefaults() -> UserDefaults {
    let groupId = "group.personal-project.StepsTrader"
    return UserDefaults(suiteName: groupId) ?? .standard
}

// MARK: - Shield UI Configuration
// Shows a button to open DOOM CTRL for paying an entry
class ShieldConfigurationProvider: ShieldConfigurationDataSource {
    
    private struct AppUnlockSettings: Codable {
        let entryCostSteps: Int
        let dayPassCostSteps: Int
        let minuteTariffEnabled: Bool
        let familyControlsModeEnabled: Bool
    }

    private struct ShieldLevelInfo {
        let label: String
        let threshold: Int
        let nextThreshold: Int?
    }

    private func levelLadder() -> [ShieldLevelInfo] {
        let thresholds = [0, 10_000, 25_000, 45_000, 70_000, 100_000, 150_000, 220_000, 320_000, 500_000]
        let labels = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
        return thresholds.enumerated().map { index, threshold in
            let next = index + 1 < thresholds.count ? thresholds[index + 1] : nil
            return ShieldLevelInfo(label: labels[index], threshold: threshold, nextThreshold: next)
        }
    }

    private func currentLevelInfo(totalSpent: Int) -> ShieldLevelInfo {
        let ladder = levelLadder()
        return ladder.last { totalSpent >= $0.threshold } ?? ladder.first!
    }

    private func formatSteps(_ value: Int) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        
        func trimTrailingZero(_ s: String) -> String {
            s.hasSuffix(".0") ? String(s.dropLast(2)) : s
        }
        
        if absValue < 1000 { return "\(value)" }
        
        if absValue < 10_000 {
            let v = (Double(absValue) / 1000.0 * 10).rounded() / 10
            return sign + trimTrailingZero(String(format: "%.1f", v)) + "K"
        }
        
        if absValue < 1_000_000 {
            let v = Int((Double(absValue) / 1000.0).rounded())
            return sign + "\(v)K"
        }
        
        if absValue < 10_000_000 {
            let v = (Double(absValue) / 1_000_000.0 * 10).rounded() / 10
            return sign + trimTrailingZero(String(format: "%.1f", v)) + "M"
        }
        
        if absValue < 1_000_000_000 {
            let v = Int((Double(absValue) / 1_000_000.0).rounded())
            return sign + "\(v)M"
        }
        
        let v = (Double(absValue) / 1_000_000_000.0 * 10).rounded() / 10
        return sign + trimTrailingZero(String(format: "%.1f", v)) + "B"
    }
    
    // Get current balance and entry cost from App Group
    private func getStepsInfo(for bundleId: String?) -> (balance: Int, entryCost: Int, dayPassCost: Int, dayPassActive: Bool, minuteModeEnabled: Bool, stepsToday: Int, totalSpent: Int) {
        let userDefaults = stepsTraderDefaults()
        let balance = userDefaults.integer(forKey: "stepsBalance")
        // `debugStepsBonus_v1` is used as a compatibility key for "Outer World bonus energy only".
        let outerWorldBonus = userDefaults.integer(forKey: "debugStepsBonus_v1")
        let stepsToday = userDefaults.integer(forKey: "cachedStepsToday") + outerWorldBonus
        let fallbackCost = 100
        var entryCost = fallbackCost
        var dayPassCost = fallbackCost * 100
        
        var minuteModeEnabled = false
        if let data = userDefaults.data(forKey: "appUnlockSettings_v1"),
           let decoded = try? JSONDecoder().decode([String: AppUnlockSettings].self, from: data),
           let bundleId,
           let settings = decoded[bundleId] {
            entryCost = settings.entryCostSteps
            dayPassCost = settings.dayPassCostSteps
            minuteModeEnabled = settings.familyControlsModeEnabled || settings.minuteTariffEnabled
        }
        
        var dayPassActive = false
        if let data = userDefaults.data(forKey: "appDayPassGrants_v1"),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data),
           let bundleId,
           let date = decoded[bundleId] {
            dayPassActive = Calendar.current.isDateInToday(date)
        }

        var totalSpent = 0
        if let bundleId {
            if let data = userDefaults.data(forKey: "appStepsSpentLifetime_v1"),
               let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
                totalSpent = decoded[bundleId] ?? 0
            } else if let data = userDefaults.data(forKey: "appStepsSpentByDay_v1"),
                      let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
                totalSpent = decoded.values.reduce(0) { $0 + ($1[bundleId] ?? 0) }
            }
        }
        
        return (balance, entryCost, dayPassCost, dayPassActive, minuteModeEnabled, stepsToday, totalSpent)
    }
    
    // Common configuration builder
    private func makeConfiguration(title: String, subtitle: String?, bundleId: String?) -> ShieldConfiguration {
        let info = getStepsInfo(for: bundleId)
        let level = currentLevelInfo(totalSpent: info.totalSpent)
        
        var lines: [String] = []
        
        // Level progress line with visual bar
        if let next = level.nextThreshold {
            let localSpent = max(0, info.totalSpent - level.threshold)
            let localTotal = max(1, next - level.threshold)
            let progress = Double(localSpent) / Double(localTotal)
            let barLength = 10
            let filled = Int(progress * Double(barLength))
            let bar = String(repeating: "▓", count: filled) + String(repeating: "░", count: barLength - filled)
            let toNext = next - info.totalSpent
            lines.append("⚡ Level \(level.label) [\(bar)]")
            lines.append("📊 \(formatSteps(info.totalSpent)) invested • \(formatSteps(toNext)) to next")
        } else {
            lines.append("⚡ Level \(level.label) [▓▓▓▓▓▓▓▓▓▓] MAX")
            lines.append("📊 \(formatSteps(info.totalSpent)) total invested")
        }
        
        lines.append("") // Empty line separator
        
        if info.minuteModeEnabled {
            let minutesLeft = info.entryCost > 0 ? max(0, info.stepsToday / info.entryCost) : 0
            lines.append("⏱ Minute mode")
            lines.append("Minutes left: \(minutesLeft)")
            lines.append("Cost: \(info.entryCost) steps/min")
        } else {
            lines.append("🔋 Balance: \(formatSteps(info.balance)) steps")
            if info.dayPassActive {
                lines.append("✅ Day pass active")
            }
            lines.append("Entry: \(formatSteps(info.entryCost)) • 5m: \(formatSteps(info.entryCost * 5))")
            lines.append("1h: \(formatSteps(info.entryCost * 12)) • Day: \(formatSteps(info.dayPassCost))")
        }
        let balanceText = lines.joined(separator: "\n")
        
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            icon: UIImage(systemName: "shoeprints.fill"),
            title: ShieldConfiguration.Label(text: title, color: .white),
            subtitle: ShieldConfiguration.Label(text: balanceText, color: .white),
            primaryButtonLabel: ShieldConfiguration.Label(text: info.minuteModeEnabled ? "Enter" : "Pay to unlock", color: .white),
            primaryButtonBackgroundColor: info.minuteModeEnabled ? .systemPink : (info.balance >= info.entryCost ? .blue : .red),
            secondaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: .white)
        )
    }

    // MARK: - Shield Configuration Methods
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        return makeConfiguration(
            title: "DOOM CTRL",
            subtitle: nil,
            bundleId: application.bundleIdentifier
        )
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        configuration(shielding: application)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration(title: "Website blocked", subtitle: nil, bundleId: nil)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        configuration(shielding: webDomain)
    }
}

// MARK: - Shield Action Handler
final class ShieldActionHandler: ShieldActionDelegate {
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        openPayDeepLink(for: Application(token: application).bundleIdentifier)
        completionHandler(.close)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        openPayDeepLink(for: nil)
        completionHandler(.close)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        openPayDeepLink(for: nil)
        completionHandler(.close)
    }

    private func openPayDeepLink(for bundleIdentifier: String?) {
        let g = stepsTraderDefaults()
        let now = Date()
        if let last = g.object(forKey: "payGateLastOpen") as? Date,
           now.timeIntervalSince(last) < 1 {
            return
        }
        g.set(now, forKey: "payGateLastOpen")

        let target = bundleIdentifier ?? "com.burbn.instagram"
        g.set(true, forKey: "shouldShowPayGate")
        g.set(target, forKey: "payGateTargetBundleId")
        g.set(true, forKey: "shortcutTriggered")
        g.set(target, forKey: "shortcutTarget")
        g.set(now, forKey: "shortcutTriggerTime")
    }
}
