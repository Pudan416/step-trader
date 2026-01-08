import Foundation
import Combine

@MainActor
final class FamilyControlsService: ObservableObject, FamilyControlsServiceProtocol {
    @Published var selection = FamilyActivitySelection()
    @Published var isAuthorized: Bool = false

    init() {
        // Family Controls removed — keep no-op state
    }

    func requestAuthorization() async throws {
        // No-op: we are not using Family Controls anymore
        isAuthorized = false
    }

    func updateSelection(_ newSelection: FamilyActivitySelection) {
        selection = newSelection
    }

    // Shield controls (no-op)
    func enableShield() {}
    func disableShield() {}
    func allowOneSession() {}
    func reenableShield() {}

    // Legacy DeviceActivity hooks (no-op)
    func startMonitoring(budgetMinutes: Int) {}
    func stopMonitoring() {}
    func checkDeviceActivityStatus() {}
    func checkAuthorizationStatus() {}
}
