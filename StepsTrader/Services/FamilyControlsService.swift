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

    private struct StoredUnlockSettings: Codable {
        let familyControlsModeEnabled: Bool?
        let minuteTariffEnabled: Bool?
    }

    init() {
        #if canImport(FamilyControls)
        isAuthorized = (center.authorizationStatus == .approved)
        #else
        isAuthorized = false
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
        let events = buildMinuteEvents()
        if events.isEmpty {
            deviceActivityCenter.stopMonitoring([minuteActivityName])
            return
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        do {
            // Restart to avoid "already monitoring" errors and to pick up updated selections/settings.
            deviceActivityCenter.stopMonitoring([minuteActivityName])
            try deviceActivityCenter.startMonitoring(minuteActivityName, during: schedule, events: events)
        } catch {
            print("❌ Failed to start DeviceActivity monitoring: \(error)")
        }
        #endif
    }

    // Legacy DeviceActivity hooks (no-op)
    func startMonitoring(budgetMinutes: Int) {}
    func stopMonitoring() {}
    func checkDeviceActivityStatus() {}
    func checkAuthorizationStatus() {}

    #if canImport(FamilyControls)
    private func buildMinuteEvents() -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: "appUnlockSettings_v1"),
              let decoded = try? JSONDecoder().decode([String: StoredUnlockSettings].self, from: data)
        else { return [:] }

        let dayKey = currentDayKey()
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        
        for (bundleId, _) in decoded {
            let key = "timeAccessSelection_v1_\(bundleId)"
            guard let selectionData = g.data(forKey: key),
                  let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData)
            else { continue }

            if selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty {
                continue
            }

            // DeviceActivity tracks CUMULATIVE usage since schedule start.
            // After threshold fires for minute N, next threshold must be N+1.
            let countKey = "minuteCount_\(dayKey)_\(bundleId)"
            let currentMinutes = g.integer(forKey: countKey)
            let nextThreshold = currentMinutes + 1

            let eventName = DeviceActivityEvent.Name("minute_\(bundleId)")
            let event = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: nextThreshold)
            )
            events[eventName] = event
        }

        return events
    }
    
    private func currentDayKey() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }
    #endif
}
