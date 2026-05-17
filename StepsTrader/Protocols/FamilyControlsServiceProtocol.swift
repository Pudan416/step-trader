import Foundation

@MainActor
protocol FamilyControlsServiceProtocol {
    var isAuthorized: Bool { get }
    var selection: FamilyActivitySelection { get set }
    func requestAuthorization() async throws
    func refreshAuthorizationStatus()
    func updateSelection(_ newSelection: FamilyActivitySelection)
    /// Updates DeviceActivity monitoring for minute-mode charging (if supported/authorized).
    func updateMinuteModeMonitoring()
    /// Updates shield configuration (shield is configured in DeviceActivityMonitorExtension).
    func updateShieldSchedule()
}
