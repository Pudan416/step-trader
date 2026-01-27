import Foundation
import HealthKit

// MARK: - HealthKit & Steps Management
extension AppModel {
    func ensureHealthAuthorizationAndRefresh() async {
        let status = healthKitService.authorizationStatus()
        print("🏥 HealthKit status before ensure: \(status.rawValue)")
        healthAuthorizationStatus = status
        switch status {
        case .sharingAuthorized:
            print("🏥 HealthKit already authorized, refreshing steps")
        case .sharingDenied:
            print("❌ HealthKit access denied. Open the Health app → Sources → DOOM CTRL and enable step reading.")
            return
        case .notDetermined:
            print("🏥 HealthKit not determined. Requesting authorization...")
            do {
                try await healthKitService.requestAuthorization()
                print("✅ HealthKit authorization completed (ensureHealthAuthorizationAndRefresh)")
                healthAuthorizationStatus = healthKitService.authorizationStatus()
            } catch {
                print("❌ HealthKit authorization failed: \(error.localizedDescription)")
                return
            }
        @unknown default:
            print("❓ HealthKit status unknown: \(status.rawValue). Attempting authorization.")
            do {
                try await healthKitService.requestAuthorization()
            } catch {
                print("❌ HealthKit authorization failed: \(error.localizedDescription)")
                return
            }
        }
        await refreshStepsBalance()
        startStepObservation()
    }
    
    func fetchStepsForCurrentDay() async throws -> Double {
        let now = Date()
        let start = currentDayStart(for: now)
        return try await healthKitService.fetchSteps(from: start, to: now)
    }
    
    func refreshStepsBalance() async {
        let status = healthKitService.authorizationStatus()
        guard status == .sharingAuthorized else {
            print("ℹ️ HealthKit not authorized yet, skipping steps refresh")
            loadCachedStepsToday()
            return
        }
        
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
        let status = healthKitService.authorizationStatus()
        guard status == .sharingAuthorized else {
            print("ℹ️ HealthKit not authorized yet, skipping refresh")
            return
        }
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
        let status = healthKitService.authorizationStatus()
        guard status == .sharingAuthorized else {
            print("ℹ️ HealthKit not authorized yet, skipping sleep refresh")
            return
        }
        
        do {
            let sleepHours = try await healthKitService.fetchTodaySleep()
            // AppModel is @MainActor, so we can update directly
            dailySleepHours = sleepHours
            persistDailyEnergyState()
            recalculateDailyEnergy()
            print("😴 Fetched sleep from HealthKit: \(String(format: "%.1f", sleepHours)) hours")
        } catch {
            print("❌ Failed to refresh sleep from HealthKit: \(error.localizedDescription)")
        }
    }
}
