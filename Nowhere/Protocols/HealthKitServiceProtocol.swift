import Foundation
import HealthKit

@preconcurrency
protocol HealthKitServiceProtocol {
    func fetchSleep(from: Date, to: Date) async throws -> Double
    @MainActor
    func requestAuthorization() async throws
    /// Returns the WRITE authorization status for steps. Note: this does NOT reflect
    /// read permission — HealthKit never reveals whether read access was granted.
    /// For read-only apps, `.sharingDenied` is expected and does not mean reads will fail.
    @MainActor
    func authorizationStatus() -> HKAuthorizationStatus
    /// Returns the WRITE authorization status for sleep (same caveat as above).
    @MainActor
    func sleepAuthorizationStatus() -> HKAuthorizationStatus
    func fetchSteps(from: Date, to: Date) async throws -> Double
    func fetchWorkouts(from: Date, to: Date) async throws -> [DetectedWorkout]
    func fetchMindfulMinutes(from: Date, to: Date) async throws -> Double
    @MainActor func startObservingSteps(updateHandler: @escaping (Double) -> Void)
    @MainActor func stopObservingSteps()
    func clearLastStepCount()
}
