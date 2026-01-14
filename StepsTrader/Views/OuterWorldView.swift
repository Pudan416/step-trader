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
    
    private let pickupRadius: CLLocationDistance = 50 // meters
    private let maxDropsOnScreen = 8
    private let minDropSeparation: CLLocationDistance = 120 // meters
    private let dropLifetime: TimeInterval = 3600 // 1 hour
    
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
        startCleanupTimer()
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
    }
    
    // MARK: - Map Region Changed
    
    func handleMapRegionChange(center: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        let now = Date()
        if let last = lastRegionProcess, now.timeIntervalSince(last) < 0.5 {
            return
        }
        guard center.latitude.isFinite,
              center.longitude.isFinite,
              span.latitudeDelta.isFinite,
              span.longitudeDelta.isFinite else {
            return
        }
        guard abs(center.latitude) <= 90, abs(center.longitude) <= 180 else {
            return
        }
        guard span.latitudeDelta > 0, span.longitudeDelta > 0 else {
            return
        }
        lastRegionProcess = now

        // Keep region reasonable: if user zooms too far out, don't spawn.
        let maxSpanDelta = 0.6
        if span.latitudeDelta > maxSpanDelta || span.longitudeDelta > maxSpanDelta {
            cleanupExpiredDrops()
            return
        }

        cleanupExpiredDrops()

        let remainingSlots = max(0, maxDropsOnScreen - energyDrops.count)
        guard remainingSlots > 0 else { return }

        // Option 2: drops are random inside the *visible* map area
        // 60% chance per region change (onEnd)
        guard Int.random(in: 1...10) <= 6 else { return }

        let spawnCount = min(Int.random(in: 1...2), remainingSlots)
        for _ in 0..<spawnCount {
            spawnDropInVisibleRegion(center: center, span: span)
        }
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
        energyDrops.removeAll { $0.id == drop.id }
        collectedDrop = drop
        totalCollected += drop.energy
        saveTotalCollected()
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
    }

    func magnetPullNearbyDrops() {
        guard let coordinate = userLocation else { return }
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
        guard !nearbyDrops.isEmpty else { return }

        // Collect up to 3 closest drops to keep it punchy (and avoid huge jumps)
        let closest = nearbyDrops
            .sorted {
                let a = CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                let b = CLLocation(latitude: $1.coordinate.latitude, longitude: $1.coordinate.longitude)
                return currentLocation.distance(from: a) < currentLocation.distance(from: b)
            }
            .prefix(3)

        let totalEnergy = closest.reduce(0) { $0 + $1.energy }
        energyDrops.removeAll { drop in
            closest.contains(where: { $0.id == drop.id })
        }
        totalCollected += totalEnergy
        saveTotalCollected()
        saveDrops()

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

    private func spawnDropInVisibleRegion(center: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        let minLat = center.latitude - span.latitudeDelta / 2
        let maxLat = center.latitude + span.latitudeDelta / 2
        let minLon = center.longitude - span.longitudeDelta / 2
        let maxLon = center.longitude + span.longitudeDelta / 2

        for _ in 0..<6 {
            let lat = Double.random(in: minLat...maxLat)
            let lon = Double.random(in: minLon...maxLon)
            let candidate = CLLocationCoordinate2D(latitude: lat, longitude: lon)

            // Ensure it's not too close to existing drops
            let candidateLoc = CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)
            let isTooClose = energyDrops.contains { existing in
                let existingLoc = CLLocation(latitude: existing.coordinate.latitude, longitude: existing.coordinate.longitude)
                return existingLoc.distance(from: candidateLoc) < minDropSeparation
            }
            if isTooClose { continue }

            let energy = Int.random(in: 1...5) * 1000 // 1000-5000
            let expiresAt = Date().addingTimeInterval(dropLifetime)
            let drop = EnergyDrop(coordinate: candidate, energy: energy, expiresAt: expiresAt)
            energyDrops.append(drop)
            saveDrops()
            return
        }
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
    
    var body: some View {
        ZStack {
            // Map
            mapView
            
            // Overlay UI
            VStack {
                headerOverlay
                Spacer()
                bottomOverlay
            }
            
            // Collected energy popup
            if let drop = locationManager.collectedDrop {
                collectedPopup(drop: drop)
            }
        }
        .onAppear {
            checkLocationPermission()
        }
        .onReceive(locationManager.$collectedDrop) { drop in
            if drop != nil {
                showCollectedAlert = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    locationManager.collectedDrop = nil
                }
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
            
            // Energy drops
            ForEach(locationManager.energyDrops) { drop in
                Annotation("", coordinate: drop.coordinate) {
                    EnergyDropMarker(drop: drop, userLocation: locationManager.userLocation)
                }
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            let center = context.region.center
            let span = context.region.span
            locationManager.handleMapRegionChange(center: center, span: span)
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
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.yellow)
                    Text(formatNumber(locationManager.totalCollected))
                        .font(.subheadline.bold())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
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
    
    // MARK: - Bottom Overlay
    
    private var bottomOverlay: some View {
        VStack(spacing: 12) {
            // Active drops indicator
            if !locationManager.energyDrops.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.yellow)
                    Text(loc(appLanguage, "\(locationManager.energyDrops.count) energy drops on map", "\(locationManager.energyDrops.count) капель энергии на карте"))
                        .font(.subheadline)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 10)
                )
            }
            
            // Info card
            infoCard
        }
        .padding(.horizontal)
        .padding(.bottom, 100)
    }
    
    private var infoCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "map.fill")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc(appLanguage, "Explore & Collect", "Исследуй и собирай"))
                        .font(.subheadline.bold())
                    Text(loc(appLanguage, "Scroll the map to discover energy drops. Walk within 50m to collect!", "Двигай карту чтобы находить капли энергии. Подойди ближе 50м чтобы забрать!"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
                
                    Button {
                locationManager.magnetPullNearbyDrops()
                    } label: {
                HStack(spacing: 8) {
                    Image(systemName: "paperclip")
                    Text(loc(appLanguage, "Magnet nearby drops (500m)", "Притянуть капли рядом (500м)"))
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.blue)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(locationManager.userLocation == nil)

            // Debug buttons
            #if DEBUG
            HStack(spacing: 8) {
                Button {
                    locationManager.spawnTestDrop()
                } label: {
                    Text("🧪 Test Drop")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                }
            }
            #endif
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 15)
        )
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
}

// MARK: - Energy Drop Marker

struct EnergyDropMarker: View {
    let drop: EnergyDrop
    let userLocation: CLLocationCoordinate2D?
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
