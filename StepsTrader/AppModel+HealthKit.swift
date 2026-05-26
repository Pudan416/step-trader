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

    #if DEBUG
    /// Simulates a new-day boundary: resets all daily state, clears caches,
    /// restarts the observer, and re-fetches fresh data from HealthKit.
    func debugForceHealthReset() async {
        AppLogger.healthKit.debug("🔧 DEBUG: forcing day-boundary health reset")

        // 1. Stop observer (stale predicate)
        healthStore.stopObservingSteps()

        // 2. Clear in-memory HealthKit cache so stale values aren't returned on error
        healthStore.clearCachedStepCount()

        // 3. Zero out all health state + UserDefaults caches
        stepsToday = 0
        dailySleepHours = 0
        healthStore.hasStepsData = false
        healthStore.hasSleepData = false
        let g = UserDefaults.stepsTrader()
        g.removeObject(forKey: SharedKeys.cachedStepsToday)
        g.set(false, forKey: SharedKeys.hasStepsData)
        g.removeObject(forKey: "cachedSleepHoursToday")

        // 4. Reset energy anchor to current day start so the system thinks it's a fresh day
        let newAnchor = currentDayStart(for: Date.now)
        g.set(newAnchor, forKey: "dailyEnergyAnchor_v1")
        AppLogger.healthKit.debug("🔧 DEBUG: new anchor = \(newAnchor)")

        // 5. Re-fetch from HealthKit and rebuild everything
        await refreshStepsIfAuthorized()
    }
    #endif
}
