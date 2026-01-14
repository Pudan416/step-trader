import SwiftUI
import MapKit
import CoreLocation

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
            self?.cleanupExpiredDrops()
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
            UserDefaults.standard.set(today, forKey: collectedTodayDayKeyStorageKey)
            collectedToday = 0
            saveCollectedToday()
        }
    }
    
    private func loadCollectedToday() {
        refreshCollectedTodayDayIfNeeded()
        collectedToday = UserDefaults.standard.integer(forKey: collectedTodayStorageKey)
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
        
        let energy = Int.random(in: 1...5) * 1000
        let expiresAt = Date().addingTimeInterval(dropLifetime)
        
        let drop = EnergyDrop(
            coordinate: dropCoordinate,
            energy: energy,
            expiresAt: expiresAt
        )
        
        energyDrops.append(drop)
        saveDrops()
    }
    
}

// MARK: - Outer World View

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
    
    var body: some View {
        ZStack {
            // Map
            mapView
            
            // Overlay UI
            VStack {
                headerOverlay
                Spacer()
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
        .onAppear {
            checkLocationPermission()
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
                    locationManager.magnetPull(drop: drop)
                }
                selectedDropForAction = nil
            }
            .disabled(locationManager.userLocation == nil || locationManager.magnetUsesToday >= 3)
            
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
            MapUserLocationButton()
            MapCompass()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .top)
    }
    
    // MARK: - Header Overlay
    
    private var headerOverlay: some View {
        VStack(spacing: 0) {
            // Status bar background
            Color.clear.frame(height: 0)
            
            HStack(spacing: 16) {
                // Title
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc(appLanguage, "Outer World", "Внешний мир"))
                        .font(.title2.bold())
                    Text(loc(appLanguage, "Explore the map to find energy", "Исследуй карту, находи энергию"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Stats badge
                let cap = max(1, locationManager.dailyCap)
                let used = min(cap, max(0, locationManager.collectedToday))
                VStack(alignment: .trailing, spacing: 4) {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.yellow)
                            Text(formatNumber(locationManager.totalCollected))
                                .font(.subheadline.bold())
                        }
                        
                        Text(loc(appLanguage, "Today \(formatNumber(used)) / \(formatNumber(cap))", "Сегодня \(formatNumber(used)) / \(formatNumber(cap))"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 999)
                        .fill(.ultraThinMaterial)
                )
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 12)
                .background(
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.systemBackground).opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
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
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [energyColor.opacity(0.6), .clear],
                            center: .center,
                            startRadius: 5,
                            endRadius: 30
                        )
                    )
                    .frame(width: 60, height: 60)
                    .scaleEffect(isAnimating ? 1.2 : 0.8)
                
                // Range indicator ring
                if isWithinRange {
                    Circle()
                        .stroke(Color.green, lineWidth: 3)
                        .frame(width: 44, height: 44)
                        .scaleEffect(isAnimating ? 1.1 : 0.9)
                }
                
                // Main circle
                    Circle()
                        .fill(
                            LinearGradient(
                            colors: [energyColor, energyColor.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    .frame(width: 36, height: 36)
                    .shadow(color: energyColor.opacity(0.5), radius: 8)
                    
                // Icon
                    Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                
                // Drop ordinal number
                Text("\(dropNumber)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                    .offset(y: -24)
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
    
    private var energyColor: Color {
        switch drop.energy {
        case 1000...2000: return .green
        case 2001...3000: return .cyan
        case 3001...4000: return .orange
        default: return .yellow
        }
    }
    
    private var shortEnergy: String {
        if drop.energy >= 1000 {
            return "\(drop.energy / 1000)K"
        }
        return "\(drop.energy)"
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
