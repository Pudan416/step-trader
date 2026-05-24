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
        loadCachedStepsToday()
        loadCachedSleepToday()
    }
    
    func requestAuthorization() async throws {
        do {
            try await healthKitService.requestAuthorization()
            authorizationStatus = healthKitService.authorizationStatus()
        } catch let error as HealthKitServiceError where error == .authorizationTimeout {
            AppLogger.healthKit.warning("HealthKit auth timed out — will retry on next attempt")
            throw error
        } catch {
            ErrorManager.shared.handle(AppError.healthKitAuthorizationFailed(error))
            throw error
        }
    }
    
    func fetchStepsForCurrentDay() async throws -> Double {
        let now = Date.now
        let start = currentDayStart(for: now)
        return try await healthKitService.fetchSteps(from: start, to: now)
    }
    
    func refreshStepsIfAuthorized() async {
        // Always attempt to fetch steps. authorizationStatus() reports WRITE permission,
        // not READ. Read access may be granted even when write status is .notDetermined
        // or .sharingDenied, so guarding on .sharingAuthorized silently blocks step fetching
        // for most users.
        let before = stepsToday
        do {
            stepsToday = try await fetchStepsForCurrentDay()
            hasStepsData = true
            cacheStepsToday()
            AppLogger.healthKit.info("👣 refreshSteps: \(Int(before)) → \(Int(self.stepsToday)) (fetched OK, cached)")
        } catch {
            AppLogger.healthKit.error("👣 refreshSteps FAILED: \(error.localizedDescription), was \(Int(before))")
            loadCachedStepsToday()
            AppLogger.healthKit.error("👣 refreshSteps: fallback to cache → \(Int(self.stepsToday))")
        }
    }
    
    func refreshSleepIfAuthorized() async {
        let status = healthKitService.sleepAuthorizationStatus()
        AppLogger.healthKit.debug("🛌 HealthKit sleep write-status: \(status.rawValue)")
        // authorizationStatus reports WRITE permission. Read access can still be allowed when status is denied.
        do {
            let now = Date.now
            let start = currentDayStart(for: now)
            dailySleepHours = try await healthKitService.fetchSleep(from: start, to: now)
            hasSleepData = true
            cacheSleepToday()
            AppLogger.healthKit.debug("🛌 Fetched sleep hours: \(String(format: "%.2f", self.dailySleepHours))h")
        } catch {
            AppLogger.healthKit.error("⚠️ Failed to refresh sleep: \(error.localizedDescription)")
            loadCachedSleepToday()
        }
    }
    
    // MARK: - Workouts & Mindful Minutes
    func fetchTodayMindfulMinutes() async -> Double {
        let now = Date.now
        let start = currentDayStart(for: now)
        do {
            return try await healthKitService.fetchMindfulMinutes(from: start, to: now)
        } catch {
            AppLogger.healthKit.error("⚠️ Failed to fetch mindful minutes: \(error.localizedDescription)")
            return 0
        }
    }

    func fetchTodayWorkouts() async -> [DetectedWorkout] {
        let now = Date.now
        let start = currentDayStart(for: now)
        do {
            return try await healthKitService.fetchWorkouts(from: start, to: now)
        } catch {
            AppLogger.healthKit.error("⚠️ Failed to fetch workouts: \(error.localizedDescription)")
            return []
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
        g.set(stepsToday, forKey: SharedKeys.cachedStepsToday)
        g.set(true, forKey: SharedKeys.hasStepsData)
    }
    
    private func loadCachedStepsToday() {
        let g = UserDefaults.stepsTrader()
        let (hour, minute) = DayBoundary.storedDayEnd()
        if let anchor = g.object(forKey: SharedKeys.dailyEnergyAnchor) as? Date,
           DayBoundary.isPersistedDayBehind(anchor: anchor, relativeTo: .now, dayEndHour: hour, dayEndMinute: minute) {
            AppLogger.healthKit.info("👣 loadCache: STALE anchor \(anchor), clearing to 0")
            stepsToday = 0
            hasStepsData = false
            return
        }
        let cached = g.double(forKey: SharedKeys.cachedStepsToday)
        stepsToday = cached
        hasStepsData = g.bool(forKey: SharedKeys.hasStepsData)
        AppLogger.healthKit.info("👣 loadCache: loaded \(Int(cached)) from UserDefaults")
    }

    private static let cachedSleepKey = "cachedSleepHoursToday"

    private func cacheSleepToday() {
        UserDefaults.stepsTrader().set(dailySleepHours, forKey: Self.cachedSleepKey)
    }

    private func loadCachedSleepToday() {
        let cached = UserDefaults.stepsTrader().double(forKey: Self.cachedSleepKey)
        if cached > 0 { dailySleepHours = cached }
    }
    
    func clearCachedStepCount() {
        healthKitService.clearLastStepCount()
    }

    // MARK: - Observation
    @MainActor
    func startObservingSteps() {
        healthKitService.startObservingSteps { [weak self] (steps: Double) in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let before = self.stepsToday
                self.stepsToday = steps
                self.hasStepsData = true
                self.cacheStepsToday()
                AppLogger.healthKit.info("👣 OBSERVER→UI: \(Int(before)) → \(Int(steps))")
            }
        }
    }
    
    @MainActor
    func stopObservingSteps() {
        healthKitService.stopObservingSteps()
    }
}
