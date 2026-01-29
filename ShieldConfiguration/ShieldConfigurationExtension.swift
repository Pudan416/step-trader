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
    
    private let appGroupId = "group.personal-project.StepsTrader"
    private let shieldStateKey = "doomShieldState_v1"
    
    private enum ShieldState: Int {
        case blocked = 0        // Initial state: just blocked
        case waitingPush = 1    // After user taps "Unlock" – show "check notifications"
    }
    
    /// Shared UserDefaults from App Group
    private func sharedDefaults() -> UserDefaults {
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) != nil,
           let appGroup = UserDefaults(suiteName: appGroupId) {
            return appGroup
        }
        return .standard
    }
    
    private func currentState() -> ShieldState {
        let raw = sharedDefaults().integer(forKey: shieldStateKey)
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
        let appIcon = UIImage(named: "AppIcon") ?? UIImage(named: "paygate") ?? UIImage(systemName: "bolt.shield.fill")
        
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
        
        // Save human-readable name for token so PayGate can display it
        if let token = application.token,
           let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
            sharedDefaults().set(appName, forKey: tokenKey)
        }
        
        switch currentState() {
        case .blocked:
            // Screen 1: Bold, punk blocking message
            return baseConfiguration(
                title: "⚡ BLOCKED",
                subtitle: "\(appName) is under control.\nYou set the rules. Now follow them.",
                primaryButtonText: "Pay to unlock"
            )
            
        case .waitingPush:
            // Screen 2: Arrow pointing up + instructions
            return baseConfiguration(
                title: "👆 CHECK ABOVE",
                subtitle: """
                    ↑ ↑ ↑
                    Swipe down for notification.
                    Choose your unlock time there.
                    
                    No push? Open DOOM CTRL app
                    → find this shield → unlock manually.
                    """,
                primaryButtonText: "Still nothing"
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
                title: "⚡ BLOCKED",
                subtitle: "\(domain) is off limits.\nFocus on what matters.",
                primaryButtonText: "Pay to unlock"
            )
            
        case .waitingPush:
            return baseConfiguration(
                title: "👆 CHECK ABOVE",
                subtitle: """
                    ↑ ↑ ↑
                    Swipe down for notification.
                    
                    No push? Open DOOM CTRL app
                    → find this shield → unlock.
                    """,
                primaryButtonText: "Still nothing"
            )
        }
    }
    
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        return configuration(shielding: webDomain)
    }
}
