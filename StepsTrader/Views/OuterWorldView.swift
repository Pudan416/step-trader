import SwiftUI
import MapKit
import CoreLocation
import UIKit

// MARK: - Energy Drop Model
struct EnergyDrop: Identifiable, Codable, Equatable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let energy: Int
    let expiresAt: Date
    let spawnedAt: Date
    
    var isExpired: Bool {
        Date() > expiresAt
    }
    
    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, energy, expiresAt, spawnedAt
    }
    
    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, energy: Int, expiresAt: Date, spawnedAt: Date = Date()) {
        self.id = id
        self.coordinate = coordinate
        self.energy = energy
        self.expiresAt = expiresAt
        self.spawnedAt = spawnedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let lat = try container.decode(Double.self, forKey: .latitude)
        let lon = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        energy = try container.decode(Int.self, forKey: .energy)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        spawnedAt = try container.decode(Date.self, forKey: .spawnedAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encode(energy, forKey: .energy)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encode(spawnedAt, forKey: .spawnedAt)
    }
    
    static func == (lhs: EnergyDrop, rhs: EnergyDrop) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Location Manager
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
    private let dropEnergy: Int = 500
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
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
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

// MARK: - Outer World View

// MARK: - Supabase Config (for leaderboard)
private struct SupabaseConfig {
    let baseURL: URL
    let apiKey: String
    
    static func load() throws -> SupabaseConfig {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              let url = URL(string: urlString),
              !anonKey.isEmpty
        else {
            throw NSError(domain: "Supabase", code: 1, userInfo: [NSLocalizedDescriptionKey: "Supabase not configured"])
        }
        return SupabaseConfig(baseURL: url, apiKey: anonKey)
    }
}

// MARK: - Leaderboard Entry
struct LeaderboardEntry: Identifiable, Codable {
    let id: String
    let nickname: String?
    let energySpentLifetime: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case nickname
        case energySpentLifetime = "energy_spent_lifetime"
    }
}

struct OuterWorldView: View {
    @ObservedObject var model: AppModel
    @StateObject private var locationManager = OuterWorldLocationManager()
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showCollectedAlert = false
    @State private var showPermissionAlert = false
    @State private var mapRegion = MKCoordinateRegion()
    @State private var showMagnetLimitToast = false
    @State private var showMagnetNoDropsToast = false
    @State private var showDailyCapToast = false
    @State private var selectedDrop: EnergyDrop?
    @State private var selectedDropForAction: EnergyDrop?
    @State private var showMechanicInfo: Bool = false
    @State private var showLeaderboard: Bool = false
    @State private var leaderboardEntries: [LeaderboardEntry] = []
    @State private var isLoadingLeaderboard: Bool = false
    
    var body: some View {
        ZStack {
            // Map
            mapView
            
            // Overlay UI
            VStack {
                headerOverlay
                Spacer()
            }
                
            // Floating controls (bottom-right)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Button {
                            recenterToUser()
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 46, height: 46)
                                .background(Circle().fill(.ultraThinMaterial))
                                .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 6)
                        }
                        .buttonStyle(.plain)
                        .disabled(locationManager.userLocation == nil)
                        
                        Button {
                            showMechanicInfo = true
                        } label: {
                            Image(systemName: "info.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 46, height: 46)
                                .background(Circle().fill(.ultraThinMaterial))
                                .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 6)
                        }
                        .buttonStyle(.plain)
                        
                        // Leaderboard button
                        Button {
                            showLeaderboard = true
                            loadLeaderboard()
                        } label: {
                            Image(systemName: "trophy.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.yellow)
                                .frame(width: 46, height: 46)
                                .background(Circle().fill(.ultraThinMaterial))
                                .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 110)
                }
            }
            
            // Collected energy popup
            if let drop = locationManager.collectedDrop {
                collectedPopup(drop: drop)
            }
            
            if showMagnetLimitToast {
                toast(text: loc(appLanguage, "Magnet limit reached (3/day)", "Лимит магнита (3/день)"))
            } else if showMagnetNoDropsToast {
                toast(text: loc(appLanguage, "No drops within 500m", "Нет капель в радиусе 500м"))
            } else if showDailyCapToast {
                toast(text: loc(appLanguage, "Outer World cap reached for today", "Лимит Outer World на сегодня исчерпан"))
            }
            
            if let drop = selectedDrop {
                dropInfoToast(drop: drop)
            }
        }
        .sheet(isPresented: $showMechanicInfo) {
            mechanicInfoSheet
        }
        .sheet(isPresented: $showLeaderboard) {
            leaderboardSheet
        }
        .onAppear {
            checkLocationPermission()
            // Force refresh to catch midnight reset
            DispatchQueue.main.async {
                locationManager.refreshEconomySnapshot()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Ensure daily counters (10k/day cap + magnets/day) reset after midnight even if the app was backgrounded.
            DispatchQueue.main.async {
                locationManager.refreshEconomySnapshot()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            // Fires around midnight / time changes. Re-check daily boundary.
            locationManager.refreshEconomySnapshot()
        }
        .onChange(of: model.stepsToday) { _, _ in
            // Daily cap depends on HealthKit steps; AppModel persists it into defaults.
            locationManager.refreshEconomySnapshot()
        }
        .onReceive(locationManager.$collectedDrop) { drop in
            if drop != nil {
                showCollectedAlert = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    locationManager.collectedDrop = nil
                }
            }
        }
        .onReceive(locationManager.$magnetLimitReachedAt) { date in
            guard date != nil else { return }
            showMagnetLimitToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                showMagnetLimitToast = false
            }
        }
        .onReceive(locationManager.$magnetNoDropsAt) { date in
            guard date != nil else { return }
            showMagnetNoDropsToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                showMagnetNoDropsToast = false
            }
        }
        .onReceive(locationManager.$dailyCapReachedAt) { date in
            guard date != nil else { return }
            showDailyCapToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                showDailyCapToast = false
            }
        }
        .confirmationDialog(
            loc(appLanguage, "Energy Drop", "Капля энергии"),
            isPresented: .init(
                get: { selectedDropForAction != nil },
                set: { if !$0 { selectedDropForAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(loc(appLanguage, "Build walking route", "Построить маршрут пешком")) {
                if let drop = selectedDropForAction {
                    openWalkingRoute(to: drop.coordinate)
                }
                selectedDropForAction = nil
            }
            
            let magnetsLeft = max(0, 3 - locationManager.magnetUsesToday)
            Button(loc(appLanguage, "Use magnet (\(magnetsLeft) left)", "Притянуть магнитом (осталось \(magnetsLeft))")) {
                if let drop = selectedDropForAction {
                    if locationManager.userLocation == nil {
                        showPermissionAlert = true
                    } else if locationManager.magnetUsesToday >= 3 {
                        locationManager.magnetLimitReachedAt = Date()
                    } else {
                        locationManager.magnetPull(drop: drop)
                    }
                }
                selectedDropForAction = nil
            }
            
            Button(loc(appLanguage, "Cancel", "Отмена"), role: .cancel) {
                selectedDropForAction = nil
            }
        } message: {
            if let drop = selectedDropForAction {
                Text(loc(appLanguage, "This drop contains \(formatNumber(drop.energy)) energy.", "В этой капле \(formatNumber(drop.energy)) энергии."))
            }
        }
        .alert(loc(appLanguage, "Location Required", "Требуется геолокация"), isPresented: $showPermissionAlert) {
            Button(loc(appLanguage, "Settings", "Настройки")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(loc(appLanguage, "Cancel", "Отмена"), role: .cancel) {}
        } message: {
            Text(loc(appLanguage, "Enable location access to explore the Outer World and collect energy drops", "Включите доступ к геолокации для исследования Внешнего мира и сбора энергии"))
        }
    }
    
    // MARK: - Map View
    
    private var mapView: some View {
        Map(position: $cameraPosition) {
            // User location
            UserAnnotation()

            // Magnet working radius (500m)
            if let userLoc = locationManager.userLocation {
                MapCircle(center: userLoc, radius: 500)
                    .foregroundStyle(Color.blue.opacity(0.10))
                    .stroke(Color.blue.opacity(0.35), lineWidth: 2)
            }
            
            // Energy drops
            ForEach(locationManager.energyDrops) { drop in
                Annotation("", coordinate: drop.coordinate) {
                    Button {
                        // Tap = show actions (route / magnet)
                        selectedDropForAction = drop
                        selectedDrop = drop
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            if selectedDrop?.id == drop.id { selectedDrop = nil }
                        }
                    } label: {
                        EnergyDropMarker(
                            drop: drop,
                            userLocation: locationManager.userLocation,
                            dropNumber: locationManager.nextDropNumber,
                            maxDropsPerDay: locationManager.maxDropsPerDay
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .top)
    }
    
    // MARK: - Header Overlay
    
    // MARK: - Motivational Text
    private var motivationalText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        
        // Night phrases (22:00-06:00) - night walks + magnets
        let nightPhrasesEN = [
            "🌙 Night walks hit different. Try it",
            "🧲 3 magnets on the map. Grab batteries without moving",
            "😴 Can't sleep? Night stroll = night scroll",
            "🌃 City's quiet. Perfect time to hunt",
            "⏰ Midnight brings new magnets. Use wisely"
        ]
        let nightPhrasesRU = [
            "🌙 Ночные прогулки — это другой вайб",
            "🧲 3 магнита на карте. Хватай не вставая",
            "😴 Не спится? Прогулка = халявный скролл",
            "🌃 Город спит. Идеальное время для охоты",
            "⏰ В полночь новые магниты. Используй с умом"
        ]
        
        // Morning phrases (06:00-12:00) - motivation to walk
        let morningPhrasesEN = [
            "🌿 Touch grass before you touch apps",
            "🚶 Your legs work. Use them",
            "📱 No steps = no scroll. Simple math",
            "☀️ Get yourself outside first",
            "👑 Earn your screen time, legend"
        ]
        let morningPhrasesRU = [
            "🌿 Сначала ноги, потом пальцы",
            "🚶 Шаги сами себя не нашагают",
            "📱 Без шагов нет скролла. Такие правила",
            "☀️ Выйди на улицу, чемпион",
            "👑 Заработай экранку, легенда"
        ]
        
        // Afternoon phrases (12:00-17:00) - balance walk + scroll
        let afternoonPhrasesEN = [
            "⚖️ Walk a bit, scroll a bit. Balance",
            "🎯 Doomscroll earned, not given",
            "🌿 Touched grass? Good. Now chill",
            "⚡ Energy's stacking. Keep it up",
            "🕐 Half day done. Spend wisely"
        ]
        let afternoonPhrasesRU = [
            "⚖️ Погулял — поскроллил. Баланс",
            "🎯 Думскролл надо заслужить",
            "🌿 Трава потрогана? Теперь чиллим",
            "⚡ Энергия копится. Продолжай",
            "🕐 Полдня позади. Трать с умом"
        ]
        
        // Evening phrases (17:00-22:00) - wind down, spend energy
        let eveningPhrasesEN = [
            "🔥 Energy expires at midnight. Use it",
            "😌 Wind down time. Burn that energy",
            "🛋️ Evening mode: scroll guilt-free",
            "✨ You walked. You earned. Now scroll",
            "⏳ Clock's ticking. Spend before reset"
        ]
        let eveningPhrasesRU = [
            "🔥 В полночь энергия сгорит. Трать",
            "😌 Время расслабиться и сжечь энергию",
            "🛋️ Вечерний режим: скролль спокойно",
            "✨ Ты ходил. Ты заработал. Отдыхай",
            "⏳ Часики тикают. Потрать до сброса"
        ]
        
        let phrasesEN: [String]
        let phrasesRU: [String]
        
        if hour < 6 || hour >= 22 {
            phrasesEN = nightPhrasesEN
            phrasesRU = nightPhrasesRU
        } else if hour < 12 {
            phrasesEN = morningPhrasesEN
            phrasesRU = morningPhrasesRU
        } else if hour < 17 {
            phrasesEN = afternoonPhrasesEN
            phrasesRU = afternoonPhrasesRU
        } else {
            phrasesEN = eveningPhrasesEN
            phrasesRU = eveningPhrasesRU
        }
        
        let index = dayOfYear % phrasesEN.count
        return loc(appLanguage, phrasesEN[index], phrasesRU[index])
    }
    
    private var headerOverlay: some View {
        let pink = Color(red: 224/255, green: 130/255, blue: 217/255)
        let cap = max(1, locationManager.dailyCap)
        let used = min(cap, max(0, locationManager.collectedToday))
        let magnetsLeft = max(0, 3 - locationManager.magnetUsesToday)
        
        return VStack(spacing: 0) {
            Color.clear.frame(height: 0)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    // Title
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc(appLanguage, "Outer World", "Внешний мир"))
                            .font(.headline)
                        Text(loc(appLanguage, "Touch grass, get fuel ⚡️", "На прогулку за топливом ⚡️"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                
                Spacer()
                
                // Stats pills
                HStack(spacing: 6) {
                    // Progress pill
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                            .foregroundColor(pink)
                        Text("\(formatNumber(used))/\(formatNumber(cap))")
                            .font(.caption2.weight(.semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.ultraThinMaterial))
                    
                    // Magnets pill
                    HStack(spacing: 4) {
                        Image(systemName: "dot.radiowaves.up.forward")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text("\(magnetsLeft)")
                            .font(.caption2.weight(.semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.ultraThinMaterial))
                }
            }
            
            // Motivational text
            Text(motivationalText)
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.85))
                .italic()
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(
                LinearGradient(
                    colors: [Color(.systemBackground).opacity(0.95), Color(.systemBackground).opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
    
    private var mechanicInfoSheet: some View {
        let pink = Color(red: 224/255, green: 130/255, blue: 217/255)
        let cap = max(1, locationManager.dailyCap)
        let used = min(cap, max(0, locationManager.collectedToday))
        let magnetsLeft = max(0, 3 - locationManager.magnetUsesToday)
        
        return NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Hero - edgy
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [pink.opacity(0.3), Color.purple.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)
                            
                            Image(systemName: "battery.100.bolt")
                                .font(.subheadline.bold())
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.yellow, .orange],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc(appLanguage, "Fuel Hunt", "Охота за топливом"))
                                .font(.headline)
                            Text(loc(appLanguage, "Walk → Collect → Dominate 🏆", "Гуляй → Собирай → Властвуй 🏆"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Today card - glass
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(loc(appLanguage, "Today's haul", "Сегодняшний улов"))
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text("\(formatNumber(used)) / \(formatNumber(cap))")
                                .font(.caption.weight(.bold))
                                .foregroundColor(pink)
                        }
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.gray.opacity(0.15))
                                    .frame(height: 6)
                                Capsule()
                                    .fill(
                                        LinearGradient(colors: [pink, .purple], startPoint: .leading, endPoint: .trailing)
                                    )
                                    .frame(width: geo.size.width * CGFloat(Double(used) / Double(cap)), height: 6)
                            }
                        }
                        .frame(height: 6)
                        
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "battery.100.bolt")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Text("+500")
                                    .font(.caption2.weight(.semibold))
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Image(systemName: "dot.radiowaves.up.forward")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                Text("\(magnetsLeft)/3")
                                    .font(.caption2.weight(.semibold))
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                    )
                    
                    // Rules - edgy
                    VStack(alignment: .leading, spacing: 10) {
                        Text(loc(appLanguage, "The Rules", "Правила игры"))
                            .font(.caption.weight(.bold))
                        
                        ruleRowEdgy(
                            icon: "scope",
                            color: .blue,
                            text: loc(appLanguage, "One battery spawns within 500m", "Одна батарейка в радиусе 500м")
                        )
                        
                        ruleRowEdgy(
                            icon: "figure.walk",
                            color: .green,
                            text: loc(appLanguage, "Walk 50m to grab it", "Подойди на 50м чтобы забрать")
                        )
                        
                        ruleRowEdgy(
                            icon: "dot.radiowaves.up.forward",
                            color: .purple,
                            text: loc(appLanguage, "Lazy? Use a magnet (3/day)", "Лень? Притяни магнитом (3/день)")
                        )
                        
                        ruleRowEdgy(
                            icon: "moon.fill",
                            color: .indigo,
                            text: loc(appLanguage, "Night walks = extra chill vibes", "Ночные прогулки = особые вайбы")
                        )
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                    )
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(loc(appLanguage, "Outer World", "Внешний мир"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc(appLanguage, "Close", "Закрыть")) {
                        showMechanicInfo = false
                    }
                }
            }
        }
    }
    
    // MARK: - Leaderboard Sheet
    private var leaderboardSheet: some View {
        NavigationView {
            Group {
                if isLoadingLeaderboard {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(loc(appLanguage, "Loading legends...", "Загружаем легенды..."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if leaderboardEntries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "trophy")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(loc(appLanguage, "No one here yet", "Пока никого"))
                            .font(.headline)
                        Text(loc(appLanguage, "Be the first to dominate!", "Будь первым, кто захватит мир!"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(Array(leaderboardEntries.enumerated()), id: \.element.id) { index, entry in
                                leaderboardRow(rank: index + 1, entry: entry)
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(loc(appLanguage, "🏆 Leaderboard", "🏆 Рейтинг"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc(appLanguage, "Close", "Закрыть")) {
                        showLeaderboard = false
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        loadLeaderboard()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }
    
    private func leaderboardRow(rank: Int, entry: LeaderboardEntry) -> some View {
        let isCurrentUser = entry.id == AuthenticationService.shared.currentUser?.id
        let rankColor: Color = {
            switch rank {
            case 1: return .yellow
            case 2: return .gray
            case 3: return Color(red: 205/255, green: 127/255, blue: 50/255) // bronze
            default: return .secondary
            }
        }()
        
        return HStack(spacing: 12) {
            // Rank
            ZStack {
                if rank <= 3 {
                    Circle()
                        .fill(rankColor.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Text("\(rank)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(rankColor)
                } else {
                    Text("\(rank)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                        .frame(width: 32)
                }
            }
            
            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.nickname ?? loc(appLanguage, "Anonymous", "Аноним"))
                    .font(.subheadline.weight(isCurrentUser ? .bold : .medium))
                    .foregroundColor(isCurrentUser ? .accentColor : .primary)
                if isCurrentUser {
                    Text(loc(appLanguage, "You", "Ты"))
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
            }
            
            Spacer()
            
            // Energy spent
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text(formatNumber(entry.energySpentLifetime))
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            if isCurrentUser {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentColor.opacity(0.12))
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
            }
        }
    }
    
    private func loadLeaderboard() {
        isLoadingLeaderboard = true
        
        Task {
            do {
                let cfg = try SupabaseConfig.load()
                let usersURL = cfg.baseURL.appendingPathComponent("rest/v1/users")
                var comps = URLComponents(url: usersURL, resolvingAgainstBaseURL: false)!
                comps.queryItems = [
                    URLQueryItem(name: "select", value: "id,nickname,energy_spent_lifetime"),
                    URLQueryItem(name: "order", value: "energy_spent_lifetime.desc"),
                    URLQueryItem(name: "limit", value: "50")
                ]
                
                var request = URLRequest(url: comps.url!)
                request.setValue(cfg.apiKey, forHTTPHeaderField: "apikey")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                
                // Add auth token if user is logged in (required for RLS)
                if let token = AuthenticationService.shared.accessToken {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                
                print("🏆 Leaderboard request: \(comps.url?.absoluteString ?? "nil")")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let bodyStr = String(data: data, encoding: .utf8) {
                    print("🏆 Leaderboard response: \(bodyStr.prefix(500))")
                }
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    print("❌ Leaderboard fetch failed: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    await MainActor.run {
                        isLoadingLeaderboard = false
                    }
                    return
                }
                
                let entries = try JSONDecoder().decode([LeaderboardEntry].self, from: data)
                print("🏆 Leaderboard loaded: \(entries.count) users")
                await MainActor.run {
                    leaderboardEntries = entries
                    isLoadingLeaderboard = false
                }
            } catch {
                print("❌ Leaderboard error: \(error)")
                await MainActor.run {
                    isLoadingLeaderboard = false
                }
            }
        }
    }
    
    private func recenterToUser() {
        guard let userLoc = locationManager.userLocation else { return }
        let region = MKCoordinateRegion(
            center: userLoc,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        cameraPosition = .region(region)
    }
    
    @ViewBuilder
    private func ruleRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: 0)
        }
    }
    
    @ViewBuilder
    private func ruleRowEdgy(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 18)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: 0)
        }
    }
    
    // MARK: - Collected Popup
    
    @ViewBuilder
    private func collectedPopup(drop: EnergyDrop) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.yellow, .orange],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: .yellow.opacity(0.5), radius: 20)
                
                Image(systemName: "bolt.fill")
                    .font(.system(size: 50))
                            .foregroundColor(.white)
            }
            
            Text("+\(formatNumber(drop.energy))")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            Text(loc(appLanguage, "Energy Collected!", "Энергия собрана!"))
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 30)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.2), radius: 30)
        )
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: locationManager.collectedDrop != nil)
    }
    
    // MARK: - Helpers
    
    private func checkLocationPermission() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestPermission()
        case .denied, .restricted:
            showPermissionAlert = true
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdating()
        @unknown default:
            break
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        let absValue = abs(number)
        let sign = number < 0 ? "-" : ""
        
        func trimTrailingZero(_ s: String) -> String {
            s.hasSuffix(".0") ? String(s.dropLast(2)) : s
        }
        
        if absValue < 1000 { return "\(number)" }
        
        if absValue < 10_000 {
            let v = (Double(absValue) / 1000.0 * 10).rounded() / 10
            return sign + trimTrailingZero(String(format: "%.1f", v)) + "K"
        }
        
        if absValue < 1_000_000 {
            let v = Int((Double(absValue) / 1000.0).rounded())
            return sign + "\(v)K"
        }
        
        if absValue < 10_000_000 {
            let v = (Double(absValue) / 1_000_000.0 * 10).rounded() / 10
            return sign + trimTrailingZero(String(format: "%.1f", v)) + "M"
        }
        
        if absValue < 1_000_000_000 {
            let v = Int((Double(absValue) / 1_000_000.0).rounded())
            return sign + "\(v)M"
        }
        
        let v = (Double(absValue) / 1_000_000_000.0 * 10).rounded() / 10
        return sign + trimTrailingZero(String(format: "%.1f", v)) + "B"
    }
    
    private func openWalkingRoute(to coordinate: CLLocationCoordinate2D) {
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = loc(appLanguage, "Energy Drop", "Капля энергии")
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking,
            MKLaunchOptionsShowsTrafficKey: false
        ])
    }
    
    @ViewBuilder
    private func toast(text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.7))
                )
                .padding(.bottom, 120)
        }
        .transition(.opacity)
    }
    
    @ViewBuilder
    private func dropInfoToast(drop: EnergyDrop) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.yellow)
                Text("+\(formatNumber(drop.energy))")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.75))
            )
            .padding(.bottom, 165)
        }
        .transition(.opacity)
    }
}

// MARK: - Energy Drop Marker

struct EnergyDropMarker: View {
    let drop: EnergyDrop
    let userLocation: CLLocationCoordinate2D?
    let dropNumber: Int
    let maxDropsPerDay: Int
    @State private var isAnimating = false
    
    private var distanceToUser: CLLocationDistance? {
        guard let userLoc = userLocation else { return nil }
        let dropLoc = CLLocation(latitude: drop.coordinate.latitude, longitude: drop.coordinate.longitude)
        let userLocation = CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude)
        return dropLoc.distance(from: userLocation)
    }
    
    private var isWithinRange: Bool {
        guard let distance = distanceToUser else { return false }
        return distance <= 50
    }
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Glow
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        RadialGradient(
                            colors: [Color.green.opacity(0.5), .clear],
                            center: .center,
                            startRadius: 5,
                            endRadius: 35
                        )
                    )
                    .frame(width: 60, height: 70)
                    .scaleEffect(isAnimating ? 1.15 : 0.85)
                
                // Range indicator
                if isWithinRange {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.green, lineWidth: 3)
                        .frame(width: 44, height: 52)
                        .scaleEffect(isAnimating ? 1.08 : 0.92)
                }
                
                // Battery body
                VStack(spacing: 0) {
                    // Battery cap
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 14, height: 5)
                    
                    // Battery main body
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [Color.green, Color.green.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 32, height: 40)
                        
                        // Bolt icon
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .shadow(color: Color.green.opacity(0.5), radius: 8)
                
                // Drop ordinal number
                Text("\(dropNumber)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.6))
                    )
                    .offset(y: -32)
            }
            
            // Energy amount + distance badge
            VStack(spacing: 2) {
                Text(shortEnergy)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                
                if let distance = distanceToUser {
                    Text(formatDistance(distance))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(isWithinRange ? .green : .white.opacity(0.8))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.6))
            )
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
    
    private var shortEnergy: String {
        let value = max(0, drop.energy)
        if value < 1000 { return "\(value)" }
        if value < 10_000 {
            let v = (Double(value) / 1000.0 * 10).rounded() / 10
            let s = String(format: "%.1f", v)
            return (s.hasSuffix(".0") ? String(s.dropLast(2)) : s) + "K"
        }
        if value < 1_000_000 {
            return "\(Int((Double(value) / 1000.0).rounded()))K"
        }
        let v = (Double(value) / 1_000_000.0 * 10).rounded() / 10
        let s = String(format: "%.1f", v)
        return (s.hasSuffix(".0") ? String(s.dropLast(2)) : s) + "M"
    }
    
    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        } else {
            return String(format: "%.1fkm", meters / 1000)
        }
    }
}

#Preview {
    OuterWorldView(model: DIContainer.shared.makeAppModel())
}
