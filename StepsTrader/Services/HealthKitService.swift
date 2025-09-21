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
                    continuation.resume(throwing: error)
                    return
                }
                let steps = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: steps)
            }
            store.execute(query)
        }
    }
}
