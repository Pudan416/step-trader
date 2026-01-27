import Foundation
import CoreLocation
import Combine
import UIKit

class OuterWorldLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var energyDrops: [EnergyDrop] = []
    @Published var collectedDrop: EnergyDrop?
    @Published var totalCollected: Int = 0
    @Published var collectedToday: Int = 0
    @Published var dailyCapReachedAt: Date?
    @Published var dailyCap: Int = 0
    @Published var magnetUsesToday: Int = 0
    @Published var magnetLimitReachedAt: Date?
    @Published var magnetNoDropsAt: Date?
    
    private let pickupRadius: CLLocationDistance = 50 // meters
    private let maxDropsOnScreen = 1
    private let dropLifetime: TimeInterval = 24 * 3600 // 24 hours
    private let dropEnergy: Int = 5
    private let spawnRadius: CLLocationDistance = 500 // meters
    private let maxMagnetUsesPerDay: Int = 3
    
    private let magnetDayKeyStorageKey = "outerworld_magnetDayKey_v1"
    private let magnetCountStorageKey = "outerworld_magnetCount_v1"
    private let capStorageKey = "outerworld_dailyCap_v1"
    private let collectedTodayDayKeyStorageKey = "outerworld_collectedDayKey_v1"
    private let collectedTodayStorageKey = "outerworld_collectedToday_v1"
    
    private var cleanupTimer: Timer?
    private var lastMagnetUse: Date?
    private var lastRegionProcess: Date?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
        loadDrops()
        loadTotalCollected()
        loadMagnetUsesToday()
        loadDailyCap()
        loadCollectedToday()
        startCleanupTimer()
    }
    
    var maxDropsPerDay: Int {
        max(0, dailyCap / dropEnergy)
    }
    
    var nextDropNumber: Int {
        // 1-based. If cap is reached, this number won't be used (no drop).
        let n = (collectedToday / dropEnergy) + 1
        return min(maxDropsPerDay, max(1, n))
    }
    
    func refreshEconomySnapshot() {
        loadDailyCap()
        loadCollectedToday()
        loadMagnetUsesToday()
        print("🔄 Outer World: Refreshed economy - cap=\(dailyCap), collectedToday=\(collectedToday), magnetsUsed=\(magnetUsesToday)")
    }
    
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startUpdating() {
        locationManager.startUpdatingLocation()
    }
    
    func stopUpdating() {
        locationManager.stopUpdatingLocation()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            startUpdating()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        userLocation = location.coordinate
        
        // Check for nearby drops to collect
        checkForPickups(at: location)
        
        // Normalize persisted drops and ensure exactly 1 drop within 500m (until daily cap is reached)
        normalizeDropsNearUser(currentLocation: location)
    }
    
    // MARK: - Drop Management
    
    private func checkForPickups(at location: CLLocation) {
        for drop in energyDrops {
            let dropLocation = CLLocation(latitude: drop.coordinate.latitude, longitude: drop.coordinate.longitude)
            let distance = location.distance(from: dropLocation)
            
            if distance <= pickupRadius {
                collectDrop(drop)
                break
            }
        }
    }
    
    private func collectDrop(_ drop: EnergyDrop) {
        guard consumeDailyCapIfPossible(amount: drop.energy) else {
            dailyCapReachedAt = Date()
            return
        }
        energyDrops.removeAll { $0.id == drop.id }
        collectedDrop = drop
        totalCollected += drop.energy
        collectedToday += drop.energy
        saveTotalCollected()
        saveCollectedToday()
        saveDrops()
        
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Post notification to add energy to balance
        NotificationCenter.default.post(
            name: NSNotification.Name("com.steps.trader.energy.collected"),
            object: nil,
            userInfo: ["energy": drop.energy]
        )
        
        // Sync stats to server
        Task { @MainActor in
            AuthenticationService.shared.syncStats()
        }
        
        // Spawn next drop after collecting the previous one (if possible)
        if let userLoc = userLocation {
            normalizeDropsNearUser(
                currentLocation: CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude)
            )
        }
    }

    func magnetPullNearbyDrops() {
        guard let coordinate = userLocation else { return }
        refreshMagnetDayIfNeeded()
        guard magnetUsesToday < maxMagnetUsesPerDay else {
            magnetLimitReachedAt = Date()
            return
        }
        
        let now = Date()
        if let lastUse = lastMagnetUse, now.timeIntervalSince(lastUse) < 10 {
            return
        }
        lastMagnetUse = now

        let currentLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let magnetRadius: CLLocationDistance = 500
        let nearbyDrops = energyDrops.filter { drop in
            let dropLocation = CLLocation(latitude: drop.coordinate.latitude, longitude: drop.coordinate.longitude)
            return currentLocation.distance(from: dropLocation) <= magnetRadius
        }
        guard !nearbyDrops.isEmpty else {
            magnetNoDropsAt = Date()
            return
        }

        // Pull ONLY 1 closest drop
        guard let closest = nearbyDrops.min(by: { a, b in
            let la = CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude)
            let lb = CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude)
            return currentLocation.distance(from: la) < currentLocation.distance(from: lb)
        }) else {
            magnetNoDropsAt = Date()
            return
        }

        let totalEnergy = closest.energy
        guard consumeDailyCapIfPossible(amount: totalEnergy) else {
            dailyCapReachedAt = Date()
            return
        }
        energyDrops.removeAll { $0.id == closest.id }
        totalCollected += totalEnergy
        collectedToday += totalEnergy
        saveTotalCollected()
        saveCollectedToday()
        saveDrops()
        
        magnetUsesToday += 1
        saveMagnetUsesToday()

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        collectedDrop = EnergyDrop(
            coordinate: coordinate,
            energy: totalEnergy,
            expiresAt: Date()
        )

        NotificationCenter.default.post(
            name: NSNotification.Name("com.steps.trader.energy.collected"),
            object: nil,
            userInfo: ["energy": totalEnergy]
        )
        
        // Sync stats to server
        Task { @MainActor in
            AuthenticationService.shared.syncStats()
        }
    }

    func magnetPull(drop: EnergyDrop) {
        guard let coordinate = userLocation else { return }
        refreshMagnetDayIfNeeded()
        guard magnetUsesToday < maxMagnetUsesPerDay else {
            magnetLimitReachedAt = Date()
            return
        }
        
        let now = Date()
        if let lastUse = lastMagnetUse, now.timeIntervalSince(lastUse) < 1.0 {
            return
        }
        lastMagnetUse = now
        
        let currentLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let dropLocation = CLLocation(latitude: drop.coordinate.latitude, longitude: drop.coordinate.longitude)
        let magnetRadius: CLLocationDistance = 500
        guard currentLocation.distance(from: dropLocation) <= magnetRadius else {
            magnetNoDropsAt = Date()
            return
        }
        
        guard consumeDailyCapIfPossible(amount: drop.energy) else {
            dailyCapReachedAt = Date()
            return
        }
        
        // If drop already gone, do nothing
        guard energyDrops.contains(where: { $0.id == drop.id }) else { return }
        
        energyDrops.removeAll { $0.id == drop.id }
        totalCollected += drop.energy
        collectedToday += drop.energy
        saveTotalCollected()
        saveCollectedToday()
        saveDrops()
        
        magnetUsesToday += 1
        saveMagnetUsesToday()
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        collectedDrop = EnergyDrop(
            coordinate: coordinate,
            energy: drop.energy,
            expiresAt: Date()
        )
        
        NotificationCenter.default.post(
            name: NSNotification.Name("com.steps.trader.energy.collected"),
            object: nil,
            userInfo: ["energy": drop.energy]
        )
        
        // Sync stats to server
        Task { @MainActor in
            AuthenticationService.shared.syncStats()
        }
        
        // Spawn next drop after collecting the previous one (if possible)
        if let userLoc = userLocation {
            normalizeDropsNearUser(
                currentLocation: CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude)
            )
        }
    }

    private func normalizeDropsNearUser(currentLocation: CLLocation) {
        refreshEconomySnapshot()
        cleanupExpiredDrops()
        
        // If daily cap reached, don't spawn.
        guard collectedToday + dropEnergy <= dailyCap else { return }
        
        // Keep only one drop, and it must be within 500m of the user.
        if !energyDrops.isEmpty {
            let userLoc = currentLocation
            
            // Pick the closest drop to user (if multiple were persisted)
            let closest = energyDrops.min { a, b in
                let la = CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude)
                let lb = CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude)
                return userLoc.distance(from: la) < userLoc.distance(from: lb)
            }
            
            if let closest {
                let closestLoc = CLLocation(latitude: closest.coordinate.latitude, longitude: closest.coordinate.longitude)
                let dist = userLoc.distance(from: closestLoc)
                
                // If it's within radius, keep exactly that one
                if dist <= spawnRadius {
                    if energyDrops.count != 1 || energyDrops.first?.id != closest.id {
                        energyDrops = [closest]
                        saveDrops()
                    }
                    return
                }
            }
            
            // Otherwise discard all old drops (they're not valid for current location)
            energyDrops.removeAll()
            saveDrops()
        }
        
        // Spawn one drop within 500m of user's current location.
        let center = currentLocation.coordinate
        let angle = Double.random(in: 0..<(2 * .pi))
        let distance = Double.random(in: max(80, pickupRadius + 10)...spawnRadius)
        
        let latOffset = (distance / 111_111) * cos(angle)
        let lonOffset = (distance / (111_111 * cos(center.latitude * .pi / 180))) * sin(angle)
        
        let coordinate = CLLocationCoordinate2D(
            latitude: center.latitude + latOffset,
            longitude: center.longitude + lonOffset
        )
        
        let drop = EnergyDrop(
            coordinate: coordinate,
            energy: dropEnergy,
            expiresAt: Date().addingTimeInterval(dropLifetime)
        )
        
        energyDrops = [drop]
        saveDrops()
    }
    
    private func cleanupExpiredDrops() {
        let before = energyDrops.count
        energyDrops.removeAll { $0.isExpired }
        if energyDrops.count != before {
            saveDrops()
        }
    }
    
    private func startCleanupTimer() {
        cleanupTimer?.invalidate()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.cleanupExpiredDrops()
            
            // Keep daily counters correct even if the app stays open across midnight.
            // This enforces that "collectedToday" (Outer World daily cap usage) resets at local day boundary.
            self.refreshCollectedTodayDayIfNeeded()
            self.refreshMagnetDayIfNeeded()
        }
    }
    
    // MARK: - Persistence
    
    private func saveDrops() {
        if let data = try? JSONEncoder().encode(energyDrops) {
            UserDefaults.standard.set(data, forKey: "outerworld_energydrops")
        }
    }
    
    private func loadDrops() {
        if let data = UserDefaults.standard.data(forKey: "outerworld_energydrops"),
           let drops = try? JSONDecoder().decode([EnergyDrop].self, from: data) {
        energyDrops = drops.filter { !$0.isExpired }
        }
    }
    
    private func saveTotalCollected() {
        UserDefaults.standard.set(totalCollected, forKey: "outerworld_totalcollected")
    }
    
    private func loadTotalCollected() {
        totalCollected = UserDefaults.standard.integer(forKey: "outerworld_totalcollected")
    }

    private func refreshCollectedTodayDayIfNeeded() {
        let today = dayKey(for: Date())
        let storedDay = UserDefaults.standard.string(forKey: collectedTodayDayKeyStorageKey)
        if storedDay != today {
            // New day - reset counter
            UserDefaults.standard.set(today, forKey: collectedTodayDayKeyStorageKey)
            UserDefaults.standard.set(0, forKey: collectedTodayStorageKey)
            UserDefaults.standard.synchronize()
            collectedToday = 0
            print("🔄 Outer World: New day detected, reset collectedToday to 0")
        }
    }
    
    private func loadCollectedToday() {
        refreshCollectedTodayDayIfNeeded()
        collectedToday = UserDefaults.standard.integer(forKey: collectedTodayStorageKey)
        print("📊 Outer World: Loaded collectedToday = \(collectedToday)")
    }

    private func saveCollectedToday() {
        UserDefaults.standard.set(collectedToday, forKey: collectedTodayStorageKey)
    }

    private func loadDailyCap() {
        dailyCap = UserDefaults.standard.integer(forKey: capStorageKey)
        if dailyCap <= 0 {
            dailyCap = 10_000 // spec default
        }
    }

    private func remainingDailyCap() -> Int {
        refreshEconomySnapshot()
        return max(0, dailyCap - collectedToday)
    }

    private func consumeDailyCapIfPossible(amount: Int) -> Bool {
        let remaining = remainingDailyCap()
        guard remaining >= amount else { return false }
        return true
    }
    
    private func refreshMagnetDayIfNeeded() {
        let today = dayKey(for: Date())
        let storedDay = UserDefaults.standard.string(forKey: magnetDayKeyStorageKey)
        if storedDay != today {
            UserDefaults.standard.set(today, forKey: magnetDayKeyStorageKey)
            magnetUsesToday = 0
            saveMagnetUsesToday()
        }
    }

    private func dayKey(for date: Date) -> String {
        // Local day key to avoid @MainActor isolation of AppModel.dayKey(for:)
        let cal = Calendar.current
        let hour = UserDefaults.standard.integer(forKey: "dayEndHour_v1")
        let minute = UserDefaults.standard.integer(forKey: "dayEndMinute_v1")
        let cutoff = cal.date(bySettingHour: hour, minute: minute, second: 0, of: date)
        let anchor: Date
        if let cutoff, date >= cutoff {
            anchor = cutoff
        } else if let cutoff, let prev = cal.date(byAdding: .day, value: -1, to: cutoff) {
            anchor = prev
        } else {
            anchor = cal.startOfDay(for: date)
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: anchor)
    }
    
    private func loadMagnetUsesToday() {
        refreshMagnetDayIfNeeded()
        magnetUsesToday = UserDefaults.standard.integer(forKey: magnetCountStorageKey)
    }
    
    private func saveMagnetUsesToday() {
        UserDefaults.standard.set(magnetUsesToday, forKey: magnetCountStorageKey)
    }
    
    // MARK: - Debug
    
    func spawnTestDrop() {
        guard let center = userLocation else { return }
        
        // Spawn very close for testing
        let latOffset = Double.random(in: -0.0003...0.0003)
        let lonOffset = Double.random(in: -0.0003...0.0003)
        
        let dropCoordinate = CLLocationCoordinate2D(
            latitude: center.latitude + latOffset,
            longitude: center.longitude + lonOffset
        )
        
        let energy = dropEnergy
        let expiresAt = Date().addingTimeInterval(dropLifetime)
        
        let drop = EnergyDrop(
            coordinate: dropCoordinate,
            energy: energy,
            expiresAt: expiresAt
        )
        
        energyDrops = [drop]
        saveDrops()
    }
    
}

