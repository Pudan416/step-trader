import HealthKit
import os.log

// MARK: - HealthKit Logger
private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StepsTrader", category: "HealthKit")

// MARK: - HealthKit Errors

enum HealthKitServiceError: LocalizedError {
    case healthKitNotAvailable
    case stepTypeNotAvailable
    case sleepTypeNotAvailable
    case authorizationTimeout
    
    var errorDescription: String? {
        switch self {
        case .healthKitNotAvailable:
            return "HealthKit is not available on this device"
        case .stepTypeNotAvailable:
            return "Step count type is not available"
        case .sleepTypeNotAvailable:
            return "Sleep analysis type is not available"
        case .authorizationTimeout:
            return "HealthKit authorization dialog did not appear"
        }
    }
}

private final class UnsafeSendableBox: @unchecked Sendable {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}

@preconcurrency
final class HealthKitService: HealthKitServiceProtocol {
    private let store = HKHealthStore()
    private let stepType: HKQuantityType?
    private let sleepType: HKCategoryType?
    @MainActor private var observerQuery: HKQuery?
    @MainActor private var isObserving = false
    @MainActor private var isRequestingAuthorization = false

    private let _stepCountLock = NSLock()
    private var _lastStepCountBacking: Double = 0
    private var lastStepCount: Double {
        get { _stepCountLock.withLock { _lastStepCountBacking } }
        set { _stepCountLock.withLock { _lastStepCountBacking = newValue } }
    }
    
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
        var readTypes: Set<HKObjectType> = [stepType, sleepType]
        readTypes.insert(HKObjectType.workoutType())
        if let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
            readTypes.insert(mindfulType)
        }
        let status = try await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
        log.info("Request status: \(status.rawValue) (\(Self.describeAuthorizationRequestStatus(status)))")
        logAuthorizationStatus(context: "requestAuthorization:pre-flight")
        
        if status == .unnecessary {
            log.info("requestAuthorization skipped — read access already granted")
        } else {
            // Use the completion-handler API and wrap in a continuation.
            // The async overload silently hangs on some iOS versions.
            let didFinish = UnsafeSendableBox(false)
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
                store.requestAuthorization(toShare: [], read: readTypes) { success, error in
                    guard !didFinish.value else { return }
                    didFinish.value = true
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume()
                    }
                }
                // Timeout — release the continuation after 10s even if the
                // completion handler never fires.
                Task.detached {
                    try? await Task.sleep(for: .seconds(10))
                    if !didFinish.value {
                        didFinish.value = true
                        log.warning("requestAuthorization timed out after 10s")
                        cont.resume(throwing: HealthKitServiceError.authorizationTimeout)
                    }
                }
            }
            log.info("requestAuthorization completed")
            logAuthorizationStatus(context: "requestAuthorization:post-request")
        }
        
        // Enable background delivery for steps so HKObserverQuery fires when suspended.
        // Sleep background delivery removed — no observer registered; sleep refreshes on foreground.
        if let stepType = self.stepType {
            try await store.enableBackgroundDelivery(for: stepType, frequency: .immediate)
            log.info("Background delivery for step count enabled")
        }
    }

    private static func describeAuthorizationRequestStatus(_ status: HKAuthorizationRequestStatus) -> String {
        switch status {
        case .shouldRequest: return "shouldRequest"
        case .unnecessary: return "unnecessary"
        case .unknown: return "unknown"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    func fetchSleep(from start: Date, to end: Date) async throws -> Double {
        guard let sleepType = sleepType else {
            log.warning("Sleep type not available, returning 0")
            return 0
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

        // Passive HKStatisticsQuery does not show the permission sheet.
        // Do not gate on authorizationStatus(for:) — it reports WRITE status only.
        // Read-only apps (toShare: []) stay .notDetermined even after the user allows reads.

        // Use .strictStartDate to exclude samples that started before the day boundary.
        // Without it, sources like WHOOP that write one giant sample spanning 22+ hours
        // leak yesterday's entire step count into today's total (14k+ phantom steps).
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        log.info("👣 fetchSteps QUERY: \(start) … \(end), lastStepCount=\(self.lastStepCount)")

        // Diagnostic: log sample breakdown by source (runs in background, doesn't affect result)
        let diagnosticStore = self.store
        Task.detached {
            let sampleQuery = HKSampleQuery(
                sampleType: stepType,
                predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
                limit: 200,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                guard let samples = samples as? [HKQuantitySample] else { return }
                var bySource: [String: Double] = [:]
                for s in samples {
                    let source = s.sourceRevision.source.name
                    let steps = s.quantity.doubleValue(for: .count())
                    bySource[source, default: 0] += steps
                }
                log.info("👣 DIAG: \(samples.count) samples (strictStartDate)")
                for (source, total) in bySource.sorted(by: { $0.value > $1.value }) {
                    log.info("👣 DIAG source '\(source)': \(Int(total)) steps")
                }
            }
            diagnosticStore.execute(sampleQuery)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, stats, error in
                guard let self = self else {
                    continuation.resume(returning: 0)
                    return
                }
                if let error = error {
                    let nsError = error as NSError
                    if nsError.code == 11 || // HKErrorCode 11 - no data available
                       nsError.localizedDescription.contains("No data available") {
                        log.debug("No step data available for period, returning 0")
                        continuation.resume(returning: 0)
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
                let prevCached = self.lastStepCount
                self.lastStepCount = steps
                log.info("👣 fetchSteps RESULT: HK returned \(Int(steps)) steps (was cached: \(Int(prevCached)))")
                if steps > 0 {
                    self.logAuthorizationStatus(context: "fetchTodaySteps:data-available")
                }
                continuation.resume(returning: steps)
            }
            store.execute(query)
        }
    }
    
    // MARK: - Workouts
    func fetchWorkouts(from start: Date, to end: Date) async throws -> [DetectedWorkout] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: 20,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    log.error("fetchWorkouts error: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }
                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }
                let results = workouts.map { w in
                    DetectedWorkout(
                        id: w.uuid,
                        activityType: w.workoutActivityType.rawValue,
                        startDate: w.startDate,
                        endDate: w.endDate,
                        durationMinutes: Int(w.duration / 60),
                        caloriesBurned: w.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                        distance: w.totalDistance?.doubleValue(for: .meter())
                    )
                }
                log.info("Fetched \(results.count) workouts for period")
                continuation.resume(returning: results)
            }
            store.execute(query)
        }
    }

    // MARK: - Mindful Minutes
    func fetchMindfulMinutes(from start: Date, to end: Date) async throws -> Double {
        guard HKHealthStore.isHealthDataAvailable() else { return 0 }
        guard let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            return 0
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: mindfulType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    log.error("fetchMindfulMinutes error: \(error.localizedDescription)")
                    continuation.resume(returning: 0)
                    return
                }
                guard let sessions = samples as? [HKCategorySample] else {
                    continuation.resume(returning: 0)
                    return
                }
                var intervals: [(start: Date, end: Date)] = []
                for session in sessions {
                    let overlapStart = max(session.startDate, start)
                    let overlapEnd = min(session.endDate, end)
                    if overlapEnd > overlapStart {
                        intervals.append((start: overlapStart, end: overlapEnd))
                    }
                }
                let totalMinutes = Self.mergedDuration(of: intervals) / 60.0
                log.info("Fetched mindful minutes: \(String(format: "%.1f", totalMinutes)) from \(sessions.count) sessions")
                continuation.resume(returning: totalMinutes)
            }
            store.execute(query)
        }
    }

    // MARK: - Background Updates
    @MainActor
    func startObservingSteps(updateHandler: @escaping (Double) -> Void) {
        guard !isObserving else { return }
        guard stepType != nil else {
            log.warning("Step type not available, cannot observe")
            return
        }

        // Note: authorizationStatus() returns WRITE status, not READ status.
        // For read-only apps, sharingDenied is expected and doesn't mean read is denied.
        // We should just try to observe and fetch data.
        
        Task { [weak self] in
            guard let self = self else { return }
            // Initial fetch so UI has fresh value before observer fires
            let dayStart = Date.startOfToday
            log.info("👣 startObservingSteps: initial fetch dayStart=\(dayStart)")
            if let steps = try? await self.fetchSteps(from: dayStart, to: Date.now) {
                log.info("👣 startObservingSteps: initial fetch returned \(Int(steps)), pushing to UI")
                self.lastStepCount = steps
                await MainActor.run { updateHandler(steps) }
            } else {
                log.warning("👣 startObservingSteps: initial fetch FAILED, lastStepCount=\(self.lastStepCount)")
            }
            await self.beginObservation(updateHandler: updateHandler)
        }
    }

    @MainActor
    func stopObservingSteps() {
        guard let query = observerQuery else { return }

        store.stop(query)
        observerQuery = nil
        isObserving = false
        log.info("Step observation stopped")
    }

    func clearLastStepCount() {
        lastStepCount = 0
    }

    @MainActor
    private func beginObservation(updateHandler: @escaping (Double) -> Void) async {
        guard !isObserving else { return }
        guard let stepType = stepType else {
            log.warning("Step type not available, cannot begin observation")
            return
        }

        let observerDayStart = Date.startOfToday
        log.info("👣 beginObservation: predicate startDate=\(observerDayStart)")

        let predicate = HKQuery.predicateForSamples(
            withStart: observerDayStart,
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
                let refetchStart = Date.startOfToday
                log.info("👣 OBSERVER FIRED: re-fetching from \(refetchStart)")
                do {
                    let steps = try await self.fetchSteps(from: refetchStart, to: Date.now)
                    log.info("👣 OBSERVER re-fetch: \(Int(steps)) steps, pushing to UI")
                    self.lastStepCount = steps
                    await MainActor.run { updateHandler(steps) }
                } catch {
                    log.error("👣 OBSERVER re-fetch FAILED: \(error.localizedDescription), lastStepCount=\(self.lastStepCount)")
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
