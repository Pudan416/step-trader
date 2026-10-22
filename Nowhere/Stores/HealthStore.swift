import Foundation
import HealthKit
import Combine

/// The latest explicit refresh result, separate from cached values and write
/// authorization. `empty` means the aggregate was zero; it does not prove that
/// the user denied reads or that HealthKit contains no samples.
enum HealthQueryOutcome: String, Equatable {
    case idle, loading, available, empty, failed
}

@MainActor
final class HealthStore: ObservableObject {
    // Dependencies
    private let healthKitService: any HealthKitServiceProtocol
    private let defaults: UserDefaults
    
    // Published State
    @Published var stepsToday: Double = 0
    @Published var dailySleepHours: Double = 0
    @Published var baseEnergyToday: Int = 0
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
    /// True once today's step query resolves, including empty/unavailable Health,
    /// or a cached result is loaded. This does not imply read permission.
    /// Do not infer from `stepsToday > 0` — a resolved zero count is valid.
    @Published var hasStepsData: Bool = false
    /// True once HealthKit has returned sleep data.
    @Published var hasSleepData: Bool = false
    @Published private(set) var stepsQueryOutcome: HealthQueryOutcome = .idle
    @Published private(set) var sleepQueryOutcome: HealthQueryOutcome = .idle
    private var stepsQueryID: UUID?
    private var sleepQueryID: UUID?
    private var stepsObservationID: UUID?
    
    init(healthKitService: any HealthKitServiceProtocol, defaults: UserDefaults = .nowhere()) {
        self.healthKitService = healthKitService
        self.defaults = defaults
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
        let now = Date.now
        let dayStart = currentDayStart(for: now)
        let queryID = UUID()
        stepsQueryID = queryID
        stepsQueryOutcome = .loading
        defer {
            if stepsQueryID == queryID, stepsQueryOutcome == .loading {
                stepsQueryID = nil
                stepsQueryOutcome = .idle
            }
        }
        do {
            let trace = HealthQueryTrace()
            let steps = try await HealthQueryTrace.$current.withValue(trace) {
                try await healthKitService.fetchSteps(from: dayStart, to: now)
            }
            guard stepsQueryID == queryID, currentDayStart(for: .now) == dayStart,
                  !Task.isCancelled else { return }
            stepsToday = steps
            stepsQueryOutcome = trace.didFail ? .failed : steps > 0 ? .available : .empty
            hasStepsData = true
            cacheStepsToday()
            AppLogger.healthKit.info("👣 refreshSteps: \(Int(before)) → \(Int(self.stepsToday)) (fetched OK, cached)")
        } catch {
            guard stepsQueryID == queryID, currentDayStart(for: .now) == dayStart,
                  !Task.isCancelled, !(error is CancellationError) else { return }
            stepsQueryOutcome = .failed
            AppLogger.healthKit.error("👣 refreshSteps FAILED: \(error.localizedDescription), was \(Int(before))")
            loadCachedStepsToday()
            if Self.isUnavailableHealthData(error) {
                // Declining or skipping Health still resolves the daily fallback.
                // A same-day cached measurement always takes precedence.
                hasStepsData = true
                cacheStepsToday()
            }
            AppLogger.healthKit.error("👣 refreshSteps: fallback to cache → \(Int(self.stepsToday))")
        }
    }
    
    func refreshSleepIfAuthorized() async {
        let now = Date.now
        let dayStart = currentDayStart(for: now)
        let queryID = UUID()
        sleepQueryID = queryID
        sleepQueryOutcome = .loading
        defer {
            if sleepQueryID == queryID, sleepQueryOutcome == .loading {
                sleepQueryID = nil
                sleepQueryOutcome = .idle
            }
        }
        let status = healthKitService.sleepAuthorizationStatus()
        AppLogger.healthKit.debug("🛌 HealthKit sleep write-status: \(status.rawValue)")
        // authorizationStatus reports WRITE permission. Read access can still be allowed when status is denied.
        do {
            let hours = try await healthKitService.fetchSleep(from: dayStart, to: now)
            guard sleepQueryID == queryID, currentDayStart(for: .now) == dayStart,
                  !Task.isCancelled else { return }
            dailySleepHours = hours
            sleepQueryOutcome = hours > 0 ? .available : .empty
            hasSleepData = true
            cacheSleepToday()
            AppLogger.healthKit.debug("🛌 Fetched sleep hours: \(String(format: "%.2f", self.dailySleepHours))h")
        } catch {
            guard sleepQueryID == queryID, currentDayStart(for: .now) == dayStart,
                  !Task.isCancelled, !(error is CancellationError) else { return }
            sleepQueryOutcome = .failed
            AppLogger.healthKit.error("⚠️ Failed to refresh sleep: \(error.localizedDescription)")
            loadCachedSleepToday()
            if Self.isUnavailableHealthData(error) {
                hasSleepData = true
            }
        }
    }

    /// A locked database or a transient query failure is not proof of missing data.
    /// Check the query's actual error, never HealthKit's write authorization status.
    private static func isUnavailableHealthData(_ error: Error) -> Bool {
        if let serviceError = error as? HealthKitServiceError,
           serviceError == .healthKitNotAvailable {
            return true
        }
        let healthError = error as NSError
        guard healthError.domain == HKErrorDomain else { return false }
        return [
            HKError.Code.errorHealthDataUnavailable,
            .errorAuthorizationNotDetermined,
            .errorAuthorizationDenied,
            .errorNoData,
        ].contains { $0.rawValue == healthError.code }
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
        let (hour, minute) = DayBoundary.storedDayEnd(group: defaults)
        return DayBoundary.currentDayStart(for: date, dayEndHour: hour, dayEndMinute: minute)
    }
    
    // MARK: - Caching
    private func cacheStepsToday() {
        let g = defaults
        g.set(stepsToday, forKey: SharedKeys.cachedStepsToday)
        g.set(true, forKey: SharedKeys.hasStepsData)
    }
    
    private func loadCachedStepsToday() {
        let g = defaults
        let (hour, minute) = DayBoundary.storedDayEnd(group: defaults)
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
        defaults.set(dailySleepHours, forKey: Self.cachedSleepKey)
    }

    private func loadCachedSleepToday() {
        let cached = defaults.double(forKey: Self.cachedSleepKey)
        if cached > 0 { dailySleepHours = cached }
    }
    
    func clearCachedStepCount() {
        // Daily rollover and sign-out invalidate sleep as well as steps, even
        // when no replacement refresh has started yet.
        stopObservingSteps()
        healthKitService.clearLastStepCount()
    }

    // MARK: - Observation
    @MainActor
    func startObservingSteps() {
        guard stepsObservationID == nil else { return }
        let observationID = UUID()
        stepsObservationID = observationID
        let dayStart = currentDayStart(for: .now)
        healthKitService.startObservingSteps { [weak self] (steps: Double) in
            Task { @MainActor [weak self] in
                guard let self, self.stepsObservationID == observationID,
                      self.currentDayStart(for: .now) == dayStart else { return }
                self.stepsQueryOutcome = steps > 0 ? .available : .empty
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
        stepsObservationID = nil
        stepsQueryID = nil
        sleepQueryID = nil
        stepsQueryOutcome = .idle
        sleepQueryOutcome = .idle
        healthKitService.stopObservingSteps()
    }
}
