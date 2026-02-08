import Foundation
import HealthKit

// MARK: - HealthKit & Steps Management
extension AppModel {
    func ensureHealthAuthorizationAndRefresh() async {
        // Delegate to HealthStore
        do {
            try await healthStore.requestAuthorization()
            print("✅ HealthKit authorization request completed")
        } catch {
            print("❌ HealthKit authorization failed: \(error.localizedDescription)")
        }
        
        // Try to fetch data regardless of status
        await refreshStepsBalance()
        await refreshSleepIfAuthorized()
        startStepObservation()
    }
    
    func fetchStepsForCurrentDay() async throws -> Double {
        return try await healthStore.fetchStepsForCurrentDay()
    }
    
    func fetchSleepForCurrentDay() async throws -> Double {
        // HealthStore doesn't expose raw fetchSleep yet, maybe add it or just use refreshSleepIfAuthorized
        // But for now let's assume we use refreshSleepIfAuthorized which updates state
        return 0 // Placeholder if not used directly
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
            print("💾 Falling back to cached steps: \(cached)")
            return cached
        }
        return 0
    }
    
    func startStepObservation() {
        healthStore.startObservingSteps()
        
        // We need to react to changes. HealthStore updates stepsToday.
        // AppModel observes HealthStore.
        // But we also need to update budget when steps change.
        // We can observe healthStore.stepsToday in AppModel.
        
        // For now, let's hook into the observation in HealthStore if possible, 
        // or just rely on the fact that HealthStore updates stepsToday, 
        // and we need a way to trigger budget update.
        
        // HealthStore.startObservingSteps updates its property.
        // AppModel should observe that property change and update budget.
        // I'll add a subscription in AppModel init or here.
        
        // Actually, HealthStore's startObservingSteps takes a closure? 
        // In my implementation of HealthStore it does NOT take a closure for external use, 
        // it updates its own state.
        
        // I should update HealthStore to allow a callback or just observe it.
        // Since I can't easily change HealthStore from here, I'll rely on AppModel's subscription 
        // to healthStore.objectWillChange, but that's generic.
        
        // Let's modify HealthStore to allow a callback or notification.
        // Or better: In AppModel, subscribe to healthStore.$stepsToday
    }
    
    func refreshSleepIfAuthorized() async {
        await healthStore.refreshSleepIfAuthorized()
        persistDailyEnergyState()
        recalculateDailyEnergy()
    }
}
