import Foundation
import HealthKit

// MARK: - HealthKit & Steps Management
extension AppModel {
    func ensureHealthAuthorizationAndRefresh() async {
        do {
            try await healthStore.requestAuthorization()
            AppLogger.healthKit.debug("✅ HealthKit authorization request completed")
        } catch {
            AppLogger.healthKit.debug("❌ HealthKit authorization failed: \(error.localizedDescription)")
        }
        
        await refreshStepsIfAuthorized()
    }


    /// Fetches steps only and updates the budget. Does NOT recalculate energy.
    func refreshStepsBalance() async {
        await healthStore.refreshStepsIfAuthorized()
        
        let budgetMinutes = budgetEngine.minutes(from: stepsToday)
        budgetEngine.setBudget(minutes: budgetMinutes)
    }
    
    /// Fetches sleep only. Does NOT recalculate energy.
    func refreshSleepIfAuthorized() async {
        await healthStore.refreshSleepIfAuthorized()
    }
    
    /// Main refresh entry point — fetches steps + sleep, then recalculates once.
    func refreshStepsIfAuthorized() async {
        await refreshStepsBalance()
        await refreshSleepIfAuthorized()
        
        recalculateDailyEnergy()
        persistDailyEnergyState()
        startStepObservation()
    }
    
    func fallbackCachedSteps() -> Double {
        let g = UserDefaults.stepsTrader()
        let cached = g.double(forKey: SharedKeys.cachedStepsToday)
        if cached > 0 {
            AppLogger.healthKit.debug("💾 Falling back to cached steps: \(cached)")
            return cached
        }
        return 0
    }
    
    func startStepObservation() {
        healthStore.startObservingSteps()
    }
}
