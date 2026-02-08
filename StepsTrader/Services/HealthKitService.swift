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
    private var stepsAnchor: HKQueryAnchor?
    private var lastStepCount: Double = 0
    private var isRequestingAuthorization = false
    private var authTimeoutTask: Task<Void, Never>?
    
    init() {
        self.stepType = HKObjectType.quantityType(forIdentifier: .stepCount)
        self.sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
    }

    @MainActor
    func authorizationStatus() -> HKAuthorizationStatus {
        // Возвращаем статус для шагов (основной тип)
        // Для сна проверяем отдельно, если нужно
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
        if #available(iOS 15.0, *) {
            let status = try await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
            log.info("Request status: \(status.rawValue)")
        }
        logAuthorizationStatus(context: "requestAuthorization:pre-flight")
        // Watchdog in case completion never fires
        authTimeoutTask?.cancel()
        authTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if self.isRequestingAuthorization {
                log.warning("requestAuthorization appears stalled (no completion in 5s). Resetting flag.")
                self.isRequestingAuthorization = false
            }
        }
        let granted: Bool = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            store.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
        log.info("requestAuthorization returned: \(granted)")
        logAuthorizationStatus(context: "requestAuthorization:post-request")
        authTimeoutTask?.cancel()
        
        // Enable background delivery for automatic updates
        if #available(iOS 12.0, *) {
            if let stepType = self.stepType {
                try await store.enableBackgroundDelivery(for: stepType, frequency: .immediate)
                log.info("Background delivery for step count enabled")
            }
            if let sleepType = self.sleepType {
                try await store.enableBackgroundDelivery(for: sleepType, frequency: .immediate)
                log.info("Background delivery for sleep data enabled")
            }
        }
    }

    func fetchTodaySteps() async throws -> Double {
        let now = Date()
        return try await fetchSteps(from: .startOfToday, to: now)
    }
    
    func fetchTodaySleep() async throws -> Double {
        let now = Date()
        return try await fetchSleep(from: .startOfToday, to: now)
    }
    
    func fetchSleep(from start: Date, to end: Date) async throws -> Double {
        guard let sleepType = sleepType else {
            log.warning("Sleep type not available, returning 0")
            return 0
        }
        
        // Ensure authorization is determined before querying
        if #available(iOS 12.0, *) {
            let status = store.authorizationStatus(for: sleepType)
            if status == .notDetermined {
                try await requestAuthorization()
            }
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                // Суммируем только фазы реального сна (asleep*). inBed не считаем — он перекрывается с asleep
                // и даёт двойной учёт: inBed 22:00–07:00 (9ч) + asleep 22:30–06:30 (8ч) = 17ч вместо 8ч.
                var totalSleepHours: Double = 0
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
                            // inBed намеренно не учитываем — это интервал «лёг–встал», внутри него уже есть asleep*
                        } else {
                            shouldCount = sleepValue == HKCategoryValueSleepAnalysis.asleep.rawValue
                        }
                        if shouldCount {
                            // Count only the overlap with [start, end]
                            let overlapStart = max(sample.startDate, start)
                            let overlapEnd = min(sample.endDate, end)
                            let duration = overlapEnd.timeIntervalSince(overlapStart)
                            if duration > 0 {
                                totalSleepHours += duration / 3600.0
                            }
                        }
                    }
                }
                
                log.debug("fetchSleep: totalHours=\(totalSleepHours)")
                continuation.resume(returning: totalSleepHours)
            }
            store.execute(query)
        }
    }
    
    func fetchSteps(from start: Date, to end: Date) async throws -> Double {
        guard let stepType = stepType else {
            log.warning("Step type not available, returning cached: \(self.lastStepCount)")
            return lastStepCount
        }
        
        // Ensure authorization is determined before querying
        if #available(iOS 12.0, *) {
            let status = store.authorizationStatus(for: stepType)
            if status == .notDetermined {
                try await requestAuthorization()
            }
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
            if #available(iOS 12.0, *) {
                let status = self.store.authorizationStatus(for: stepType)
                if status == .notDetermined {
                    log.warning("Authorization not determined. Requesting before observing.")
                    do {
                        try await self.requestAuthorization()
                    } catch {
                        log.error("Authorization request failed: \(error.localizedDescription)")
                    }
                }
            }
            
            // Initial fetch so UI has fresh value before anchored updates
            if let steps = try? await self.fetchTodaySteps() {
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

        observerQuery = HKAnchoredObjectQuery(
            type: stepType,
            predicate: predicate,
            anchor: stepsAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, error in
            guard let self = self else { return }
            if let error = error {
                log.error("Anchored query error: \(error.localizedDescription)")
                return
            }
            self.stepsAnchor = newAnchor
            let added = samples?
                .compactMap { $0 as? HKQuantitySample }
                .reduce(0.0) { $0 + $1.quantity.doubleValue(for: .count()) } ?? 0
            if added > 0 {
                self.lastStepCount += added
            }
            Task { @MainActor in
                updateHandler(self.lastStepCount)
            }
        }

        if let query = observerQuery {
            store.execute(query)
            isObserving = true
            log.info("Step observation started (anchored)")
        }
    }

    private func logAuthorizationStatus(context: String) {
        if #available(iOS 12.0, *) {
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
        } else {
            log.debug("[\(context)] authorization status unavailable (iOS < 12)")
        }
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
