import Foundation
import AuthenticationServices
import SwiftUI
import CryptoKit
import Security

// MARK: - User Model

struct AppUser: Codable {
    let id: String
    let email: String?
    var nickname: String?
    var country: String?
    var avatarData: Data?
    let createdAt: Date
    
    // Synced stats
    var energySpentLifetime: Int
    var batteriesCollected: Int
    
    var displayName: String {
        if let nickname = nickname, !nickname.isEmpty {
            return nickname
        }
        return email ?? "User"
    }
    
    var locationString: String? {
        guard let countryCode = country, !countryCode.isEmpty else { return nil }
        let locale = Locale.current
        return locale.localizedString(forRegionCode: countryCode) ?? countryCode
    }
    
    var countryFlag: String? {
        guard let countryCode = country, !countryCode.isEmpty else { return nil }
        let base: UInt32 = 127397
        var flag = ""
        for scalar in countryCode.uppercased().unicodeScalars {
            if let unicode = UnicodeScalar(base + scalar.value) {
                flag.append(String(unicode))
            }
        }
        return flag.isEmpty ? nil : flag
    }
    
    init(id: String, email: String?, nickname: String? = nil, country: String? = nil, avatarData: Data? = nil, createdAt: Date, energySpentLifetime: Int = 0, batteriesCollected: Int = 0) {
        self.id = id
        self.email = email
        self.nickname = nickname
        self.country = country
        self.avatarData = avatarData
        self.createdAt = createdAt
        self.energySpentLifetime = energySpentLifetime
        self.batteriesCollected = batteriesCollected
    }
}

// MARK: - Authentication Service

@MainActor
class AuthenticationService: NSObject, ObservableObject {
    
    static let shared = AuthenticationService()
    
    @Published var currentUser: AppUser?
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    /// Current access token for API requests (nil if not authenticated)
    var accessToken: String? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let session = try? JSONDecoder().decode(SupabaseSessionResponse.self, from: data)
        else { return nil }
        return session.accessToken
    }
    
    private let userDefaultsKey = "supabaseSession_v1"
    private let avatarDefaultsPrefix = "userAvatarData_v1_"
    private var currentNonce: String?
    
    override init() {
        super.init()
        Task { @MainActor in
            await loadStoredSessionAndRefreshUser()
        }
    }
    
    // MARK: - Public Methods
    
    func signInWithApple() async throws {
        // Prefer using SignInWithAppleButton in SwiftUI (nonce must be attached to the request).
        throw AuthError.unknown
    }
    
    func signOut() {
        clearStoredSession()
        currentUser = nil
        isAuthenticated = false
    }
    
    /// Handle authorization result from SignInWithAppleButton
    func handleAuthorization(_ authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            error = AuthError.invalidCredential.localizedDescription
            return
        }
        
        guard let nonce = currentNonce else {
            error = "Missing nonce. Please try again."
            return
        }
        
        guard let identityToken = credential.identityToken,
              let idTokenString = String(data: identityToken, encoding: .utf8) else {
            error = "Missing identity token from Apple."
            return
        }
        
        isLoading = true
        error = nil
        
        Task { @MainActor in
            defer { self.isLoading = false }
            do {
                let session = try await self.supabaseSignInWithApple(idToken: idTokenString, nonce: nonce)
                self.storeSession(session)
                try await self.loadCurrentUserFromSupabase(session: session)
                self.isAuthenticated = (self.currentUser != nil)
                self.currentNonce = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
    
    func checkAuthenticationState() async { await loadStoredSessionAndRefreshUser() }
    
    // MARK: - Stats Sync
    
    /// Call this when energy is spent or batteries collected to sync to server
    func syncStats() {
        guard isAuthenticated, let user = currentUser else { return }
        
        let energy = totalLocalEnergySpent()
        let batteries = totalLocalBatteriesCollected()
        
        // Only sync if changed
        if energy == user.energySpentLifetime && batteries == user.batteriesCollected { return }
        
        Task { @MainActor in
            guard let session = loadStoredSession() else { return }
            do {
                try await syncStatsToSupabase(session: session, userId: user.id, energy: energy, batteries: batteries)
                // Update local user
                var updatedUser = user
                updatedUser.energySpentLifetime = energy
                updatedUser.batteriesCollected = batteries
                currentUser = updatedUser
            } catch {
                print("❌ Stats sync failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Profile Update Methods
    
    func updateProfile(nickname: String?, country: String?, avatarData: Data?) {
        guard var user = currentUser else { return }
        
        // Avatar is currently local-only (no column yet in public.users). We keep it in UserDefaults per user id.
        user.avatarData = avatarData
        storeAvatarData(avatarData, for: user.id)
        
        // Update local user immediately for responsive UI
        user.nickname = nickname
        user.country = country
        currentUser = user
        
        Task { @MainActor in
            do {
                guard let session = loadStoredSession() else { return }
                try await patchUserProfile(session: session, userId: user.id, nickname: nickname, country: country)
                // Refresh from DB to keep canonical values
                try await loadCurrentUserFromSupabase(session: session)
            } catch {
                self.error = error.localizedDescription
                print("❌ Profile update failed: \(error.localizedDescription)")
            }
        }
    }

    func updateProfile(nickname: String?, country: String?) {
        updateProfile(nickname: nickname, country: country, avatarData: currentUser?.avatarData)
    }
    
    /// Async version for awaiting completion
    func updateProfileAsync(nickname: String?, country: String?, avatarData: Data?) async throws {
        guard var user = currentUser else { return }
        
        // Avatar is local-only
        user.avatarData = avatarData
        storeAvatarData(avatarData, for: user.id)
        
        // Update local user immediately
        user.nickname = nickname
        user.country = country
        currentUser = user
        
        guard let session = loadStoredSession() else { return }
        try await patchUserProfile(session: session, userId: user.id, nickname: nickname, country: country)
        try await loadCurrentUserFromSupabase(session: session)
    }
    
    // MARK: - Private Methods
    
    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.email]
        request.nonce = sha256(nonce)
    }
    
    private func storeAvatarData(_ data: Data?, for userId: String) {
        let key = avatarDefaultsPrefix + userId
        if let data, !data.isEmpty {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    
    private func loadAvatarData(for userId: String) -> Data? {
        UserDefaults.standard.data(forKey: avatarDefaultsPrefix + userId)
    }
    
    private func loadStoredSession() -> SupabaseSessionResponse? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return nil }
        // Backward-compatible: older builds may have encoded Date as numeric timestamps (default JSONEncoder),
        // while we currently decode ISO8601 from Supabase responses.
        if let s = try? supabaseJSONDecoder().decode(SupabaseSessionResponse.self, from: data) {
            return s
        }
        if let s = try? JSONDecoder().decode(SupabaseSessionResponse.self, from: data) {
            return s
        }
        return nil
    }
    
    private func storeSession(_ session: SupabaseSessionResponse) {
        guard let data = try? supabaseJSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
    
    private func clearStoredSession() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    /// Expose current Supabase access token for other app subsystems (e.g. syncing user state).
    /// This is safe because it's already stored on-device; do not send it to your own backend.
    var currentSupabaseAccessToken: String? { loadStoredSession()?.accessToken }
    
    private func loadStoredSessionAndRefreshUser() async {
        guard let session = loadStoredSession() else {
            currentUser = nil
            isAuthenticated = false
            return
        }
        
        do {
            let validSession = try await ensureValidSession(session)
            if validSession.accessToken != session.accessToken {
                storeSession(validSession)
            }
            try await loadCurrentUserFromSupabase(session: validSession)
            isAuthenticated = (currentUser != nil)
        } catch {
            // Session likely invalid/revoked
            clearStoredSession()
            currentUser = nil
            isAuthenticated = false
        }
    }
    
    // MARK: - Supabase REST
    
    private struct SupabaseConfig {
        let baseURL: URL
        let anonKey: String
        
        static func load() throws -> SupabaseConfig {
            guard let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
                  let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
                  let url = URL(string: urlString),
                  !anonKey.isEmpty
            else {
                throw AuthError.misconfiguredSupabase
            }
            return SupabaseConfig(baseURL: url, anonKey: anonKey)
        }
    }
    
    private func supabaseJSONDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func supabaseJSONEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
    
    private func makeJSONRequest(
        url: URL,
        method: String,
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AuthError.unknown }
        return (data, http)
    }
    
    private func supabaseSignInWithApple(idToken: String, nonce: String) async throws -> SupabaseSessionResponse {
        let cfg = try SupabaseConfig.load()
        
        // POST /auth/v1/token?grant_type=id_token
        let url = cfg.baseURL.appendingPathComponent("auth/v1/token")
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]
        
        let payload = SupabaseIdTokenGrantRequest(provider: "apple", idToken: idToken, nonce: nonce)
        let body = try JSONEncoder().encode(payload)
        let (data, http) = try await makeJSONRequest(
            url: comps.url!,
            method: "POST",
            headers: ["apikey": cfg.anonKey, "authorization": "Bearer \(cfg.anonKey)"],
            body: body
        )
        
        if http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "Supabase auth failed"
            throw AuthError.supabaseError(msg)
        }
        
        return try supabaseJSONDecoder().decode(SupabaseSessionResponse.self, from: data)
    }
    
    private func ensureValidSession(_ session: SupabaseSessionResponse) async throws -> SupabaseSessionResponse {
        // Refresh if expires within 60 seconds
        let threshold = Date().addingTimeInterval(60)
        if session.expiresAt > threshold { return session }
        
        let cfg = try SupabaseConfig.load()
        let url = cfg.baseURL.appendingPathComponent("auth/v1/token")
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        
        let body = try JSONEncoder().encode(SupabaseRefreshGrantRequest(refreshToken: session.refreshToken))
        let (data, http) = try await makeJSONRequest(
            url: comps.url!,
            method: "POST",
            headers: ["apikey": cfg.anonKey, "authorization": "Bearer \(cfg.anonKey)"],
            body: body
        )
        
        if http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "Supabase refresh failed"
            throw AuthError.supabaseError(msg)
        }
        
        return try supabaseJSONDecoder().decode(SupabaseSessionResponse.self, from: data)
    }
    
    private func loadCurrentUserFromSupabase(session: SupabaseSessionResponse) async throws {
        let cfg = try SupabaseConfig.load()
        
        // Fetch canonical profile row from PostgREST: public.users
        let usersURL = cfg.baseURL.appendingPathComponent("rest/v1/users")
        var comps = URLComponents(url: usersURL, resolvingAgainstBaseURL: false)!
        let uid = session.user.id
        comps.queryItems = [
            URLQueryItem(name: "select", value: "id,email,nickname,country,created_at,is_banned,ban_reason,ban_until,energy_spent_lifetime,batteries_collected"),
            URLQueryItem(name: "id", value: "eq.\(uid)")
        ]
        
        let (data, http) = try await makeJSONRequest(
            url: comps.url!,
            method: "GET",
            headers: [
                "apikey": cfg.anonKey,
                "authorization": "Bearer \(session.accessToken)",
                "accept": "application/json"
            ],
            body: nil
        )
        
        if http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "Failed to load profile"
            throw AuthError.supabaseError(msg)
        }
        
        let rows = try supabaseJSONDecoder().decode([SupabasePublicUserRow].self, from: data)
        guard let row = rows.first else {
            // Trigger might not have created the row yet; fallback to auth user
            // Generate a unique nickname for new users
            let generatedNickname = await generateUniqueNickname(session: session)
            
            let user = AppUser(
                id: session.user.id,
                email: session.user.email,
                nickname: generatedNickname,
                country: nil,
                avatarData: loadAvatarData(for: session.user.id),
                createdAt: session.user.createdAt ?? Date(),
                energySpentLifetime: 0,
                batteriesCollected: 0
            )
            currentUser = user
            
            // Push the generated nickname to Supabase
            if let nickname = generatedNickname {
                Task {
                    try? await patchUserProfile(session: session, userId: user.id, nickname: nickname, country: nil)
                }
            }
            return
        }
        
        // If user exists but has no nickname, generate one
        if row.nickname == nil || row.nickname?.isEmpty == true {
            let generatedNickname = await generateUniqueNickname(session: session)
            if let nickname = generatedNickname {
                Task {
                    try? await patchUserProfile(session: session, userId: row.id, nickname: nickname, country: row.country)
                }
            }
        }
        
        // Ban gating (client-side visibility; server-side should still enforce via RLS if needed)
        if row.isBanned {
            // If ban_until is nil => permanent. If future => active.
            let until = row.banUntil
            if until == nil || until! > Date() {
                currentUser = AppUser(
                    id: row.id,
                    email: row.email,
                    nickname: row.nickname,
                    country: row.country,
                    avatarData: loadAvatarData(for: row.id),
                    createdAt: row.createdAt,
                    energySpentLifetime: row.energySpentLifetime ?? 0,
                    batteriesCollected: row.batteriesCollected ?? 0
                )
                isAuthenticated = true
                error = "Account is banned."
                return
            }
        }
        
        let serverEnergy = row.energySpentLifetime ?? 0
        let serverBatteries = row.batteriesCollected ?? 0
        
        // Merge with local data - take maximum to prevent losing progress
        let localEnergy = totalLocalEnergySpent()
        let localBatteries = totalLocalBatteriesCollected()
        
        let mergedEnergy = max(serverEnergy, localEnergy)
        let mergedBatteries = max(serverBatteries, localBatteries)
        
        currentUser = AppUser(
            id: row.id,
            email: row.email,
            nickname: row.nickname,
            country: row.country,
            avatarData: loadAvatarData(for: row.id),
            createdAt: row.createdAt,
            energySpentLifetime: mergedEnergy,
            batteriesCollected: mergedBatteries
        )
        
        // If local has more, push to server
        if localEnergy > serverEnergy || localBatteries > serverBatteries {
            Task {
                try? await syncStatsToSupabase(session: session, userId: row.id, energy: mergedEnergy, batteries: mergedBatteries)
            }
        }
        
        // Apply server data to local storage if server has more
        var didRestoreData = false
        if serverEnergy > localEnergy {
            applyEnergySpentToLocal(serverEnergy)
            didRestoreData = true
        }
        if serverBatteries > localBatteries {
            applyBatteriesToLocal(serverBatteries)
            didRestoreData = true
        }
        
        // Notify AppModel to reload data
        if didRestoreData {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .init("StatsRestoredFromServer"), object: nil)
            }
        }
    }
    
    // MARK: - Stats Sync Helpers
    
    private func totalLocalEnergySpent() -> Int {
        // Sum of all energy spent lifetime from UserDefaults
        guard let data = UserDefaults.stepsTrader().data(forKey: "appStepsSpentLifetime_v1"),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return 0
        }
        return dict.values.reduce(0, +)
    }
    
    private func totalLocalBatteriesCollected() -> Int {
        UserDefaults.standard.integer(forKey: "outerworld_totalcollected") / 5
    }
    
    private func applyEnergySpentToLocal(_ total: Int) {
        print("📊 Applying server energy to local: \(total)")
        
        // Load existing data
        let defaults = UserDefaults.stepsTrader()
        var dict: [String: Int] = [:]
        if let data = defaults.data(forKey: "appStepsSpentLifetime_v1"),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            dict = decoded
        }
        
        // Calculate current total
        let currentTotal = dict.values.reduce(0, +)
        
        // If server has more, add the difference to a _restored key
        if total > currentTotal {
            let diff = total - currentTotal
            dict["_restored", default: 0] += diff
            print("📊 Restored \(diff) energy from server (total now: \(total))")
            
            if let encoded = try? JSONEncoder().encode(dict) {
                defaults.set(encoded, forKey: "appStepsSpentLifetime_v1")
            }
        }
    }
    
    private func applyBatteriesToLocal(_ count: Int) {
        let energy = count * 5
        UserDefaults.standard.set(energy, forKey: "outerworld_totalcollected")
        print("📊 Applying server batteries to local: \(count) (\(energy) energy)")
    }
    
    private func syncStatsToSupabase(session: SupabaseSessionResponse, userId: String, energy: Int, batteries: Int) async throws {
        let cfg = try SupabaseConfig.load()
        let usersURL = cfg.baseURL.appendingPathComponent("rest/v1/users")
        var comps = URLComponents(url: usersURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "id", value: "eq.\(userId)")]
        
        let patch = ["energy_spent_lifetime": energy, "batteries_collected": batteries]
        let body = try JSONEncoder().encode(patch)
        
        let (_, http) = try await makeJSONRequest(
            url: comps.url!,
            method: "PATCH",
            headers: [
                "apikey": cfg.anonKey,
                "authorization": "Bearer \(session.accessToken)",
                "prefer": "return=minimal",
                "accept": "application/json"
            ],
            body: body
        )
        
        if http.statusCode < 400 {
            print("✅ Stats synced to Supabase: energy=\(energy), batteries=\(batteries)")
        }
    }
    
    // MARK: - Energy Balance Logging
    
    /// Logs current energy state to Supabase for admin visibility
    func logEnergyState(stepsToday: Int, energyBalance: Int, energySpent: Int, batteriesCollected: Int) async {
        guard isAuthenticated,
              let userId = currentUser?.id,
              let session = loadStoredSession() else {
            print("📊 Energy log skipped: not authenticated or no session")
            return
        }
        
        print("📊 Logging energy state: steps=\(stepsToday), balance=\(energyBalance), spent=\(energySpent), batteries=\(batteriesCollected)")
        
        do {
            let cfg = try SupabaseConfig.load()
            let usersURL = cfg.baseURL.appendingPathComponent("rest/v1/users")
            var comps = URLComponents(url: usersURL, resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "id", value: "eq.\(userId)")]
            
            let patch = SupabasePublicUserPatch(
                energySpentLifetime: energySpent,
                batteriesCollected: batteriesCollected,
                currentStepsToday: stepsToday,
                currentEnergyBalance: energyBalance
            )
            let body = try JSONEncoder().encode(patch)
            
            print("📊 PATCH URL: \(comps.url?.absoluteString ?? "nil")")
            print("📊 PATCH body: \(String(data: body, encoding: .utf8) ?? "nil")")
            
            let (data, http) = try await makeJSONRequest(
                url: comps.url!,
                method: "PATCH",
                headers: [
                    "apikey": cfg.anonKey,
                    "authorization": "Bearer \(session.accessToken)",
                    "prefer": "return=representation",
                    "accept": "application/json"
                ],
                body: body
            )
            
            let responseBody = String(data: data, encoding: .utf8) ?? "empty"
            print("📊 PATCH response: HTTP \(http.statusCode), body: \(responseBody)")
            
            if http.statusCode < 400 {
                print("✅ Energy state logged successfully")
            } else {
                print("❌ Energy state log failed: HTTP \(http.statusCode)")
            }
        } catch {
            print("❌ Energy state log error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Nickname Generation
    
    private func generateUniqueNickname(session: SupabaseSessionResponse) async -> String? {
        // Word pools for generating fun nicknames
        let prefixes = [
            // Doom-themed
            "Doom", "Dark", "Shadow", "Chaos", "Void", "Cyber", "Neo", "Night", "Storm", "Iron",
            // Walk-themed
            "Swift", "Step", "Stride", "Path", "Trail", "Road", "Walk", "Run", "Sprint", "Dash",
            // Social-themed
            "Scroll", "Swipe", "Tap", "Click", "Like", "Share", "Post", "Feed", "Viral", "Trend"
        ]
        
        let suffixes = [
            // Doom-themed
            "Slayer", "Hunter", "Rider", "Walker", "Master", "Lord", "Knight", "Warrior", "Phantom", "Reaper",
            // Walk-themed  
            "Stepper", "Runner", "Mover", "Pacer", "Tracker", "Chaser", "Seeker", "Finder", "Blazer", "Cruiser",
            // Social-themed
            "Scroller", "Surfer", "Diver", "Lurker", "Poster", "Sharer", "Viewer", "Watcher", "Browser", "Streamer"
        ]
        
        // Try up to 10 times to find a unique nickname
        for _ in 0..<10 {
            let prefix = prefixes.randomElement() ?? "User"
            let suffix = suffixes.randomElement() ?? "One"
            let number = Int.random(in: 10...99)
            let candidate = "\(prefix)\(suffix)\(number)"
            
            // Check if this nickname is already taken
            if await isNicknameAvailable(candidate, session: session) {
                return candidate
            }
        }
        
        // Fallback: use UUID-based name
        let shortId = UUID().uuidString.prefix(6).uppercased()
        return "User\(shortId)"
    }
    
    private func isNicknameAvailable(_ nickname: String, session: SupabaseSessionResponse) async -> Bool {
        do {
            let cfg = try SupabaseConfig.load()
            let usersURL = cfg.baseURL.appendingPathComponent("rest/v1/users")
            var comps = URLComponents(url: usersURL, resolvingAgainstBaseURL: false)!
            comps.queryItems = [
                URLQueryItem(name: "select", value: "id"),
                URLQueryItem(name: "nickname", value: "eq.\(nickname)"),
                URLQueryItem(name: "limit", value: "1")
            ]
            
            var request = URLRequest(url: comps.url!)
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return true // Assume available on error
            }
            
            // If array is empty, nickname is available
            if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return jsonArray.isEmpty
            }
            
            return true
        } catch {
            print("⚠️ Nickname check failed: \(error.localizedDescription)")
            return true // Assume available on error
        }
    }
    
    private func patchUserProfile(session: SupabaseSessionResponse, userId: String, nickname: String?, country: String?) async throws {
        let cfg = try SupabaseConfig.load()
        let usersURL = cfg.baseURL.appendingPathComponent("rest/v1/users")
        var comps = URLComponents(url: usersURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "id", value: "eq.\(userId)")]
        
        let patch = SupabasePublicUserPatch(nickname: nickname, country: country)
        let body = try JSONEncoder().encode(patch)
        
        print("🔄 PATCH profile: userId=\(userId), nickname=\(nickname ?? "nil"), country=\(country ?? "nil")")
        print("🔄 PATCH URL: \(comps.url?.absoluteString ?? "nil")")
        
        let (data, http) = try await makeJSONRequest(
            url: comps.url!,
            method: "PATCH",
            headers: [
                "apikey": cfg.anonKey,
                "authorization": "Bearer \(session.accessToken)",
                "prefer": "return=representation",
                "accept": "application/json"
            ],
            body: body
        )
        
        let responseString = String(data: data, encoding: .utf8) ?? "(empty)"
        print("🔄 PATCH response: status=\(http.statusCode), body=\(responseString)")
        
        if http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "Failed to update profile"
            throw AuthError.supabaseError(msg)
        }
        
        // Check if any rows were updated (empty array means RLS blocked or row doesn't exist)
        if responseString == "[]" {
            print("⚠️ PATCH returned empty array - check RLS policies or if user row exists")
            throw AuthError.supabaseError("Profile update failed. User row may not exist or access denied.")
        }
    }
    
    // MARK: - Nonce helpers (Apple Sign In)
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
        Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if errorCode != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
            }
            
            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case invalidCredential
    case cancelled
    case misconfiguredSupabase
    case supabaseError(String)
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Invalid credentials received"
        case .cancelled:
            return "Sign in was cancelled"
        case .misconfiguredSupabase:
            return "Supabase is not configured. Set SUPABASE_URL and SUPABASE_ANON_KEY in Info.plist."
        case .supabaseError(let message):
            return message
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

// MARK: - Supabase DTOs

private struct SupabaseIdTokenGrantRequest: Codable {
    let provider: String
    let idToken: String
    let nonce: String
    
    enum CodingKeys: String, CodingKey {
        case provider
        case idToken = "id_token"
        case nonce
    }
}

private struct SupabaseRefreshGrantRequest: Codable {
    let refreshToken: String
    enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
}

private struct SupabaseAuthUser: Codable {
    let id: String
    let email: String?
    let createdAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case createdAt = "created_at"
    }
}

private struct SupabaseSessionResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String
    let user: SupabaseAuthUser
    let expiresAt: Date
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case user
        case expiresAt = "expires_at"
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try c.decode(String.self, forKey: .accessToken)
        tokenType = try c.decode(String.self, forKey: .tokenType)
        expiresIn = try c.decode(Int.self, forKey: .expiresIn)
        refreshToken = try c.decode(String.self, forKey: .refreshToken)
        user = try c.decode(SupabaseAuthUser.self, forKey: .user)
        if let stored = try? c.decode(Date.self, forKey: .expiresAt) {
            expiresAt = stored
        } else {
            expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(accessToken, forKey: .accessToken)
        try c.encode(tokenType, forKey: .tokenType)
        try c.encode(expiresIn, forKey: .expiresIn)
        try c.encode(refreshToken, forKey: .refreshToken)
        try c.encode(user, forKey: .user)
        try c.encode(expiresAt, forKey: .expiresAt)
    }
}

private struct SupabasePublicUserRow: Codable {
    let id: String
    let email: String?
    let nickname: String?
    let country: String?
    let createdAt: Date
    let isBanned: Bool
    let banReason: String?
    let banUntil: Date?
    let energySpentLifetime: Int?
    let batteriesCollected: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case nickname
        case country
        case createdAt = "created_at"
        case isBanned = "is_banned"
        case banReason = "ban_reason"
        case banUntil = "ban_until"
        case energySpentLifetime = "energy_spent_lifetime"
        case batteriesCollected = "batteries_collected"
    }
}

private struct SupabasePublicUserPatch: Codable {
    let nickname: String?
    let country: String?
    let energySpentLifetime: Int?
    let batteriesCollected: Int?
    let currentStepsToday: Int?
    let currentEnergyBalance: Int?
    let lastSyncAt: String?
    
    enum CodingKeys: String, CodingKey {
        case nickname
        case country
        case energySpentLifetime = "energy_spent_lifetime"
        case batteriesCollected = "batteries_collected"
        case currentStepsToday = "current_steps_today"
        case currentEnergyBalance = "current_energy_balance"
        case lastSyncAt = "last_sync_at"
    }
    
    init(nickname: String? = nil, country: String? = nil, energySpentLifetime: Int? = nil, batteriesCollected: Int? = nil, currentStepsToday: Int? = nil, currentEnergyBalance: Int? = nil) {
        self.nickname = nickname
        self.country = country
        self.energySpentLifetime = energySpentLifetime
        self.batteriesCollected = batteriesCollected
        self.currentStepsToday = currentStepsToday
        self.currentEnergyBalance = currentEnergyBalance
        self.lastSyncAt = ISO8601DateFormatter().string(from: Date())
    }
}
