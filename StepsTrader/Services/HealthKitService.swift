import HealthKit

final class HealthKitService: HealthKitServiceProtocol {
    private let store = HKHealthStore()
    private let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: [stepType])
    }

    func fetchTodaySteps() async throws -> Double {
        let now = Date()
        let predicate = HKQuery.predicateForSamples(withStart: .startOfToday, end: now, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error = error {
                    // Если ошибка "No data available", возвращаем 0 вместо ошибки
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
                continuation.resume(returning: steps)
            }
            store.execute(query)
        }
    }
}
