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
        guard healthKitService.authorizationStatus() == .sharingAuthorized else { return }
        do {
            stepsToday = try await fetchStepsForCurrentDay()
            cacheStepsToday()
        } catch {
            print("⚠️ Failed to refresh steps: \(error)")
            loadCachedStepsToday()
        }
    }
    
    func refreshSleepIfAuthorized() async {
        let status = healthKitService.sleepAuthorizationStatus()
        print("🛌 HealthKit sleep write-status: \(status.rawValue)")
        // authorizationStatus reports WRITE permission. Read access can still be allowed when status is denied.
        do {
            let now = Date()
            let start = currentDayStart(for: now)
            dailySleepHours = try await healthKitService.fetchSleep(from: start, to: now)
            print("🛌 Fetched sleep hours: \(String(format: "%.2f", dailySleepHours))h")
        } catch {
            print("⚠️ Failed to refresh sleep: \(error)")
        }
    }
    
    // MARK: - Helpers
    private func currentDayStart(for date: Date) -> Date {
        let g = UserDefaults.stepsTrader()
        let s = UserDefaults.standard
        
        let hour = (g.object(forKey: "dayEndHour_v1") as? Int)
            ?? (s.object(forKey: "dayEndHour_v1") as? Int)
            ?? 0
            
        let minute = (g.object(forKey: "dayEndMinute_v1") as? Int)
            ?? (s.object(forKey: "dayEndMinute_v1") as? Int)
            ?? 0
            
        return DayBoundary.currentDayStart(for: date, dayEndHour: hour, dayEndMinute: minute)
    }
    
    // MARK: - Caching
    private func cacheStepsToday() {
        let g = UserDefaults.stepsTrader()
        g.set(stepsToday, forKey: "cachedStepsToday")
    }
    
    private func loadCachedStepsToday() {
        let g = UserDefaults.stepsTrader()
        stepsToday = g.double(forKey: "cachedStepsToday")
    }
    
    // MARK: - Observation
    func startObservingSteps() {
        healthKitService.startObservingSteps { [weak self] (steps: Double) in
            Task { @MainActor [weak self] in
                self?.stepsToday = steps
                self?.cacheStepsToday()
            }
        }
    }
    
    func stopObservingSteps() {
        healthKitService.stopObservingSteps()
    }
}
