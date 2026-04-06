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
    
    var appleDisplayName: String?
    var hasSetCustomNickname: Bool
    
    var displayName: String {
        // Explicitly user-chosen nickname wins
        if hasSetCustomNickname, let nickname = nickname, !nickname.isEmpty {
            return nickname
        }
        // Apple ID full name as default
        if let appleDisplayName = appleDisplayName, !appleDisplayName.isEmpty {
            return appleDisplayName
        }
        // Auto-generated nickname or email fallback
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
    
    var countryFlagEmoji: String? {
        guard let countryCode = country, !countryCode.isEmpty else { return nil }
        let result = countryFlag(countryCode)
        return result.isEmpty ? nil : result
    }
    
    init(id: String, email: String?, nickname: String? = nil, country: String? = nil, avatarData: Data? = nil, createdAt: Date, appleDisplayName: String? = nil, hasSetCustomNickname: Bool = false) {
        self.id = id
        self.email = email
        self.nickname = nickname
        self.country = country
        self.avatarData = avatarData
        self.createdAt = createdAt
        self.appleDisplayName = appleDisplayName
        self.hasSetCustomNickname = hasSetCustomNickname
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
        guard let data = SessionKeychain.loadSession() else { return nil }
        if let session = try? supabaseDecoder.decode(SupabaseSessionResponse.self, from: data) {
            return session.accessToken
        }
        if let session = try? JSONDecoder().decode(SupabaseSessionResponse.self, from: data) {
            return session.accessToken
        }
        return nil
    }
    
    // Auth data intentionally stored in .standard — not shared with extensions.
    // Avatar bytes live on disk (Documents dir) to avoid bloating UserDefaults.
    private let userDefaultsKey = "supabaseSession_v1"
    private let avatarDefaultsPrefix = "userAvatarData_v1_"
    private let appleNamePrefix = "appleDisplayName_v1_"
    private let customNicknamePrefix = "hasCustomNickname_v1_"
    private var currentNonce: String?
    private var pendingContinuations: [CheckedContinuation<Void, Never>] = []
    
    override init() {
        super.init()
        Task { @MainActor in
            await loadStoredSessionAndRefreshUser()
            isInitialized = true
            AppLogger.auth.debug("AuthenticationService initialized: isAuthenticated=\(self.isAuthenticated)")
            for continuation in pendingContinuations {
                continuation.resume()
            }
            pendingContinuations.removeAll()
        }
    }
    
    /// Wait for the initial session restore to complete.
    /// The check-and-append is atomic within a single MainActor turn,
    /// preventing the continuation from being appended after init already drained the array.
    func waitForInitialization() async {
        guard !isInitialized else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if isInitialized {
                continuation.resume()
            } else {
                pendingContinuations.append(continuation)
            }
        }
    }
    
    // MARK: - Public Methods
    
    func signOut() {
        clearStoredSession()
        currentUser = nil
        isAuthenticated = false
    }
    
    /// Permanently deletes the user's account and all associated server-side data
    /// via Supabase Edge Function, then wipes local caches.
    func deleteAccount() async throws {
        guard let session = loadStoredSession() else {
            throw AuthError.supabaseError("No active session")
        }
        
        let cfg = try SupabaseConfig.load()
        let url = cfg.baseURL.appendingPathComponent("functions/v1/delete-user")
        
        let (data, http) = try await makeJSONRequest(
            url: url,
            method: "POST",
            headers: [
                "apikey": cfg.anonKey,
                "authorization": "Bearer \(session.accessToken)"
            ]
        )
        
        if http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "Account deletion failed"
            throw AuthError.supabaseError(msg)
        }
        
        let userId = session.user.id
        clearStoredSession()
        storeAvatarData(nil, for: userId)
        UserDefaults.standard.removeObject(forKey: appleNamePrefix + userId)
        UserDefaults.standard.removeObject(forKey: customNicknamePrefix + userId)
        
        currentUser = nil
        isAuthenticated = false
        
        #if DEBUG
        AppLogger.auth.debug("🗑️ Account deleted successfully for user \(userId.prefix(8))…")
        #endif
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
        
        // Apple only delivers fullName on the very first sign-in — capture it now
        let appleFullName: String? = {
            guard let fn = credential.fullName else { return nil }
            let formatter = PersonNameComponentsFormatter()
            let formatted = formatter.string(from: fn).trimmingCharacters(in: .whitespacesAndNewlines)
            if !formatted.isEmpty { return formatted }
            let parts = [fn.givenName, fn.familyName].compactMap { $0 }.filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }()
        
        Task { @MainActor in
            defer { self.isLoading = false }
            do {
                let session = try await self.supabaseSignInWithApple(idToken: idTokenString, nonce: nonce)
                self.storeSession(session)
                // Persist Apple name keyed by user ID (never overwrite with nil)
                if let name = appleFullName {
                    self.storeAppleDisplayName(name, for: session.user.id)
                }
                try await self.loadCurrentUserFromSupabase(session: session)
                if let name = appleFullName {
                    await self.promoteAppleNameAsDefaultProfileNameIfNeeded(name, session: session)
                }
                self.isAuthenticated = (self.currentUser != nil)
                self.currentNonce = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
    
    func checkAuthenticationState() async { await loadStoredSessionAndRefreshUser() }
    
    // MARK: - Input Validation

    private static let nicknameMaxLength = 30
    private static let nicknameAllowedPattern = try! NSRegularExpression(pattern: "^[\\p{L}\\p{N}\\s._\\-]+$")
    private static let countryCodePattern = try! NSRegularExpression(pattern: "^[A-Z]{2}$")

    private func sanitizedNickname(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return raw }
        let trimmed = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.nicknameMaxLength))
        guard !trimmed.isEmpty else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard Self.nicknameAllowedPattern.firstMatch(in: trimmed, range: range) != nil else {
            return nil
        }
        return trimmed
    }

    private func validatedCountry(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return raw }
        let upper = raw.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(upper.startIndex..., in: upper)
        guard Self.countryCodePattern.firstMatch(in: upper, range: range) != nil else {
            return nil
        }
        return upper
    }

    // MARK: - Profile Update Methods
    
    func updateProfile(nickname: String?, country: String?, avatarData: Data?) {
        guard var user = currentUser else { return }
        let nickname = sanitizedNickname(nickname)
        let country = validatedCountry(country)
        
        // Store avatar locally for immediate display
        user.avatarData = avatarData
        storeAvatarData(avatarData, for: user.id)
        
        // Mark as explicitly set if a non-empty nickname was provided
        if let nick = nickname, !nick.isEmpty {
            user.hasSetCustomNickname = true
            storeHasCustomNickname(true, for: user.id)
        }
        
        // Update local user immediately for responsive UI
        user.nickname = nickname
        user.country = country
        currentUser = user
        
        Task { @MainActor in
            do {
                guard let session = loadStoredSession() else { return }
                
                if let data = avatarData, !data.isEmpty {
                    _ = try await uploadAvatarToStorage(session: session, userId: user.id, imageData: data)
                } else if avatarData == nil {
                    try? await deleteAvatarFromStorage(session: session, userId: user.id)
                }
                
                try await patchUserProfile(session: session, userId: user.id, nickname: nickname, country: country)
                // Refresh from DB to keep canonical values
                try await loadCurrentUserFromSupabase(session: session)
            } catch {
                self.error = error.localizedDescription
                AppLogger.auth.error("❌ Profile update failed: \(error.localizedDescription)")
            }
        }
    }

    func updateProfile(nickname: String?, country: String?) {
        updateProfile(nickname: nickname, country: country, avatarData: currentUser?.avatarData)
    }
    
    /// Async version for awaiting completion
    func updateProfileAsync(nickname: String?, country: String?, avatarData: Data?) async throws {
        guard var user = currentUser else { return }
        let nickname = sanitizedNickname(nickname)
        let country = validatedCountry(country)

        // Store avatar locally
        user.avatarData = avatarData
        storeAvatarData(avatarData, for: user.id)
        
        // Mark as explicitly set if a non-empty nickname was provided
        if let nick = nickname, !nick.isEmpty {
            user.hasSetCustomNickname = true
            storeHasCustomNickname(true, for: user.id)
        }
        
        // Update local user immediately
        user.nickname = nickname
        user.country = country
        currentUser = user
        
        guard let session = loadStoredSession() else { return }
        
        if let data = avatarData, !data.isEmpty {
            _ = try await uploadAvatarToStorage(session: session, userId: user.id, imageData: data)
        } else if avatarData == nil {
            try? await deleteAvatarFromStorage(session: session, userId: user.id)
        }
        
        try await patchUserProfile(session: session, userId: user.id, nickname: nickname, country: country)
        try await loadCurrentUserFromSupabase(session: session)
    }
    
    // MARK: - Private Methods
    
    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        do {
            let nonce = try randomNonceString()
            currentNonce = nonce
            request.requestedScopes = [.email, .fullName]
            request.nonce = sha256(nonce)
        } catch {
            AppLogger.auth.error("Failed to generate nonce: \(error.localizedDescription)")
            self.error = "Authentication setup failed. Please try again."
        }
    }
    
    private static func avatarFileURL(for userId: String) -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docs.appendingPathComponent("avatar_\(userId).png")
    }

    private func storeAvatarData(_ data: Data?, for userId: String) {
        guard let fileURL = Self.avatarFileURL(for: userId) else {
            AppLogger.auth.error("Failed to resolve documents directory for avatar storage")
            return
        }
        if let data, !data.isEmpty {
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                AppLogger.auth.error("Failed to write avatar to disk: \(error.localizedDescription)")
            }
        } else {
            try? FileManager.default.removeItem(at: fileURL)
        }
        UserDefaults.standard.removeObject(forKey: avatarDefaultsPrefix + userId)
    }
    
    private func loadAvatarData(for userId: String) -> Data? {
        guard let fileURL = Self.avatarFileURL(for: userId) else { return nil }
        if let data = try? Data(contentsOf: fileURL) {
            return data
        }
        let key = avatarDefaultsPrefix + userId
        if let legacyData = UserDefaults.standard.data(forKey: key) {
            do {
                try legacyData.write(to: fileURL, options: .atomic)
            } catch {
                AppLogger.auth.error("Failed to migrate avatar to disk: \(error.localizedDescription)")
            }
            UserDefaults.standard.removeObject(forKey: key)
            return legacyData
        }
        return nil
    }
    
    func storeAppleDisplayName(_ name: String, for userId: String) {
        UserDefaults.standard.set(name, forKey: appleNamePrefix + userId)
    }
    
    private func loadAppleDisplayName(for userId: String) -> String? {
        UserDefaults.standard.string(forKey: appleNamePrefix + userId)
    }
    
    private func storeHasCustomNickname(_ value: Bool, for userId: String) {
        UserDefaults.standard.set(value, forKey: customNicknamePrefix + userId)
    }

    private func promoteAppleNameAsDefaultProfileNameIfNeeded(_ name: String, session: SupabaseSessionResponse) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var user = currentUser else { return }

        // Never override a nickname the user explicitly chose.
        guard !user.hasSetCustomNickname else {
            if user.appleDisplayName != trimmed {
                user.appleDisplayName = trimmed
                currentUser = user
            }
            return
        }

        var didMutateLocalUser = false
        if user.appleDisplayName != trimmed {
            user.appleDisplayName = trimmed
            didMutateLocalUser = true
        }
        if user.nickname != trimmed {
            user.nickname = trimmed
            didMutateLocalUser = true
        }
        if didMutateLocalUser {
            currentUser = user
        }

        do {
            try await patchUserProfile(session: session, userId: user.id, nickname: trimmed, country: user.country)
        } catch {
            // Keep local Apple name for UI even if profile PATCH fails.
            AppLogger.auth.error("⚠️ Failed to promote Apple name as nickname: \(error.localizedDescription)")
        }
    }
    
    private func loadHasCustomNickname(for userId: String) -> Bool {
        UserDefaults.standard.bool(forKey: customNicknamePrefix + userId)
    }
    
    private func loadStoredSession() -> SupabaseSessionResponse? {
        // One-time migration: move session from UserDefaults to Keychain
        if let legacyData = UserDefaults.standard.data(forKey: userDefaultsKey) {
            let saved = SessionKeychain.saveSession(legacyData)
            if saved {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
                AppLogger.auth.debug("🔐 Migrated session from UserDefaults to Keychain")
            } else {
                AppLogger.auth.error("🔐 Keychain save failed during migration — keeping UserDefaults copy to prevent session loss")
            }
        }

        guard let data = SessionKeychain.loadSession() else { return nil }
        if let s = try? supabaseDecoder.decode(SupabaseSessionResponse.self, from: data) {
            return s
        }
        if let s = try? JSONDecoder().decode(SupabaseSessionResponse.self, from: data) {
            return s
        }
        return nil
    }
    
    private func storeSession(_ session: SupabaseSessionResponse) {
        guard let data = try? supabaseEncoder.encode(session) else { return }
        SessionKeychain.saveSession(data)
    }
    
    private func clearStoredSession() {
        SessionKeychain.deleteSession()
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    private func loadStoredSessionAndRefreshUser() async {
        AppLogger.auth.debug("🔐 loadStoredSessionAndRefreshUser called")
        guard let session = loadStoredSession() else {
            AppLogger.auth.debug("🔐 No stored session found in Keychain")
            currentUser = nil
            isAuthenticated = false
            return
        }
        
        #if DEBUG
        AppLogger.auth.debug("🔐 Found stored session, user: \(session.user.id.prefix(8))…, expires: \(session.expiresAt)")
        #endif
        
        do {
            let validSession = try await ensureValidSession(session)
            AppLogger.auth.debug("🔐 Session validated/refreshed successfully")
            if validSession.accessToken != session.accessToken {
                AppLogger.auth.debug("🔐 Token was refreshed, storing new session")
                storeSession(validSession)
            }
            try await loadCurrentUserFromSupabase(session: validSession)
            isAuthenticated = (currentUser != nil)
            #if DEBUG
            AppLogger.auth.debug("🔐 Final state: isAuthenticated=\(self.isAuthenticated)")
            #endif
        } catch {
            AppLogger.auth.error("🔐 Session restore failed: \(error.localizedDescription)")
            // Session likely invalid/revoked
            clearStoredSession()
            currentUser = nil
            isAuthenticated = false
        }
    }
    
    // MARK: - Supabase REST
    // SupabaseConfig is now defined in NetworkClient.swift
    
    private lazy var supabaseDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private lazy var supabaseEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    
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
        
        return try supabaseDecoder.decode(SupabaseSessionResponse.self, from: data)
    }
    
    private func ensureValidSession(_ session: SupabaseSessionResponse) async throws -> SupabaseSessionResponse {
        let threshold = Date().addingTimeInterval(AppConstants.Timing.sessionRefreshThreshold)
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
        
        return try supabaseDecoder.decode(SupabaseSessionResponse.self, from: data)
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
            URLQueryItem(name: "select", value: "id,email,nickname,country,created_at,is_banned,ban_reason,ban_until"),
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
        
        let rows = try supabaseDecoder.decode([SupabasePublicUserRow].self, from: data)
        guard let row = rows.first else {
            // Trigger might not have created the row yet; fallback to auth user.
            // Do not auto-generate nicknames; prefer Apple name or email fallback in UI.
            currentUser = AppUser(
                id: session.user.id,
                email: session.user.email,
                nickname: nil,
                country: nil,
                avatarData: loadAvatarData(for: session.user.id),
                createdAt: session.user.createdAt ?? Date(),
                appleDisplayName: loadAppleDisplayName(for: session.user.id),
                hasSetCustomNickname: loadHasCustomNickname(for: session.user.id)
            )
            return
        }
        
        let avatarData = loadAvatarData(for: row.id)
        
        if row.isBanned {
            let until = row.banUntil
            if until == nil || (until.map { $0 > Date() } ?? true) {
                currentUser = AppUser(
                    id: row.id,
                    email: row.email,
                    nickname: row.nickname,
                    country: row.country,
                    avatarData: avatarData,
                    createdAt: row.createdAt,
                    appleDisplayName: loadAppleDisplayName(for: row.id),
                    hasSetCustomNickname: loadHasCustomNickname(for: row.id)
                )
                isAuthenticated = true
                error = "Account is banned."
                return
            }
        }
        
        currentUser = AppUser(
            id: row.id,
            email: row.email,
            nickname: row.nickname,
            country: row.country,
            avatarData: avatarData,
            createdAt: row.createdAt,
            appleDisplayName: loadAppleDisplayName(for: row.id),
            hasSetCustomNickname: loadHasCustomNickname(for: row.id)
        )
    }
    
    private func patchUserProfile(session: SupabaseSessionResponse, userId: String, nickname: String?, country: String?) async throws {
        let cfg = try SupabaseConfig.load()
        let usersURL = cfg.baseURL.appendingPathComponent("rest/v1/users")
        guard var comps = URLComponents(url: usersURL, resolvingAgainstBaseURL: false) else {
            throw AuthError.supabaseError("Invalid users URL")
        }
        comps.queryItems = [URLQueryItem(name: "id", value: "eq.\(userId)")]
        
        guard let finalURL = comps.url else {
            throw AuthError.supabaseError("Failed to construct profile URL")
        }
        
        let patch = SupabasePublicUserPatch(nickname: nickname, country: country)
        let body = try JSONEncoder().encode(patch)
        
        #if DEBUG
        AppLogger.auth.debug("🔄 PATCH profile: userId=\(userId.prefix(8))…, nickname=\(nickname != nil ? "<set>" : "nil"), country=\(country ?? "nil")")
        #endif
        
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
        #if DEBUG
        AppLogger.auth.debug("🔄 PATCH response: status=\(http.statusCode), body=\(responseString)")
        #endif
        
        if http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "Failed to update profile"
            throw AuthError.supabaseError(msg)
        }
        
        // Check if any rows were updated (empty array means RLS blocked or row doesn't exist)
        if responseString == "[]" {
            AppLogger.auth.debug("⚠️ PATCH returned empty array - check RLS policies or if user row exists")
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
        
        #if DEBUG
        AppLogger.auth.debug("📸 Uploading avatar to: \(storageURL.absoluteString)")
        #endif
        
        var request = URLRequest(url: storageURL)
        request.httpMethod = "POST"
        request.httpBody = imageData
        request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "content-type")
        request.setValue("true", forHTTPHeaderField: "x-upsert") // Overwrite if exists
        
        let (data, http) = try await network.data(for: request)
        
        #if DEBUG
        let responseString = String(data: data, encoding: .utf8) ?? "(empty)"
        AppLogger.auth.debug("📸 Upload response: status=\(http.statusCode), body=\(responseString)")
        #endif
        
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
            AppLogger.auth.error("⚠️ Avatar delete failed with status: \(http.statusCode)")
        }
    }
    
    // MARK: - Fetch all users for Resistance screen
    
    struct ResistanceUser: Identifiable {
        let id: String
        let nickname: String
    }
    
    func fetchResistanceUsers(limit: Int = 20) async throws -> [ResistanceUser] {
        guard let session = loadStoredSession() else {
            throw AuthError.supabaseError("No active session")
        }

        let cfg = try SupabaseConfig.load()
        let usersURL = cfg.baseURL.appendingPathComponent("rest/v1/users")
        guard var comps = URLComponents(url: usersURL, resolvingAgainstBaseURL: false) else {
            throw AuthError.supabaseError("Invalid users URL")
        }
        comps.queryItems = [
            URLQueryItem(name: "select", value: "id,nickname"),
            URLQueryItem(name: "nickname", value: "neq."),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        
        guard let finalURL = comps.url else {
            throw AuthError.supabaseError("Failed to construct users list URL")
        }
        
        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        
        let (data, http) = try await network.data(for: request)
        guard http.statusCode < 400 else {
            throw AuthError.supabaseError("Failed to fetch users")
        }
        
        let rows = try supabaseDecoder.decode([ResistanceUserRow].self, from: data)
        return rows.shuffled().compactMap { row in
            guard let nick = row.nickname, !nick.isEmpty else { return nil }
            return ResistanceUser(id: row.id, nickname: nick)
        }
    }
    
    private struct ResistanceUserRow: Codable {
        let id: String
        let nickname: String?
    }
    
    // MARK: - Nonce helpers (Apple Sign In)
    
    private func randomNonceString(length: Int = 32) throws -> String {
        precondition(length > 0)
        let charset: [Character] =
        Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if errorCode != errSecSuccess {
                throw NSError(domain: "AuthenticationService", code: Int(errorCode),
                              userInfo: [NSLocalizedDescriptionKey: "SecRandomCopyBytes failed with OSStatus \(errorCode)"])
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

// MARK: - Session Keychain Helper

private enum SessionKeychain {
    private static let service = "com.stepstrader.supabase-session"
    private static let account = "session_v1"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    @discardableResult
    static func saveSession(_ data: Data) -> Bool {
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
            return updateStatus == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func loadSession() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func deleteSession() {
        SecItemDelete(baseQuery as CFDictionary)
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
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case nickname
        case country
        case createdAt = "created_at"
        case isBanned = "is_banned"
        case banReason = "ban_reason"
        case banUntil = "ban_until"
    }
}

private struct SupabasePublicUserPatch: Codable {
    let nickname: String?
    let country: String?
    
    init(nickname: String? = nil, country: String? = nil) {
        self.nickname = nickname
        self.country = country
    }
}
