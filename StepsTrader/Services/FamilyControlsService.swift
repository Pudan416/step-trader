import Foundation
import Combine
#if canImport(FamilyControls)
import FamilyControls
import DeviceActivity
#endif

@MainActor
final class FamilyControlsService: ObservableObject, FamilyControlsServiceProtocol {
    @Published var selection = FamilyActivitySelection()
    @Published var isAuthorized: Bool = false
    #if canImport(FamilyControls)
    private let center = AuthorizationCenter.shared
    private let deviceActivityCenter = DeviceActivityCenter()
    private let minuteActivityName = DeviceActivityName("minuteMode")
    #endif

    init() {
        #if canImport(FamilyControls)
        isAuthorized = (center.authorizationStatus == .approved)
        // AuthorizationCenter doesn't reliably notify on revocation (Apple known issue).
        // Use refreshAuthorizationStatus() on foreground transitions instead (audit fix #15).
        #else
        isAuthorized = false
        #endif
    }

    /// Re-check authorization status. Call this when the app enters foreground
    /// since AuthorizationCenter doesn't reliably push revocation events.
    func refreshAuthorizationStatus() {
        #if canImport(FamilyControls)
        let newStatus = (center.authorizationStatus == .approved)
        if newStatus != isAuthorized {
            isAuthorized = newStatus
            AppLogger.familyControls.info("Authorization status changed to: \(newStatus ? "approved" : "revoked")")
        }
        #endif
    }

    func requestAuthorization() async throws {
        #if canImport(FamilyControls)
        try await center.requestAuthorization(for: .individual)
        isAuthorized = (center.authorizationStatus == .approved)
        #else
        isAuthorized = false
        #endif
    }

    func updateSelection(_ newSelection: FamilyActivitySelection) {
        selection = newSelection
    }

    func updateMinuteModeMonitoring() {
        #if canImport(FamilyControls)
        Task { @MainActor in
            let events = buildHeartbeatEvents()
            if events.isEmpty {
                deviceActivityCenter.stopMonitoring([minuteActivityName])
                return
            }

            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
                intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
                repeats: true
            )

            do {
                deviceActivityCenter.stopMonitoring([minuteActivityName])
                try deviceActivityCenter.startMonitoring(minuteActivityName, during: schedule, events: events)
            } catch {
                AppLogger.familyControls.error("❌ Failed to start DeviceActivity monitoring: \(error)")
            }
        }
        #endif
    }
    
    func updateShieldSchedule() {
        // Shield is configured in DeviceActivityMonitorExtension.intervalDidStart()
        // via ManagedSettingsStore. This method is kept for protocol compliance.
    }

    #if canImport(FamilyControls)
    /// Builds heartbeat events for ticket groups so checkAndClearExpiredUnlocks
    /// fires every minute while the user is in an unblocked app, catching expiry
    /// without waiting for DeviceActivity unlock-expiry callbacks (which are best-effort).
    private func buildHeartbeatEvents() -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        let g = UserDefaults.stepsTrader()
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]

        let liteData = g.data(forKey: SharedKeys.liteTicketConfig) ?? g.data(forKey: SharedKeys.liteShieldConfig)
        if let data = liteData,
           let lite = try? JSONDecoder().decode(LiteTicketConfig.self, from: data) {
            for group in lite.groups where group.active {
                guard let selectionData = Data(base64Encoded: group.selectionDataBase64),
                      let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData),
                      !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
                else { continue }

                let eventName = DeviceActivityEvent.Name("ticketGroup_\(group.id)")
                events[eventName] = DeviceActivityEvent(
                    applications: selection.applicationTokens,
                    categories: selection.categoryTokens,
                    threshold: DateComponents(minute: 1)
                )
            }
        }

        return events
    }

    #endif
}
