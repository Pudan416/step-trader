import Foundation
import UserNotifications

enum SettingsPermissionStatus: Equatable {
    case connected
    case checkAccess
    case unavailable
    case allowed
    case notRequested
    case offInSystemSettings
    case actionNeeded
}

enum SettingsPermissionAction: Equatable {
    case checkAccess
    case requestPermission
    case openSystemSettings
}

struct SettingsPermissionPresentation: Equatable {
    let status: SettingsPermissionStatus
    let action: SettingsPermissionAction?
    let contributesToWarning: Bool

    static func health(isAvailable: Bool, hasReturnedData: Bool) -> Self {
        guard isAvailable else {
            return .init(status: .unavailable, action: nil, contributesToWarning: false)
        }
        return hasReturnedData
            ? .init(status: .connected, action: nil, contributesToWarning: false)
            : .init(status: .checkAccess, action: .checkAccess, contributesToWarning: false)
    }

    static func notifications(status: UNAuthorizationStatus) -> Self {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .init(status: .allowed, action: nil, contributesToWarning: false)
        case .notDetermined:
            return .init(status: .notRequested, action: .requestPermission, contributesToWarning: true)
        case .denied:
            return .init(status: .offInSystemSettings, action: .openSystemSettings, contributesToWarning: true)
        @unknown default:
            return .init(status: .checkAccess, action: .openSystemSettings, contributesToWarning: false)
        }
    }

    static func screenTime(isAuthorized: Bool) -> Self {
        isAuthorized
            ? .init(status: .connected, action: nil, contributesToWarning: false)
            : .init(status: .actionNeeded, action: .requestPermission, contributesToWarning: true)
    }
}
