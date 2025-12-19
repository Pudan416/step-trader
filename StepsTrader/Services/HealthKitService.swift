import HealthKit

final class HealthKitService: HealthKitServiceProtocol {
    private let store = HKHealthStore()
    private let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
    private var observerQuery: HKObserverQuery?
    private var isObserving = false

    func requestAuthorization() async throws {
        logAuthorizationStatus(context: "requestAuthorization:pre-flight")
        try await store.requestAuthorization(toShare: [], read: [stepType])
        logAuthorizationStatus(context: "requestAuthorization:post-request")
        
        // Enable background delivery for automatic updates
        if #available(iOS 12.0, *) {
            try await store.enableBackgroundDelivery(for: stepType, frequency: .immediate)
            print("📡 HealthKit: background delivery for step count enabled")
        }
    }

    func fetchTodaySteps() async throws -> Double {
        // Ensure authorization is determined before querying
        if #available(iOS 12.0, *) {
            let status = store.authorizationStatus(for: stepType)
            if status == .notDetermined {
                try await requestAuthorization()
            }
        }

        let now = Date()
        let predicate = HKQuery.predicateForSamples(withStart: .startOfToday, end: now, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error = error {
                    // If the error is "No data available", return 0 instead of failing
                    let nsError = error as NSError
                    if nsError.code == 11 || // HKErrorCode 11 - no data available
                       nsError.localizedDescription.contains("No data available") {
                        print("📊 No step data available for today, returning 0")
                        continuation.resume(returning: 0)
                        return
                    }
                    print("❌ HealthKit error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }
                
                let steps = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
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

        observerQuery = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completionHandler, error in
            if let error = error {
                print("❌ HealthKit observer error: \(error.localizedDescription)")
                completionHandler()
                return
            }

            print("📊 HealthKit data changed, fetching updated steps")

            Task { @MainActor in
                do {
                    let steps = try await self?.fetchTodaySteps() ?? 0
                    updateHandler(steps)
                } catch {
                    print("❌ Failed to fetch updated steps: \(error)")
                }
                completionHandler()
            }
        }

        if let query = observerQuery {
            store.execute(query)
            isObserving = true
            print("✅ HealthKit step observation started")
        }
    }

    private func logAuthorizationStatus(context: String) {
        if #available(iOS 12.0, *) {
            let status = store.authorizationStatus(for: stepType)
            let statusDescription: String
            switch status {
            case .sharingAuthorized:
                statusDescription = "sharing authorized"
            case .sharingDenied:
                statusDescription = "sharing denied"
            case .notDetermined:
                statusDescription = "not determined"
            @unknown default:
                statusDescription = "unknown (\(status.rawValue))"
            }
            print("🏥 HealthKit [\(context)]: \(statusDescription)")
        } else {
            print("🏥 HealthKit [\(context)]: authorization status unavailable (iOS < 12)")
        }
    }
}
