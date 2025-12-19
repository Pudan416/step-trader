import Foundation
import ManagedSettings
import ManagedSettingsUI
import UIKit

// MARK: - Shield UI Configuration
// Shows a button to open Steps Trader for paying an entry
final class ShieldConfigurationProvider: NSObject {
    
    // Get current balance and entry cost from App Group
    private func getStepsInfo() -> (balance: Int, cost: Int) {
        let userDefaults = UserDefaults.stepsTrader()
        let balance = userDefaults.integer(forKey: "stepsBalance")
        let cost = userDefaults.integer(forKey: "entryCostSteps")
        return (balance, cost)
    }
    
    // Common configuration builder
    private func makeConfiguration(title: String, subtitle: String?) -> ShieldConfiguration {
        let (balance, cost) = getStepsInfo()
        
        // Show balance and cost in subtitle
        let balanceText = "Balance: \(balance) steps\nEntry cost: \(cost) steps"
        
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            icon: UIImage(systemName: "shoeprints.fill"),
            title: ShieldConfiguration.Label(text: title, color: .white),
            subtitle: ShieldConfiguration.Label(text: balanceText, color: .white),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Pay to unlock", color: .white),
            primaryButtonBackgroundColor: balance >= cost ? .blue : .red,
            secondaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: .white)
        )
    }

    // MARK: - Shield Configuration Methods
    func configuration(shielding application: Application) -> ShieldConfiguration {
        return makeConfiguration(title: "Steps Trader",
                                 subtitle: nil)
    }

    func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        return configuration(shielding: application)
    }

    func configuration(shielding category: ActivityCategory) -> ShieldConfiguration {
        return makeConfiguration(title: "Category blocked",
                                 subtitle: nil)
    }

    func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        return makeConfiguration(title: "Website blocked",
                                 subtitle: nil)
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
        if let last = g.object(forKey: "focusGateLastOpen") as? Date,
           now.timeIntervalSince(last) < 1 {
            return
        }
        g.set(now, forKey: "focusGateLastOpen")

        let target = bundleIdentifier ?? "com.burbn.instagram"
        guard let encodedTarget = target.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed)
        else { return }

        guard let url = URL(string: "steps-trader://focus?target=\(encodedTarget)") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
