import Foundation
import HealthKit

// MARK: - HealthKit & Steps Management
extension AppModel {
    func ensureHealthAuthorizationAndRefresh() async {
        // Note: authorizationStatus() returns WRITE status, not READ status.
        // For read-only apps, we can't check if read is authorized - we just try to read.
        // Apple doesn't expose read authorization status for privacy reasons.
        
        let status = healthKitService.authorizationStatus()
        print("🏥 HealthKit status before ensure: \(status.rawValue) (note: this is WRITE status, not read)")
        healthAuthorizationStatus = status
        
        // Always request authorization (it's a no-op if already requested)
        // Then try to fetch data - if it works, read access is granted
        do {
            try await healthKitService.requestAuthorization()
            print("✅ HealthKit authorization request completed")
        } catch {
            print("❌ HealthKit authorization failed: \(error.localizedDescription)")
        }
        
        // Try to fetch data regardless of status - this is the only way to know if read works
        await refreshStepsBalance()
        await refreshSleepIfAuthorized()
        startStepObservation()
    }
    
    func fetchStepsForCurrentDay() async throws -> Double {
        let now = Date()
        let start = currentDayStart(for: now)
        return try await healthKitService.fetchSteps(from: start, to: now)
    }
    
    func fetchSleepForCurrentDay() async throws -> Double {
        let now = Date()
        let start = currentDayStart(for: now)
        return try await healthKitService.fetchSleep(from: start, to: now)
    }
    
    func refreshStepsBalance() async {
        // Don't check authorizationStatus - it shows WRITE status, not READ
        // Just try to fetch and handle errors gracefully
        do {
            stepsToday = try await fetchStepsForCurrentDay()
            print("✅ Refreshed steps: \(Int(stepsToday))")
            cacheStepsToday()
            
            // Update budget with new steps
            let budgetMinutes = budgetEngine.minutes(from: stepsToday)
            budgetEngine.setBudget(minutes: budgetMinutes)
            syncBudgetProperties()
            
            // Recalculate daily energy
            recalculateDailyEnergy()
        } catch {
            print("⚠️ Could not refresh steps: \(error)")
            loadCachedStepsToday()
        }
    }
    
    func refreshStepsIfAuthorized() async {
        // Just try to refresh - if read access isn't granted, it will fail gracefully
        await refreshStepsBalance()
        await refreshSleepIfAuthorized()
    }
    
    func cacheStepsToday() {
        let g = UserDefaults.stepsTrader()
        g.set(Int(stepsToday), forKey: "cachedStepsToday")
    }
    
    func loadCachedStepsToday() {
        let g = UserDefaults.stepsTrader()
        let cached = g.integer(forKey: "cachedStepsToday")
        if cached > 0 {
            stepsToday = Double(cached)
            print("💾 Loaded cached stepsToday: \(cached)")
        }
    }
    
    func fallbackCachedSteps() -> Double {
        let g = UserDefaults.stepsTrader()
        let cached = g.integer(forKey: "cachedStepsToday")
        if cached > 0 {
            print("💾 Falling back to cached steps: \(cached)")
            return Double(cached)
        }
        return 0
    }
    
    func startStepObservation() {
        healthKitService.startObservingSteps { [weak self] (_: Double) in
            Task { @MainActor in
                await self?.refreshStepsBalance()
                if let steps = self?.stepsToday {
                    print("📊 Auto-updated steps (custom day): \(Int(steps))")
                }
            }
        }
    }
    
    func refreshSleepIfAuthorized() async {
        // Just try to fetch - if read access isn't granted, it will fail gracefully
        do {
            let sleepHours = try await fetchSleepForCurrentDay()
            // AppModel is @MainActor, so we can update directly
            dailySleepHours = sleepHours
            persistDailyEnergyState()
            recalculateDailyEnergy()
            print("😴 Fetched sleep from HealthKit: \(String(format: "%.1f", sleepHours)) hours")
        } catch {
            print("⚠️ Could not fetch sleep from HealthKit: \(error.localizedDescription)")
        }
    }
}
