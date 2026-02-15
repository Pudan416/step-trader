//
//  ShieldConfigurationExtension.swift
//  ShieldConfiguration
//
//  Created by Konstantin Pudan on 23.01.2026.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

// Override the functions below to customize the shields used in various situations.
// The system provides a default appearance for any methods that your subclass doesn't override.
// Make sure that your class name matches the NSExtensionPrincipalClass in your Info.plist.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    
    private enum ShieldState: Int {
        case blocked = 0        // Initial state: just blocked
        case waitingPush = 1    // After user taps "Unlock" – show "check notifications"
    }
    
    /// Shared UserDefaults from App Group
    private func sharedDefaults() -> UserDefaults {
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedKeys.appGroupId) != nil,
           let appGroup = UserDefaults(suiteName: SharedKeys.appGroupId) {
            return appGroup
        }
        return .standard
    }
    
    private func currentState() -> ShieldState {
        let raw = sharedDefaults().integer(forKey: SharedKeys.shieldState)
        return ShieldState(rawValue: raw) ?? .blocked
    }
    
    private func getAppName(for application: Application) -> String {
        return application.localizedDisplayName ?? "App"
    }
    
    // MARK: - Brand Colors
    private var brandPink: UIColor {
        UIColor(red: 224/255, green: 130/255, blue: 217/255, alpha: 1.0)
    }
    
    private var darkBackground: UIColor {
        UIColor(red: 0.05, green: 0.05, blue: 0.12, alpha: 0.95)
    }
    
    /// Base configuration with our brand styling
    private func baseConfiguration(
        title: String,
        subtitle: String,
        primaryButtonText: String,
        secondaryButtonText: String? = nil
    ) -> ShieldConfiguration {
        // Try to load app icon from extension assets
        let appIcon = UIImage(named: "AppIcon") ?? UIImage(named: "paygate") ?? UIImage(systemName: "shield.fill")
        
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: darkBackground,
            icon: appIcon,
            title: ShieldConfiguration.Label(text: title, color: .white),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: UIColor.white.withAlphaComponent(0.85)),
            primaryButtonLabel: ShieldConfiguration.Label(text: primaryButtonText, color: .white),
            primaryButtonBackgroundColor: brandPink,
            secondaryButtonLabel: secondaryButtonText.map { ShieldConfiguration.Label(text: $0, color: UIColor.white.withAlphaComponent(0.6)) }
        )
    }
    
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        let appName = getAppName(for: application)
        
        // Save human-readable name and bundleId for token so PayGate/findTicketGroup can resolve
        if let token = application.token,
           let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            let base64 = tokenData.base64EncodedString()
            let defaults = sharedDefaults()
            defaults.set(appName, forKey: "fc_appName_" + base64)
            if let bid = application.bundleIdentifier {
                defaults.set(bid, forKey: "fc_bundleId_" + base64)
            }
        }
        
        switch currentState() {
        case .blocked:
            return baseConfiguration(
                title: "\(appName) is closed.",
                subtitle: "Open Proof to spend exp.",
                primaryButtonText: "Open"
            )
            
        case .waitingPush:
            return baseConfiguration(
                title: "Check your notifications.",
                subtitle: "A notification is waiting.\nOr open Proof directly.",
                primaryButtonText: "Open Proof"
            )
        }
    }
    
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        return configuration(shielding: application)
    }
    
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        let domain = webDomain.domain ?? "this site"
        
        switch currentState() {
        case .blocked:
            return baseConfiguration(
                title: "\(domain) is closed.",
                subtitle: "Open Proof to spend exp.",
                primaryButtonText: "Open"
            )
            
        case .waitingPush:
            return baseConfiguration(
                title: "Check your notifications.",
                subtitle: "A notification is waiting.\nOr open Proof directly.",
                primaryButtonText: "Open Proof"
            )
        }
    }
    
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        return configuration(shielding: webDomain)
    }
}
