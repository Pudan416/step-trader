import HealthKit

@preconcurrency
final class HealthKitService: HealthKitServiceProtocol {
    private let store = HKHealthStore()
    private let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
    private let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    private var observerQuery: HKQuery?
    private var isObserving = false
    private var stepsAnchor: HKQueryAnchor?
    private var lastStepCount: Double = 0
    private var isRequestingAuthorization = false
    private var authTimeoutTask: Task<Void, Never>?

    @MainActor
    func authorizationStatus() -> HKAuthorizationStatus {
        // Возвращаем статус для шагов (основной тип)
        // Для сна проверяем отдельно, если нужно
        store.authorizationStatus(for: stepType)
    }

    @MainActor
    func requestAuthorization() async throws {
        if isRequestingAuthorization {
            print("🏥 HealthKit authorization already in-flight, skipping duplicate call")
            return
        }
        isRequestingAuthorization = true
        defer { isRequestingAuthorization = false }

        print("🏥 HealthKit requestAuthorization started on main actor")
        logHealthKitEntitlement()
        logEmbeddedProfileHealthKit()
        print("🏥 isHealthDataAvailable: \(HKHealthStore.isHealthDataAvailable())")
        guard HKHealthStore.isHealthDataAvailable() else {
            print("🚫 HealthKit is not available on this device/configuration.")
            return
        }
        let readTypes: Set<HKObjectType> = [stepType, sleepType]
        if #available(iOS 15.0, *) {
            let status = try await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
            print("🏥 HealthKit request status: \(status.rawValue)")
        }
        logAuthorizationStatus(context: "requestAuthorization:pre-flight")
        // Watchdog in case completion never fires
        authTimeoutTask?.cancel()
        authTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if self.isRequestingAuthorization {
                print("⚠️ HealthKit requestAuthorization appears stalled (no completion in 5s). Resetting flag.")
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
        print("🏥 HealthKit requestAuthorization returned: \(granted)")
        logAuthorizationStatus(context: "requestAuthorization:post-request")
        authTimeoutTask?.cancel()
        
        // Enable background delivery for automatic updates
        if #available(iOS 12.0, *) {
            try await store.enableBackgroundDelivery(for: stepType, frequency: .immediate)
            print("📡 HealthKit: background delivery for step count enabled")
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
        // Ensure authorization is determined before querying
        if #available(iOS 12.0, *) {
            let status = store.authorizationStatus(for: sleepType)
            if status == .notDetermined {
                try await requestAuthorization()
            }
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
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
                
                // Суммируем все интервалы сна
                var totalSleepHours: Double = 0
                if let samples = samples as? [HKCategorySample] {
                    for sample in samples {
                        // Учитываем все типы сна: asleep, inBed, awake
                        // Обычно учитываем только asleep для точности, но можно включить и inBed
                        let sleepValue = sample.value
                        var shouldCount = false
                        
                        if #available(iOS 16.0, *) {
                            // Учитываем все типы сна в iOS 16+
                            shouldCount = sleepValue == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                                         sleepValue == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                                         sleepValue == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                                         sleepValue == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                                         sleepValue == HKCategoryValueSleepAnalysis.inBed.rawValue
                        } else {
                            // Fallback для iOS < 16
                            shouldCount = sleepValue == HKCategoryValueSleepAnalysis.asleep.rawValue ||
                                         sleepValue == HKCategoryValueSleepAnalysis.inBed.rawValue
                        }
                        
                        if shouldCount {
                            let duration = sample.endDate.timeIntervalSince(sample.startDate)
                            totalSleepHours += duration / 3600.0 // Конвертируем секунды в часы
                        }
                    }
                }
                
                continuation.resume(returning: totalSleepHours)
            }
            store.execute(query)
        }
    }
    
    func fetchSteps(from start: Date, to end: Date) async throws -> Double {
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
                        print("📊 No step data available for today, returning cached")
                        continuation.resume(returning: self.lastStepCount)
                        return
                    }
                    print("❌ HealthKit error: \(error.localizedDescription)")
                    if self.lastStepCount > 0 {
                        continuation.resume(returning: self.lastStepCount)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                
                let steps = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                self.lastStepCount = steps
                print("📊 Fetched \(Int(steps)) steps for today")
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

        if #available(iOS 12.0, *) {
            let status = store.authorizationStatus(for: stepType)
            switch status {
            case .notDetermined:
                print("⚠️ HealthKit authorization not determined. Requesting before observing.")
                Task { [weak self] in
                    do {
                        try await self?.requestAuthorization()
                        await self?.beginObservation(updateHandler: updateHandler)
                    } catch {
                        print("❌ HealthKit authorization request failed: \(error)")
                    }
                }
                return
            case .sharingDenied:
                print("❌ HealthKit authorization denied. Observation not started.")
                return
            default:
                break
            }
        }

        Task { [weak self] in
            // Initial fetch so UI has fresh value before anchored updates
            if let steps = try? await self?.fetchTodaySteps() {
                await MainActor.run { updateHandler(steps) }
            }
            await self?.beginObservation(updateHandler: updateHandler)
        }
    }

    func stopObservingSteps() {
        guard let query = observerQuery else { return }
        
        store.stop(query)
        observerQuery = nil
        isObserving = false
        print("🛑 HealthKit step observation stopped")
    }

    @MainActor
    private func beginObservation(updateHandler: @escaping (Double) -> Void) async {
        guard !isObserving else { return }

        print("🔄 Starting HealthKit step observation")

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
                print("❌ HealthKit anchored query error: \(error.localizedDescription)")
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
            print("✅ HealthKit step observation started (anchored)")
        }
    }

    private func logAuthorizationStatus(context: String) {
        if #available(iOS 12.0, *) {
            let stepStatus = store.authorizationStatus(for: stepType)
            let sleepStatus = store.authorizationStatus(for: sleepType)
            let stepStatusDescription: String
            let sleepStatusDescription: String
            
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
            
            print("🏥 HealthKit [\(context)]: steps=\(stepStatusDescription), sleep=\(sleepStatusDescription)")
        } else {
            print("🏥 HealthKit [\(context)]: authorization status unavailable (iOS < 12)")
        }
    }

    private func logHealthKitEntitlement() {
        // SecTask* APIs can be unavailable in some build configs; skip detailed entitlement check.
        print("🏥 Entitlement check skipped (SecTask APIs unavailable in this build)")
    }

    private func logEmbeddedProfileHealthKit() {
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let content = String(data: data, encoding: .ascii) else {
            print("🏥 embedded.mobileprovision not found or unreadable")
            return
        }
        let hasHealthKit = content.contains("com.apple.developer.healthkit")
        let hasBackground = content.contains("com.apple.developer.healthkit.background-delivery")
        print("🏥 Provision profile contains healthkit: \(hasHealthKit), background: \(hasBackground)")
    }
}
