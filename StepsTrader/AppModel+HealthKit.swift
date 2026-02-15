import Foundation
import HealthKit

// MARK: - HealthKit & Steps Management
extension AppModel {
    func ensureHealthAuthorizationAndRefresh() async {
        // Delegate to HealthStore
        do {
            try await healthStore.requestAuthorization()
            AppLogger.healthKit.debug("✅ HealthKit authorization request completed")
        } catch {
            AppLogger.healthKit.debug("❌ HealthKit authorization failed: \(error.localizedDescription)")
        }
        
        // Try to fetch data regardless of status
        await refreshStepsBalance()
        await refreshSleepIfAuthorized()
        startStepObservation()
    }
    
    func fetchStepsForCurrentDay() async throws -> Double {
        return try await healthStore.fetchStepsForCurrentDay()
    }
    
    func refreshStepsBalance() async {
        await healthStore.refreshStepsIfAuthorized()
        
        // Update budget with new steps
        let budgetMinutes = budgetEngine.minutes(from: stepsToday)
        budgetEngine.setBudget(minutes: budgetMinutes)
        syncBudgetProperties()
        
        // Recalculate daily energy
        recalculateDailyEnergy()
    }
    
    func refreshStepsIfAuthorized() async {
        await refreshStepsBalance()
        await refreshSleepIfAuthorized()
    }
    
    func cacheStepsToday() {
        // Handled by HealthStore
    }
    
    func loadCachedStepsToday() {
        // Handled by HealthStore
    }
    
    func fallbackCachedSteps() -> Double {
        let g = UserDefaults.stepsTrader()
        let cached = g.double(forKey: "cachedStepsToday")
        if cached > 0 {
            AppLogger.healthKit.debug("💾 Falling back to cached steps: \(cached)")
            return cached
        }
        return 0
    }
    
    func startStepObservation() {
        healthStore.startObservingSteps()
    }
    
    func refreshSleepIfAuthorized() async {
        await healthStore.refreshSleepIfAuthorized()
        persistDailyEnergyState()
        recalculateDailyEnergy()
    }
}
