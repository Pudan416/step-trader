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
    
    /// Локальный helper для доступа к shared `UserDefaults` из App Group.
    private func sharedDefaults() -> UserDefaults {
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) != nil,
           let appGroup = UserDefaults(suiteName: appGroupId) {
            return appGroup
        }
        return .standard
    }
    
    private func currentState() -> ShieldState {
        // Используем shared UserDefaults из App Group, чтобы синхронизировать состояние
        // между ShieldAction, ShieldConfiguration и основным приложением.
        let raw = sharedDefaults().integer(forKey: shieldStateKey)
        return ShieldState(rawValue: raw) ?? .blocked
    }
    
    private func getAppName(for application: Application) -> String {
        // Use localizedDisplayName from Application, or fallback to "App"
        return application.localizedDisplayName ?? "App"
    }
    
    /// Общая конфигурация внешнего вида (тёмный фон, белый текст, логотип DOOM CTRL).
    private func baseConfiguration(
        title: String,
        subtitle: String,
        primaryButtonText: String,
        secondaryButtonText: String? = nil
    ) -> ShieldConfiguration {
        // Пытаемся взять наш логотип из ассетов экстеншена; если нет — используем SF Symbol.
        let appIcon = UIImage(named: "AppIcon") ?? UIImage(named: "paygate") ?? UIImage(systemName: "shield.checkered")
        
        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterialDark,
            backgroundColor: UIColor.black.withAlphaComponent(0.70),
            icon: appIcon,
            title: ShieldConfiguration.Label(text: title, color: .white),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: .white),
            primaryButtonLabel: ShieldConfiguration.Label(text: primaryButtonText, color: .white),
            primaryButtonBackgroundColor: .systemBlue,
            secondaryButtonLabel: secondaryButtonText.map { ShieldConfiguration.Label(text: $0, color: .white) }
        )
    }
    
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        let appName = getAppName(for: application)
        
        // Сохраняем человекочитаемое имя для токена, чтобы PayGate мог его показать.
        if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: application.token, requiringSecureCoding: true) {
            let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
            sharedDefaults().set(appName, forKey: tokenKey)
        }
        
        switch currentState() {
        case .blocked:
            // Первый экран: просто говорим, что приложение заблокировано нашим щитом
            return baseConfiguration(
                title: "App Blocked",
                subtitle: "\(appName)\nBlocked by DOOM CTRL",
                primaryButtonText: "Unlock"
            )
        case .waitingPush:
            // Второй экран: объясняем, что отправили пуш и даём кнопку "Push not received"
            return baseConfiguration(
                title: "Check notifications",
                subtitle: "We sent a push from DOOM CTRL.\nOpen it to choose unlock time.",
                primaryButtonText: "Push not received"
            )
        }
    }
    
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        // Для категорий используем ту же логику, что и для отдельных приложений
        return configuration(shielding: application)
    }
    
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        return baseConfiguration(
            title: "Website Blocked",
            subtitle: (webDomain.domain ?? "Unknown") + "\nBlocked by DOOM CTRL",
            primaryButtonText: "OK"
        )
    }
    
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        return configuration(shielding: webDomain)
    }
}
