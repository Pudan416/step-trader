import HealthKit
import os.log

// MARK: - HealthKit Logger
private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StepsTrader", category: "HealthKit")

// MARK: - HealthKit Errors

enum HealthKitServiceError: LocalizedError {
    case healthKitNotAvailable
    case stepTypeNotAvailable
    case sleepTypeNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .healthKitNotAvailable:
            return "HealthKit is not available on this device"
        case .stepTypeNotAvailable:
            return "Step count type is not available"
        case .sleepTypeNotAvailable:
            return "Sleep analysis type is not available"
        }
    }
}

@preconcurrency
final class HealthKitService: HealthKitServiceProtocol {
    private let store = HKHealthStore()
    private let stepType: HKQuantityType?
    private let sleepType: HKCategoryType?
    private var observerQuery: HKQuery?
    private var isObserving = false
    private var lastStepCount: Double = 0
    private var isRequestingAuthorization = false
    
    init() {
        self.stepType = HKObjectType.quantityType(forIdentifier: .stepCount)
        self.sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
    }

    @MainActor
    func authorizationStatus() -> HKAuthorizationStatus {
        // Return status for steps (primary type)
        // Sleep checked separately if needed
        guard let stepType = stepType else { return .notDetermined }
        return store.authorizationStatus(for: stepType)
    }
    
    @MainActor
    func sleepAuthorizationStatus() -> HKAuthorizationStatus {
        guard let sleepType = sleepType else { return .notDetermined }
        return store.authorizationStatus(for: sleepType)
    }

    @MainActor
    func requestAuthorization() async throws {
        if isRequestingAuthorization {
            log.debug("Authorization already in-flight, skipping duplicate call")
            return
        }
        isRequestingAuthorization = true
        defer { isRequestingAuthorization = false }

        log.info("requestAuthorization started on main actor")
        logHealthKitEntitlement()
        logEmbeddedProfileHealthKit()
        log.info("isHealthDataAvailable: \(HKHealthStore.isHealthDataAvailable())")
        guard HKHealthStore.isHealthDataAvailable() else {
            log.error("HealthKit is not available on this device/configuration")
            throw HealthKitServiceError.healthKitNotAvailable
        }
        guard let stepType = stepType else {
            log.error("Step count type not available")
            throw HealthKitServiceError.stepTypeNotAvailable
        }
        guard let sleepType = sleepType else {
            log.error("Sleep analysis type not available")
            throw HealthKitServiceError.sleepTypeNotAvailable
        }
        let readTypes: Set<HKObjectType> = [stepType, sleepType]
        let status = try await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
        log.info("Request status: \(status.rawValue)")
        logAuthorizationStatus(context: "requestAuthorization:pre-flight")
        
        // Native async API — no continuation wrapper or timeout watchdog needed
        try await store.requestAuthorization(toShare: [], read: readTypes)
        log.info("requestAuthorization completed")
        logAuthorizationStatus(context: "requestAuthorization:post-request")
        
        // Enable background delivery for steps so HKObserverQuery fires when suspended.
        // Sleep background delivery removed — no observer registered; sleep refreshes on foreground.
        if let stepType = self.stepType {
            try await store.enableBackgroundDelivery(for: stepType, frequency: .immediate)
            log.info("Background delivery for step count enabled")
        }
    }

    func fetchSleep(from start: Date, to end: Date) async throws -> Double {
        guard let sleepType = sleepType else {
            log.warning("Sleep type not available, returning 0")
            return 0
        }
        
        // Ensure authorization is determined before querying
        let sleepAuthStatus = store.authorizationStatus(for: sleepType)
        if sleepAuthStatus == .notDetermined {
            try await requestAuthorization()
        }
        
        // P10: Clamp lookback to 24h to avoid ancient samples whose endDate falls in the window
        let maxLookback: TimeInterval = 24 * 3600
        let clampedStart = max(start, end.addingTimeInterval(-maxLookback))
        
        let predicate = HKQuery.predicateForSamples(withStart: clampedStart, end: end, options: [])
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { [clampedStart] _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                // Only sum actual sleep phases (asleep*). inBed overlaps with asleep
                // causing double-counting: inBed 22:00–07:00 (9h) + asleep 22:30–06:30 (8h) = 17h instead of 8h.
                var intervals: [(start: Date, end: Date)] = []
                if let samples = samples as? [HKCategorySample] {
                    log.debug("fetchSleep: samples=\(samples.count)")
                    for sample in samples {
                        let sleepValue = sample.value
                        var shouldCount = false
                        if #available(iOS 16.0, *) {
                            shouldCount = sleepValue == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                                         sleepValue == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                                         sleepValue == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                                         sleepValue == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                        } else {
                            shouldCount = sleepValue == HKCategoryValueSleepAnalysis.asleep.rawValue
                        }
                        if shouldCount {
                            let overlapStart = max(sample.startDate, clampedStart)
                            let overlapEnd = min(sample.endDate, end)
                            if overlapEnd > overlapStart {
                                intervals.append((start: overlapStart, end: overlapEnd))
                            }
                        }
                    }
                }
                
                // P8: Merge overlapping intervals to prevent double-counting from multiple sources
                let totalSleepHours = Self.mergedDuration(of: intervals) / 3600.0
                
                log.debug("fetchSleep: totalHours=\(totalSleepHours) (from \(intervals.count) intervals)")
                continuation.resume(returning: totalSleepHours)
            }
            store.execute(query)
        }
    }
    
    /// Merge overlapping time intervals and return total duration in seconds.
    /// Handles Watch + Phone recording overlapping sleep sessions.
    static func mergedDuration(of intervals: [(start: Date, end: Date)]) -> TimeInterval {
        guard !intervals.isEmpty else { return 0 }
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [(start: Date, end: Date)] = [sorted[0]]
        for interval in sorted.dropFirst() {
            if interval.start <= merged[merged.count - 1].end {
                // Overlapping or adjacent — extend the current merged interval
                merged[merged.count - 1].end = max(merged[merged.count - 1].end, interval.end)
            } else {
                merged.append(interval)
            }
        }
        return merged.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
    }
    
    func fetchSteps(from start: Date, to end: Date) async throws -> Double {
        guard let stepType = stepType else {
            log.warning("Step type not available, returning cached: \(self.lastStepCount)")
            return lastStepCount
        }
        
        // Ensure authorization is determined before querying
        let stepAuthStatus = store.authorizationStatus(for: stepType)
        if stepAuthStatus == .notDetermined {
            try await requestAuthorization()
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, stats, error in
                guard let self = self else {
                    continuation.resume(returning: 0)
                    return
                }
                if let error = error {
                    // If the error is "No data available", return 0 instead of failing
                    let nsError = error as NSError
                    if nsError.code == 11 || // HKErrorCode 11 - no data available
                       nsError.localizedDescription.contains("No data available") {
                        log.debug("No step data available for today, returning cached")
                        continuation.resume(returning: self.lastStepCount)
                        return
                    }
                    log.error("HealthKit error: \(error.localizedDescription)")
                    if self.lastStepCount > 0 {
                        continuation.resume(returning: self.lastStepCount)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                
                let steps = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                self.lastStepCount = steps
                log.info("Fetched \(Int(steps)) steps for today")
                if steps > 0 {
                    self.logAuthorizationStatus(context: "fetchTodaySteps:data-available")
                }
                continuation.resume(returning: steps)
            }
            store.execute(query)
        }
    }
    
    // MARK: - Background Updates
    func startObservingSteps(updateHandler: @escaping (Double) -> Void) {
        guard !isObserving else { return }
        guard let stepType = stepType else {
            log.warning("Step type not available, cannot observe")
            return
        }

        // Note: authorizationStatus() returns WRITE status, not READ status.
        // For read-only apps, sharingDenied is expected and doesn't mean read is denied.
        // We should just try to observe and fetch data.
        
        Task { [weak self] in
            guard let self = self else { return }
            // Request authorization if not done yet
            let observeAuthStatus = self.store.authorizationStatus(for: stepType)
            if observeAuthStatus == .notDetermined {
                log.warning("Authorization not determined. Requesting before observing.")
                do {
                    try await self.requestAuthorization()
                } catch {
                    log.error("Authorization request failed: \(error.localizedDescription)")
                }
            }
            
            // Initial fetch so UI has fresh value before observer fires
            if let steps = try? await self.fetchSteps(from: Date.startOfToday, to: Date()) {
                self.lastStepCount = steps
                await MainActor.run { updateHandler(steps) }
            }
            await self.beginObservation(updateHandler: updateHandler)
        }
    }

    func stopObservingSteps() {
        guard let query = observerQuery else { return }
        
        store.stop(query)
        observerQuery = nil
        isObserving = false
        log.info("Step observation stopped")
    }

    @MainActor
    private func beginObservation(updateHandler: @escaping (Double) -> Void) async {
        guard !isObserving else { return }
        guard let stepType = stepType else {
            log.warning("Step type not available, cannot begin observation")
            return
        }

        log.info("Starting step observation")

        let predicate = HKQuery.predicateForSamples(
            withStart: Date.startOfToday,
            end: nil,
            options: .strictStartDate
        )

        // Use HKObserverQuery to detect changes, then re-fetch the accurate cumulative total
        // via HKStatisticsQuery. This avoids the double-counting risk of accumulating deltas
        // from HKAnchoredObjectQuery when samples are re-delivered after background wakes.
        observerQuery = HKObserverQuery(sampleType: stepType, predicate: predicate) { [weak self] _, completionHandler, error in
            guard let self = self else {
                completionHandler()
                return
            }
            if let error = error {
                log.error("Observer query error: \(error.localizedDescription)")
                completionHandler()
                return
            }
            Task {
                defer { completionHandler() }
                do {
                    let steps = try await self.fetchSteps(from: Date.startOfToday, to: Date())
                    self.lastStepCount = steps
                    await MainActor.run { updateHandler(steps) }
                } catch {
                    log.error("Observer re-fetch failed: \(error.localizedDescription)")
                }
            }
        }

        if let query = observerQuery {
            store.execute(query)
            isObserving = true
            log.info("Step observation started (observer + statistics re-fetch)")
        }
    }

    private func logAuthorizationStatus(context: String) {
        let stepStatusDescription: String
        let sleepStatusDescription: String
        
        if let stepType = stepType {
            let stepStatus = store.authorizationStatus(for: stepType)
            switch stepStatus {
            case .sharingAuthorized:
                stepStatusDescription = "sharing authorized"
            case .sharingDenied:
                stepStatusDescription = "sharing denied"
            case .notDetermined:
                stepStatusDescription = "not determined"
            @unknown default:
                stepStatusDescription = "unknown (\(stepStatus.rawValue))"
            }
        } else {
            stepStatusDescription = "type unavailable"
        }
        
        if let sleepType = sleepType {
            let sleepStatus = store.authorizationStatus(for: sleepType)
            switch sleepStatus {
            case .sharingAuthorized:
                sleepStatusDescription = "sharing authorized"
            case .sharingDenied:
                sleepStatusDescription = "sharing denied"
            case .notDetermined:
                sleepStatusDescription = "not determined"
            @unknown default:
                sleepStatusDescription = "unknown (\(sleepStatus.rawValue))"
            }
        } else {
            sleepStatusDescription = "type unavailable"
        }
        
        log.debug("[\(context)] steps=\(stepStatusDescription), sleep=\(sleepStatusDescription)")
    }

    private func logHealthKitEntitlement() {
        // SecTask* APIs can be unavailable in some build configs; skip detailed entitlement check.
        log.debug("Entitlement check skipped (SecTask APIs unavailable in this build)")
    }

    private func logEmbeddedProfileHealthKit() {
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let content = String(data: data, encoding: .ascii) else {
            log.debug("embedded.mobileprovision not found or unreadable")
            return
        }
        let hasHealthKit = content.contains("com.apple.developer.healthkit")
        let hasBackground = content.contains("com.apple.developer.healthkit.background-delivery")
        log.debug("Provision profile contains healthkit: \(hasHealthKit), background: \(hasBackground)")
    }
}
