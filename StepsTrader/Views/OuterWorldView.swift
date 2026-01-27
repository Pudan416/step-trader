import SwiftUI
import MapKit
import CoreLocation
import UIKit

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
    
    @State private var cameraPosition: MapCameraPosition = .automatic
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
            // Map - используем Group для безопасной инициализации
            Group {
                mapView
            }
            
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
                toast(text: loc(appLanguage, "Magnet limit reached (3/day)"))
            } else if showMagnetNoDropsToast {
                toast(text: loc(appLanguage, "No drops within 500m"))
            } else if showDailyCapToast {
                toast(text: loc(appLanguage, "Outer World cap reached for today"))
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
            print("🟢 OuterWorldView: onAppear")
            // Initialize with safe default region if location not available
            if locationManager.userLocation == nil {
                // Default to a safe region (e.g., center of a major city or last known location)
                let defaultRegion = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // San Francisco default
                    span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                )
                cameraPosition = .region(defaultRegion)
            }
            
            checkLocationPermission()
            // Force refresh to catch midnight reset - откладываем, чтобы не блокировать инициализацию view
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms задержка
                locationManager.refreshEconomySnapshot()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Ensure daily counters (50/day cap + magnets/day) reset after midnight even if the app was backgrounded.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms задержка
                locationManager.refreshEconomySnapshot()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            // Fires around midnight / time changes. Re-check daily boundary.
            locationManager.refreshEconomySnapshot()
        }
        .onChange(of: model.stepsToday) { _, _ in
            // Daily cap uses the latest app settings; AppModel persists it into defaults.
            locationManager.refreshEconomySnapshot()
        }
        .onReceive(locationManager.$userLocation) { location in
            if let location = location, cameraPosition == .automatic {
                // Update camera position when location becomes available
                cameraPosition = .region(MKCoordinateRegion(
                    center: location,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            }
        }
        .onReceive(locationManager.$collectedDrop) { drop in
            if drop != nil {
                showCollectedAlert = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 секунды
                    locationManager.collectedDrop = nil
                }
            }
        }
        .onReceive(locationManager.$magnetLimitReachedAt) { date in
            guard date != nil else { return }
            showMagnetLimitToast = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 секунды
                showMagnetLimitToast = false
            }
        }
        .onReceive(locationManager.$magnetNoDropsAt) { date in
            guard date != nil else { return }
            showMagnetNoDropsToast = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_800_000_000) // 1.8 секунды
                showMagnetNoDropsToast = false
            }
        }
        .onReceive(locationManager.$dailyCapReachedAt) { date in
            guard date != nil else { return }
            showDailyCapToast = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 секунды
                showDailyCapToast = false
            }
        }
        .confirmationDialog(
            loc(appLanguage, "Control Drop"),
            isPresented: .init(
                get: { selectedDropForAction != nil },
                set: { if !$0 { selectedDropForAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(loc(appLanguage, "Build walking route")) {
                if let drop = selectedDropForAction {
                    openWalkingRoute(to: drop.coordinate)
                }
                selectedDropForAction = nil
            }
            
            let magnetsLeft = max(0, 3 - locationManager.magnetUsesToday)
            Button(loc(appLanguage, "Use magnet (\(magnetsLeft) left)")) {
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
            
            Button(loc(appLanguage, "Cancel"), role: .cancel) {
                selectedDropForAction = nil
            }
        } message: {
            if let drop = selectedDropForAction {
                Text(loc(appLanguage, "This drop contains \(formatNumber(drop.energy)) control."))
            }
        }
        .alert(loc(appLanguage, "Location Required"), isPresented: $showPermissionAlert) {
            Button(loc(appLanguage, "Settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(loc(appLanguage, "Cancel"), role: .cancel) {}
        } message: {
            Text(loc(appLanguage, "Enable location access to explore the Outer World and collect control drops"))
        }
    }
    
    // MARK: - Map View
    
    @ViewBuilder
    private var mapView: some View {
        Map(position: $cameraPosition) {
            // User location
            if locationManager.authorizationStatus == .authorizedWhenInUse || 
               locationManager.authorizationStatus == .authorizedAlways {
                UserAnnotation()
            }

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
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_600_000_000) // 1.6 секунды
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
        .task {
            print("🟢 OuterWorldView: Map view task started")
            // Небольшая задержка для безопасной инициализации Metal
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            print("🟢 OuterWorldView: Map view task completed")
        }
    }
    
    // MARK: - Header Overlay
    
    // MARK: - Motivational Text
    private var motivationalText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        
        // Night phrases (22:00-06:00) - night walks + magnets
        let nightPhrasesEN = [
            "🌙 Night walks hit different. Try it if you want",
            "🧲 3 magnets on the map. Grab batteries if it helps",
            "😴 Can't sleep? Night stroll = night scroll. Or don't",
            "🌃 City's quiet. Perfect time to hunt. Your call",
            "⏰ Midnight brings new magnets. Use them if you want"
        ]
        
        // Morning phrases (06:00-12:00) - motivation to walk
        let morningPhrasesEN = [
            "🌿 Touch grass. Or don't. Your call",
            "🚶 Your legs work. Use them if you want",
            "📱 No steps = no scroll. Or ignore it",
            "☀️ Get yourself outside. Or don't",
            "👑 Earn your screen time. Or don't. That's fine"
        ]
        
        // Afternoon phrases (12:00-17:00) - balance walk + scroll
        let afternoonPhrasesEN = [
            "⚖️ Walk a bit, scroll a bit. Balance",
            "🎯 Doomscroll earned. Or not. Your call",
            "🌿 Touched grass? Good. Now chill",
            "⚡ Control's stacking. Your call",
            "🕐 Half day done. Your call"
        ]
        
        // Evening phrases (17:00-22:00) - wind down, spend energy
        let eveningPhrasesEN = [
            "🔥 Control expires at midnight. Use it if you want",
            "😌 Wind down time. Spend control if it helps",
            "🛋️ Evening mode. Scroll if you want",
            "✨ You walked. Or didn't. That's fine",
            "⏳ Clock's ticking. Use it if it helps"
        ]
        
        let phrasesEN: [String]
        
        if hour < 6 || hour >= 22 {
            phrasesEN = nightPhrasesEN
        } else if hour < 12 {
            phrasesEN = morningPhrasesEN
        } else if hour < 17 {
            phrasesEN = afternoonPhrasesEN
        } else {
            phrasesEN = eveningPhrasesEN
        }
        
        let index = dayOfYear % phrasesEN.count
        return loc(appLanguage, phrasesEN[index])
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
                        Text(loc(appLanguage, "Outer World"))
                            .font(.headline)
                        Text(loc(appLanguage, "Touch grass, get control ⚡️"))
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
                            Text(loc(appLanguage, "Control Hunt"))
                                .font(.headline)
                            Text(loc(appLanguage, "Walk → Collect → Dominate 🏆"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Today card - glass
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(loc(appLanguage, "Today's haul"))
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
                                Text("+5")
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
                        Text(loc(appLanguage, "The Rules"))
                            .font(.caption.weight(.bold))
                        
                        ruleRowEdgy(
                            icon: "scope",
                            color: .blue,
                            text: loc(appLanguage, "One battery spawns within 500m")
                        )
                        
                        ruleRowEdgy(
                            icon: "figure.walk",
                            color: .green,
                            text: loc(appLanguage, "Walk 50m to grab it")
                        )
                        
                        ruleRowEdgy(
                            icon: "dot.radiowaves.up.forward",
                            color: .purple,
                            text: loc(appLanguage, "Lazy? Use a magnet (3/day)")
                        )
                        
                        ruleRowEdgy(
                            icon: "moon.fill",
                            color: .indigo,
                            text: loc(appLanguage, "Night walks = extra chill vibes")
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
            .navigationTitle(loc(appLanguage, "Outer World"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc(appLanguage, "Close")) {
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
                        Text(loc(appLanguage, "Loading legends..."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if leaderboardEntries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "trophy")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(loc(appLanguage, "No one here yet"))
                            .font(.headline)
                        Text(loc(appLanguage, "Be the first to dominate!"))
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
            .navigationTitle(loc(appLanguage, "🏆 Leaderboard"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc(appLanguage, "Close")) {
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
                Text(entry.nickname ?? loc(appLanguage, "Anonymous"))
                    .font(.subheadline.weight(isCurrentUser ? .bold : .medium))
                    .foregroundColor(isCurrentUser ? .accentColor : .primary)
                if isCurrentUser {
                    Text(loc(appLanguage, "You"))
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
            
            Text(loc(appLanguage, "Control collected"))
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
        item.name = loc(appLanguage, "Control Drop")
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
