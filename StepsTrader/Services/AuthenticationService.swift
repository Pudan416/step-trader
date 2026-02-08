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
    var avatarData: Data?  // Local cache
    var avatarURL: String? // Supabase Storage URL
    let createdAt: Date
    
    // Synced stats
    var energySpentLifetime: Int
    
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
    
    init(id: String, email: String?, nickname: String? = nil, country: String? = nil, avatarData: Data? = nil, avatarURL: String? = nil, createdAt: Date, energySpentLifetime: Int = 0) {
        self.id = id
        self.email = email
        self.nickname = nickname
        self.country = country
        self.avatarData = avatarData
        self.avatarURL = avatarURL
        self.createdAt = createdAt
        self.energySpentLifetime = energySpentLifetime
    }
}

// MARK: - Authentication Service

@MainActor
class AuthenticationService: NSObject, ObservableObject {
    
    static let shared = AuthenticationService()
    private let network = NetworkClient.shared
    
    @Published var currentUser: AppUser?
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    /// Indicates if the initial session restore has completed
    @Published private(set) var isInitialized: Bool = false
    
    /// Current access token for API requests (nil if not authenticated)
    var accessToken: String? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return nil }
        // Try both decoders for backward compatibility
        if let session = try? supabaseJSONDecoder().decode(SupabaseSessionResponse.self, from: data) {
            return session.accessToken
        }
        if let session = try? JSONDecoder().decode(SupabaseSessionResponse.self, from: data) {
            return session.accessToken
        }
        return nil
    }
    
    private let userDefaultsKey = "supabaseSession_v1"
    private let avatarDefaultsPrefix = "userAvatarData_v1_"
    private var currentNonce: String?
    private var initializationContinuation: CheckedContinuation<Void, Never>?
    
    override init() {
        super.init()
        Task { @MainActor in
            await loadStoredSessionAndRefreshUser()
            isInitialized = true
            print("🔐 AuthenticationService initialized: isAuthenticated=\(isAuthenticated)")
        }
    }
    
    /// Wait for the initial session restore to complete
    func waitForInitialization() async {
        if isInitialized { return }
        // Poll until initialized (simple approach)
        while !isInitialized {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
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
        
        // Only sync if changed
        if energy == user.energySpentLifetime { return }
        
        Task { @MainActor in
            guard let session = loadStoredSession() else { return }
            do {
                try await syncStatsToSupabase(session: session, userId: user.id, energy: energy)
                // Update local user
                var updatedUser = user
                updatedUser.energySpentLifetime = energy
                currentUser = updatedUser
            } catch {
                print("❌ Stats sync failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Profile Update Methods
    
    func updateProfile(nickname: String?, country: String?, avatarData: Data?) {
        guard var user = currentUser else { return }
        
        // Store avatar locally for immediate display
        user.avatarData = avatarData
        storeAvatarData(avatarData, for: user.id)
        
        // Update local user immediately for responsive UI
        user.nickname = nickname
        user.country = country
        currentUser = user
        
        Task { @MainActor in
            do {
                guard let session = loadStoredSession() else { return }
                
                // Upload avatar to Supabase Storage if provided
                var avatarUrl: String? = nil
                if let data = avatarData, !data.isEmpty {
                    avatarUrl = try await uploadAvatarToStorage(session: session, userId: user.id, imageData: data)
                    print("📸 Avatar uploaded: \(avatarUrl ?? "nil")")
                } else if avatarData == nil {
                    // Avatar was removed - delete from storage
                    try? await deleteAvatarFromStorage(session: session, userId: user.id)
                    avatarUrl = "" // Empty string to clear the URL in DB
                }
                
                try await patchUserProfile(session: session, userId: user.id, nickname: nickname, country: country, avatarUrl: avatarUrl)
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
        
        // Store avatar locally
        user.avatarData = avatarData
        storeAvatarData(avatarData, for: user.id)
        
        // Update local user immediately
        user.nickname = nickname
        user.country = country
        currentUser = user
        
        guard let session = loadStoredSession() else { return }
        
        // Upload avatar to Supabase Storage if provided
        var avatarUrl: String? = nil
        if let data = avatarData, !data.isEmpty {
            avatarUrl = try await uploadAvatarToStorage(session: session, userId: user.id, imageData: data)
        } else if avatarData == nil {
            // Avatar was removed
            try? await deleteAvatarFromStorage(session: session, userId: user.id)
            avatarUrl = ""
        }
        
        try await patchUserProfile(session: session, userId: user.id, nickname: nickname, country: country, avatarUrl: avatarUrl)
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
        print("🔐 loadStoredSessionAndRefreshUser called")
        guard let session = loadStoredSession() else {
            print("🔐 No stored session found in UserDefaults")
            currentUser = nil
            isAuthenticated = false
            return
        }
        
        print("🔐 Found stored session, user: \(session.user.id), expires: \(session.expiresAt)")
        
        do {
            let validSession = try await ensureValidSession(session)
            print("🔐 Session validated/refreshed successfully")
            if validSession.accessToken != session.accessToken {
                print("🔐 Token was refreshed, storing new session")
                storeSession(validSession)
            }
            try await loadCurrentUserFromSupabase(session: validSession)
            isAuthenticated = (currentUser != nil)
            print("🔐 Final state: isAuthenticated=\(isAuthenticated), user=\(currentUser?.id ?? "nil")")
        } catch {
            print("🔐 Session restore failed: \(error.localizedDescription)")
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
        
        let (data, http) = try await network.data(for: req)
        return (data, http)
    }
    
    private func supabaseSignInWithApple(idToken: String, nonce: String) async throws -> SupabaseSessionResponse {
        let cfg = try SupabaseConfig.load()
        
        // POST /auth/v1/token?grant_type=id_token
        let url = cfg.baseURL.appendingPathComponent("auth/v1/token")
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AuthError.supabaseError("Invalid URL: \(url)")
        }
        comps.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]
        
        guard let finalURL = comps.url else {
            throw AuthError.supabaseError("Failed to construct auth URL")
        }
        
        let payload = SupabaseIdTokenGrantRequest(provider: "apple", idToken: idToken, nonce: nonce)
        let body = try JSONEncoder().encode(payload)
        let (data, http) = try await makeJSONRequest(
            url: finalURL,
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
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AuthError.supabaseError("Invalid URL: \(url)")
        }
        comps.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        
        guard let finalURL = comps.url else {
            throw AuthError.supabaseError("Failed to construct refresh URL")
        }
        
        let body = try JSONEncoder().encode(SupabaseRefreshGrantRequest(refreshToken: session.refreshToken))
        let (data, http) = try await makeJSONRequest(
            url: finalURL,
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
        guard var comps = URLComponents(url: usersURL, resolvingAgainstBaseURL: false) else {
            throw AuthError.supabaseError("Invalid users URL: \(usersURL)")
        }
        let uid = session.user.id
        comps.queryItems = [
            URLQueryItem(name: "select", value: "id,email,nickname,country,created_at,is_banned,ban_reason,ban_until,energy_spent_lifetime"),
            URLQueryItem(name: "id", value: "eq.\(uid)")
        ]
        
        guard let finalURL = comps.url else {
            throw AuthError.supabaseError("Failed to construct users URL")
        }
        
        let (data, http) = try await makeJSONRequest(
            url: finalURL,
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
                avatarURL: nil,
                createdAt: session.user.createdAt ?? Date(),
                energySpentLifetime: 0
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
        
        // Load avatar: prefer local cache, fallback to URL
        var avatarData = loadAvatarData(for: row.id)
        if avatarData == nil, let urlString = row.avatarUrl, !urlString.isEmpty,
           let url = URL(string: urlString) {
            // Download avatar from Supabase Storage
            avatarData = try? await downloadAvatar(from: url)
            if let data = avatarData {
                storeAvatarData(data, for: row.id)
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
                    avatarData: avatarData,
                    avatarURL: row.avatarUrl,
                    createdAt: row.createdAt,
                    energySpentLifetime: row.energySpentLifetime ?? 0
                )
                isAuthenticated = true
                error = "Account is banned."
                return
            }
        }
        
        let serverEnergy = row.energySpentLifetime ?? 0
        
        // Merge with local data - take maximum to prevent losing progress
        let localEnergy = totalLocalEnergySpent()
        let mergedEnergy = max(serverEnergy, localEnergy)
        
        currentUser = AppUser(
            id: row.id,
            email: row.email,
            nickname: row.nickname,
            country: row.country,
            avatarData: avatarData,
            avatarURL: row.avatarUrl,
            createdAt: row.createdAt,
            energySpentLifetime: mergedEnergy
        )
        
        // If local has more, push to server
        if localEnergy > serverEnergy {
            Task {
                try? await syncStatsToSupabase(session: session, userId: row.id, energy: mergedEnergy)
            }
        }
        
        // Apply server data to local storage if server has more
        if serverEnergy > localEnergy {
            applyEnergySpentToLocal(serverEnergy)
            
            // Notify AppModel to reload data
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
    
    private func syncStatsToSupabase(session: SupabaseSessionResponse, userId: String, energy: Int) async throws {
        let cfg = try SupabaseConfig.load()
        let usersURL = cfg.baseURL.appendingPathComponent("rest/v1/users")
        guard var comps = URLComponents(url: usersURL, resolvingAgainstBaseURL: false) else {
            throw AuthError.supabaseError("Invalid users URL")
        }
        comps.queryItems = [URLQueryItem(name: "id", value: "eq.\(userId)")]
        
        guard let finalURL = comps.url else {
            throw AuthError.supabaseError("Failed to construct sync URL")
        }
        
        let patch = ["energy_spent_lifetime": energy]
        let body = try JSONEncoder().encode(patch)
        
        let (_, http) = try await makeJSONRequest(
            url: finalURL,
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
            print("✅ Stats synced to Supabase: energy=\(energy)")
        }
    }
    
    // MARK: - Energy Balance Logging
    
    /// Logs lifetime energy spent to Supabase
    func logEnergyState(energySpent: Int) async {
        guard isAuthenticated,
              let userId = currentUser?.id,
              let session = loadStoredSession() else {
            print("📊 Energy log skipped: not authenticated or no session")
            return
        }
        
        print("📊 Logging energy spent: \(energySpent)")
        
        do {
            let cfg = try SupabaseConfig.load()
            let usersURL = cfg.baseURL.appendingPathComponent("rest/v1/users")
            guard var comps = URLComponents(url: usersURL, resolvingAgainstBaseURL: false) else {
                print("❌ Invalid users URL")
                return
            }
            comps.queryItems = [URLQueryItem(name: "id", value: "eq.\(userId)")]
            
            guard let finalURL = comps.url else {
                print("❌ Failed to construct energy log URL")
                return
            }
            
            let patch = SupabasePublicUserPatch(
                energySpentLifetime: energySpent
            )
            let body = try JSONEncoder().encode(patch)
            
            let (data, http) = try await makeJSONRequest(
                url: finalURL,
                method: "PATCH",
                headers: [
                    "apikey": cfg.anonKey,
                    "authorization": "Bearer \(session.accessToken)",
                    "prefer": "return=representation",
                    "accept": "application/json"
                ],
                body: body
            )
            
            if http.statusCode < 400 {
                print("✅ Energy state logged successfully")
            } else {
                let responseBody = String(data: data, encoding: .utf8) ?? "empty"
                print("❌ Energy state log failed: HTTP \(http.statusCode), body: \(responseBody)")
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
            guard var comps = URLComponents(url: usersURL, resolvingAgainstBaseURL: false) else {
                return true // Assume available on error
            }
            comps.queryItems = [
                URLQueryItem(name: "select", value: "id"),
                URLQueryItem(name: "nickname", value: "eq.\(nickname)"),
                URLQueryItem(name: "limit", value: "1")
            ]
            
            guard let finalURL = comps.url else {
                return true // Assume available on error
            }
            
            var request = URLRequest(url: finalURL)
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            let (data, httpResponse) = try await network.data(for: request)
            
            guard httpResponse.statusCode == 200 else {
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
    
    private func patchUserProfile(session: SupabaseSessionResponse, userId: String, nickname: String?, country: String?, avatarUrl: String? = nil) async throws {
        let cfg = try SupabaseConfig.load()
        let usersURL = cfg.baseURL.appendingPathComponent("rest/v1/users")
        guard var comps = URLComponents(url: usersURL, resolvingAgainstBaseURL: false) else {
            throw AuthError.supabaseError("Invalid users URL")
        }
        comps.queryItems = [URLQueryItem(name: "id", value: "eq.\(userId)")]
        
        guard let finalURL = comps.url else {
            throw AuthError.supabaseError("Failed to construct profile URL")
        }
        
        let patch = SupabasePublicUserPatch(nickname: nickname, country: country, avatarUrl: avatarUrl)
        let body = try JSONEncoder().encode(patch)
        
        print("🔄 PATCH profile: userId=\(userId), nickname=\(nickname ?? "nil"), country=\(country ?? "nil"), avatarUrl=\(avatarUrl ?? "nil")")
        print("🔄 PATCH URL: \(finalURL.absoluteString)")
        
        let (data, http) = try await makeJSONRequest(
            url: finalURL,
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
    
    // MARK: - Supabase Storage (Avatars)
    
    /// Uploads avatar image to Supabase Storage and returns the public URL
    private func uploadAvatarToStorage(session: SupabaseSessionResponse, userId: String, imageData: Data) async throws -> String {
        let cfg = try SupabaseConfig.load()
        
        // Storage endpoint: /storage/v1/object/avatars/{userId}.jpg
        let fileName = "\(userId).jpg"
        let storageURL = cfg.baseURL
            .appendingPathComponent("storage/v1/object/avatars")
            .appendingPathComponent(fileName)
        
        print("📸 Uploading avatar to: \(storageURL.absoluteString)")
        
        var request = URLRequest(url: storageURL)
        request.httpMethod = "POST"
        request.httpBody = imageData
        request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "content-type")
        request.setValue("true", forHTTPHeaderField: "x-upsert") // Overwrite if exists
        
        let (data, http) = try await network.data(for: request)
        
        let responseString = String(data: data, encoding: .utf8) ?? "(empty)"
        print("📸 Upload response: status=\(http.statusCode), body=\(responseString)")
        
        if http.statusCode >= 400 {
            throw AuthError.supabaseError("Avatar upload failed: \(responseString)")
        }
        
        // Return public URL
        let publicURL = cfg.baseURL
            .appendingPathComponent("storage/v1/object/public/avatars")
            .appendingPathComponent(fileName)
        
        return publicURL.absoluteString
    }
    
    /// Deletes avatar from Supabase Storage
    private func deleteAvatarFromStorage(session: SupabaseSessionResponse, userId: String) async throws {
        let cfg = try SupabaseConfig.load()
        
        let fileName = "\(userId).jpg"
        let storageURL = cfg.baseURL
            .appendingPathComponent("storage/v1/object/avatars")
            .appendingPathComponent(fileName)
        
        var request = URLRequest(url: storageURL)
        request.httpMethod = "DELETE"
        request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "authorization")
        
        let (_, http) = try await network.data(for: request)
        
        // 404 is OK - file might not exist
        if http.statusCode >= 400 && http.statusCode != 404 {
            print("⚠️ Avatar delete failed with status: \(http.statusCode)")
        }
    }
    
    /// Downloads avatar from URL
    private func downloadAvatar(from url: URL) async throws -> Data {
        let (data, http) = try await network.data(from: url)
        guard http.statusCode < 400 else {
            throw AuthError.supabaseError("Failed to download avatar")
        }
        return data
    }
    
    // MARK: - Fetch all users for Resistance screen
    
    /// Public user info for Resistance display (no sensitive data)
    struct ResistanceUser: Identifiable {
        let id: String
        let nickname: String
        let energySpentLifetime: Int
    }
    
    /// Fetches list of users from Supabase for Resistance screen (randomized, limited)
    func fetchResistanceUsers(limit: Int = 20) async throws -> [ResistanceUser] {
        let cfg = try SupabaseConfig.load()
        let usersURL = cfg.baseURL.appendingPathComponent("rest/v1/users")
        guard var comps = URLComponents(url: usersURL, resolvingAgainstBaseURL: false) else {
            throw AuthError.supabaseError("Invalid users URL")
        }
        comps.queryItems = [
            URLQueryItem(name: "select", value: "id,nickname,energy_spent_lifetime"),
            URLQueryItem(name: "nickname", value: "neq."),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        
        guard let finalURL = comps.url else {
            throw AuthError.supabaseError("Failed to construct users list URL")
        }
        
        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        
        let (data, http) = try await network.data(for: request)
        guard http.statusCode < 400 else {
            throw AuthError.supabaseError("Failed to fetch users")
        }
        
        let rows = try supabaseJSONDecoder().decode([ResistanceUserRow].self, from: data)
        return rows.shuffled().compactMap { row in
            guard let nick = row.nickname, !nick.isEmpty else { return nil }
            return ResistanceUser(id: row.id, nickname: nick, energySpentLifetime: row.energySpentLifetime ?? 0)
        }
    }
    
    private struct ResistanceUserRow: Codable {
        let id: String
        let nickname: String?
        let energySpentLifetime: Int?
        
        enum CodingKeys: String, CodingKey {
            case id
            case nickname
            case energySpentLifetime = "energy_spent_lifetime"
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
    let avatarUrl: String?
    let createdAt: Date
    let isBanned: Bool
    let banReason: String?
    let banUntil: Date?
    let energySpentLifetime: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case nickname
        case country
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
        case isBanned = "is_banned"
        case banReason = "ban_reason"
        case banUntil = "ban_until"
        case energySpentLifetime = "energy_spent_lifetime"
    }
}

private struct SupabasePublicUserPatch: Codable {
    let nickname: String?
    let country: String?
    let avatarUrl: String?
    let energySpentLifetime: Int?
    let lastSyncAt: String?
    
    enum CodingKeys: String, CodingKey {
        case nickname
        case country
        case avatarUrl = "avatar_url"
        case energySpentLifetime = "energy_spent_lifetime"
        case lastSyncAt = "last_sync_at"
    }
    
    init(nickname: String? = nil, country: String? = nil, avatarUrl: String? = nil, energySpentLifetime: Int? = nil) {
        self.nickname = nickname
        self.country = country
        self.avatarUrl = avatarUrl
        self.energySpentLifetime = energySpentLifetime
        self.lastSyncAt = ISO8601DateFormatter().string(from: Date())
    }
}
