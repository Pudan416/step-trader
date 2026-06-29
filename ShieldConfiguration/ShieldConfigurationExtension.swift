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

    /// Cache token → base64 to avoid repeated NSKeyedArchiver calls on every shield display.
    /// Protected by cacheLock because configuration(shielding:) can be called on any thread.
    private static var tokenBase64Cache: [ApplicationToken: String] = [:]
    private static let cacheLock = NSLock()

    private static func base64(for token: ApplicationToken) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = tokenBase64Cache[token] { return cached }
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            return nil
        }
        let b64 = data.base64EncodedString()
        tokenBase64Cache[token] = b64
        return b64
    }

    /// Shared UserDefaults from App Group
    private func sharedDefaults() -> UserDefaults {
        if let appGroup = UserDefaults(suiteName: SharedKeys.appGroupId) {
            return appGroup
        }
        assertionFailure("ShieldConfigurationExtension: App group unavailable")
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
    
    /// Whether a push was sent recently (within 30 seconds).
    /// ShieldAction writes `shieldPushSentAt`; `.defer` re-queries this configuration.
    private func wasPushRecentlySent() -> Bool {
        let defaults = sharedDefaults()
        guard let sentAt = defaults.object(forKey: SharedKeys.shieldPushSentAt) as? Date else {
            return false
        }
        return Date().timeIntervalSince(sentAt) < 30
    }
    
    /// Base configuration with our brand styling
    private func baseConfiguration(
        title: String,
        subtitle: String,
        primaryButtonText: String,
        secondaryButtonText: String? = nil
    ) -> ShieldConfiguration {
        let appIcon = UIImage(named: "ShieldIcon") ?? UIImage(systemName: "eye.fill")
        
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
        
        if let token = application.token,
           let base64 = Self.base64(for: token) {
            let defaults = sharedDefaults()
            if defaults.string(forKey: SharedKeys.fcAppNameKey(base64)) != appName {
                defaults.set(appName, forKey: SharedKeys.fcAppNameKey(base64))
            }
            if let bid = application.bundleIdentifier,
               defaults.string(forKey: SharedKeys.fcBundleIdKey(base64)) != bid {
                defaults.set(bid, forKey: SharedKeys.fcBundleIdKey(base64))
            }
            if defaults.string(forKey: SharedKeys.fcAppNameKey(base64)) != appName
                || (application.bundleIdentifier != nil && defaults.string(forKey: SharedKeys.fcBundleIdKey(base64)) != application.bundleIdentifier) {
                defaults.synchronize()
            }
        }
        
        let title = String(format: NSLocalizedString("%@ is locked\nby Nowhere.", comment: "Shield title for blocked app"), appName)

        if wasPushRecentlySent() {
            return baseConfiguration(
                title: title,
                subtitle: String(format: NSLocalizedString("\nNowhere sent you a push.\nTap it to unlock %@.", comment: "Shield subtitle after push sent"), appName),
                primaryButtonText: NSLocalizedString("one more push", comment: "Shield primary button — resend push"),
                secondaryButtonText: NSLocalizedString("keep it closed", comment: "Shield secondary button")
            )
        }

        return baseConfiguration(
            title: title,
            subtitle: NSLocalizedString("\nSpend some colors\nto unlock it", comment: "Shield subtitle"),
            primaryButtonText: NSLocalizedString("unlock with push", comment: "Shield primary button — request notification"),
            secondaryButtonText: NSLocalizedString("keep it closed", comment: "Shield secondary button — conscious opt-out")
        )
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        return configuration(shielding: application)
    }
    
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        let domain = webDomain.domain ?? NSLocalizedString("this site", comment: "Fallback name for unknown web domain")
        let title = String(format: NSLocalizedString("%@ is locked\nby Nowhere.", comment: "Shield title for blocked domain"), domain)

        if wasPushRecentlySent() {
            return baseConfiguration(
                title: title,
                subtitle: String(format: NSLocalizedString("\nNowhere sent you a push.\nTap it to unlock %@.", comment: "Shield subtitle after push sent"), domain),
                primaryButtonText: NSLocalizedString("one more push", comment: "Shield primary button — resend push"),
                secondaryButtonText: NSLocalizedString("keep it closed", comment: "Shield secondary button")
            )
        }

        return baseConfiguration(
            title: title,
            subtitle: NSLocalizedString("\nSpend some colors\nto unlock it", comment: "Shield subtitle"),
            primaryButtonText: NSLocalizedString("unlock with push", comment: "Shield primary button — request notification"),
            secondaryButtonText: NSLocalizedString("keep it closed", comment: "Shield secondary button — conscious opt-out")
        )
    }
    
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        return configuration(shielding: webDomain)
    }
}
