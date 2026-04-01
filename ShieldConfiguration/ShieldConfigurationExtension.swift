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
    
    /// Shared UserDefaults from App Group
    private func sharedDefaults() -> UserDefaults {
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedKeys.appGroupId) != nil,
           let appGroup = UserDefaults(suiteName: SharedKeys.appGroupId) {
            return appGroup
        }
        return .standard
    }
    
    private func getAppName(for application: Application) -> String {
        return application.localizedDisplayName ?? NSLocalizedString("App", comment: "Fallback name for unknown app")
    }
    
    // MARK: - Brand Colors
    // Matches AppColors.brandAccent (#FFD369); extension target can't import ColorConstants.
    private var brandYellow: UIColor {
        UIColor(red: 0xFF/255.0, green: 0xD3/255.0, blue: 0x69/255.0, alpha: 1.0)
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
            primaryButtonLabel: ShieldConfiguration.Label(text: primaryButtonText, color: .black),
            primaryButtonBackgroundColor: brandYellow,
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
            defaults.set(appName, forKey: SharedKeys.fcAppNameKey(base64))
            if let bid = application.bundleIdentifier {
                defaults.set(bid, forKey: SharedKeys.fcBundleIdKey(base64))
            }
        }
        
        return baseConfiguration(
            title: String(format: NSLocalizedString("%@ is closed.", comment: "Shield title for blocked app"), appName),
            subtitle: NSLocalizedString("Spend colors in Nowhere to unlock it.", comment: "Shield subtitle"),
            primaryButtonText: NSLocalizedString("Unlock with colors", comment: "Shield primary button")
        )
    }
    
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        return configuration(shielding: application)
    }
    
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        let domain = webDomain.domain ?? NSLocalizedString("this site", comment: "Fallback name for unknown web domain")
        
        return baseConfiguration(
            title: String(format: NSLocalizedString("%@ is closed.", comment: "Shield title for blocked domain"), domain),
            subtitle: NSLocalizedString("Spend colors in Nowhere to unlock it.", comment: "Shield subtitle"),
            primaryButtonText: NSLocalizedString("Unlock with colors", comment: "Shield primary button")
        )
    }
    
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        return configuration(shielding: webDomain)
    }
}
