import Foundation
import HealthKit
@testable import Steps4

final class MockHealthKitService: HealthKitServiceProtocol {
    func fetchSleep(from: Date, to: Date) async throws -> Double { 0 }
    @MainActor func requestAuthorization() async throws {}
    @MainActor func authorizationStatus() -> HKAuthorizationStatus { .sharingAuthorized }
    @MainActor func sleepAuthorizationStatus() -> HKAuthorizationStatus { .sharingAuthorized }
    func fetchSteps(from: Date, to: Date) async throws -> Double { 0 }
    func fetchWorkouts(from: Date, to: Date) async throws -> [DetectedWorkout] { [] }
    func fetchMindfulMinutes(from: Date, to: Date) async throws -> Double { 0 }
    func startObservingSteps(updateHandler: @escaping (Double) -> Void) {}
    func stopObservingSteps() {}
    func clearLastStepCount() {}
}

@MainActor
final class MockFamilyControlsService: FamilyControlsServiceProtocol {
    var isAuthorized: Bool = false
    var selection: FamilyActivitySelection = FamilyActivitySelection()
    func requestAuthorization() async throws {}
    func refreshAuthorizationStatus() {}
    func updateSelection(_ newSelection: FamilyActivitySelection) {}
    func updateMinuteModeMonitoring() {}
    func updateShieldSchedule() {}
}

final class MockNotificationService: NotificationServiceProtocol {
    func requestPermission() async throws {}
    func sendTimeExpiredNotification() {}
    func sendUnblockNotification(remainingMinutes: Int) {}
    func sendRemainingTimeNotification(remainingMinutes: Int) {}
    func sendMinuteModeSummary(bundleId: String, minutesUsed: Int, stepsCharged: Int) {}
    func sendTestNotification() {}
    func sendAccessWindowReminder(remainingSeconds: Int, bundleId: String) {}
    func scheduleAccessWindowStatus(remainingSeconds: Int, bundleId: String) {}
}

final class MockBudgetEngine: BudgetEngineProtocol {
    var tariff: Tariff = .medium
    var stepsPerMinute: Double { tariff.stepsPerMinute }

    func minutes(from steps: Double) -> Int { max(0, Int(steps / stepsPerMinute)) }
    func setBudget(minutes: Int) {}
    func resetIfNeeded() {}
    func updateTariff(_ newTariff: Tariff) { tariff = newTariff }
    func updateDayEnd(hour: Int, minute: Int) {}
    func reloadFromStorage() {}
}
