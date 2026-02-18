import Foundation
import HealthKit
import Combine

@MainActor
final class HealthStore: ObservableObject {
    // Dependencies
    private let healthKitService: any HealthKitServiceProtocol
    
    // Published State
    @Published var stepsToday: Double = 0
    @Published var dailySleepHours: Double = 0
    @Published var baseEnergyToday: Int = 0
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
    /// True once HealthKit has returned step data (or a cached value was loaded).
    /// Do not infer from `stepsToday > 0` — zero steps with data IS valid.
    @Published var hasStepsData: Bool = false
    /// True once HealthKit has returned sleep data.
    @Published var hasSleepData: Bool = false
    
    init(healthKitService: any HealthKitServiceProtocol) {
        self.healthKitService = healthKitService
        self.authorizationStatus = healthKitService.authorizationStatus()
    }
    
    func requestAuthorization() async throws {
        do {
            try await healthKitService.requestAuthorization()
            authorizationStatus = healthKitService.authorizationStatus()
        } catch {
            ErrorManager.shared.handle(AppError.healthKitAuthorizationFailed(error))
            throw error
        }
    }
    
    func fetchStepsForCurrentDay() async throws -> Double {
        let now = Date()
        let start = currentDayStart(for: now)
        return try await healthKitService.fetchSteps(from: start, to: now)
    }
    
    func refreshStepsIfAuthorized() async {
        // Always attempt to fetch steps. authorizationStatus() reports WRITE permission,
        // not READ. Read access may be granted even when write status is .notDetermined
        // or .sharingDenied, so guarding on .sharingAuthorized silently blocks step fetching
        // for most users.
        do {
            stepsToday = try await fetchStepsForCurrentDay()
            hasStepsData = true
            cacheStepsToday()
        } catch {
            AppLogger.healthKit.error("⚠️ Failed to refresh steps: \(error.localizedDescription)")
            loadCachedStepsToday()
        }
    }
    
    func refreshSleepIfAuthorized() async {
        let status = healthKitService.sleepAuthorizationStatus()
        AppLogger.healthKit.debug("🛌 HealthKit sleep write-status: \(status.rawValue)")
        // authorizationStatus reports WRITE permission. Read access can still be allowed when status is denied.
        do {
            let now = Date()
            let start = currentDayStart(for: now)
            dailySleepHours = try await healthKitService.fetchSleep(from: start, to: now)
            hasSleepData = true
            AppLogger.healthKit.debug("🛌 Fetched sleep hours: \(String(format: "%.2f", self.dailySleepHours))h")
        } catch {
            AppLogger.healthKit.error("⚠️ Failed to refresh sleep: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helpers
    private func currentDayStart(for date: Date) -> Date {
        let (hour, minute) = DayBoundary.storedDayEnd()
        return DayBoundary.currentDayStart(for: date, dayEndHour: hour, dayEndMinute: minute)
    }
    
    // MARK: - Caching
    private func cacheStepsToday() {
        let g = UserDefaults.stepsTrader()
        g.set(stepsToday, forKey: "cachedStepsToday")
        g.set(true, forKey: "hasStepsData_v1")
    }
    
    private func loadCachedStepsToday() {
        let g = UserDefaults.stepsTrader()
        let cached = g.double(forKey: "cachedStepsToday")
        stepsToday = cached
        // Use a separate flag so 0 steps is distinguishable from "never fetched"
        hasStepsData = g.bool(forKey: "hasStepsData_v1")
    }
    
    // MARK: - Observation
    func startObservingSteps() {
        healthKitService.startObservingSteps { [weak self] (steps: Double) in
            Task { @MainActor [weak self] in
                self?.stepsToday = steps
                self?.hasStepsData = true
                self?.cacheStepsToday()
            }
        }
    }
    
    func stopObservingSteps() {
        healthKitService.stopObservingSteps()
    }
}
