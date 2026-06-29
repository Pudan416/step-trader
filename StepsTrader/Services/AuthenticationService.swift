import Foundation
import AuthenticationServices
import SwiftUI
import CryptoKit
import Security

// MARK: - Authentication Service
//
// `AppUser` model lives in AppUser.swift; the auth error enum, Keychain session
// store and Supabase DTOs live in AuthSupportTypes.swift; the low-level
// Supabase REST calls live in AuthenticationService+SupabaseREST.swift. (§9.2)

@MainActor
class AuthenticationService: NSObject, ObservableObject {
    
    static let shared = AuthenticationService()
    // `internal` (not private) so the +SupabaseREST extension can reach it. (§9.2)
    let network = NetworkClient.shared

    /// Weak reference set by AppModel on init so post-login can trigger a full sync.
    weak var postLoginSyncModel: AppModel?

    @Published var currentUser: AppUser?
    @Published var isAuthenticated: Bool = false
    @Published var isAnonymous: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String?

    var hasAppleAccount: Bool { isAuthenticated && !isAnonymous }
    
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

    /// Returns a valid (possibly refreshed) access token, refreshing via GoTrue if expired.
    /// Use this instead of `accessToken` for any Supabase API call that can wait for a refresh.
    func freshAccessToken() async -> String? {
        guard let session = loadStoredSession() else { return nil }
        guard let valid = try? await ensureValidSession(session) else { return session.accessToken }
        if valid.accessToken != session.accessToken {
            storeSession(valid)
        }
        return valid.accessToken
    }
    
    // Auth data intentionally stored in .standard — not shared with extensions.
    // Avatar bytes live on disk (Documents dir) to avoid bloating UserDefaults.
    private let userDefaultsKey = "supabaseSession_v1"
    private let avatarDefaultsPrefix = "userAvatarData_v1_"
    private let appleNamePrefix = "appleDisplayName_v1_"
    private let customNicknamePrefix = "hasCustomNickname_v1_"
    /// UserDefaults key for the APNs hex device token cached by `AppDelegate.
    /// application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    /// `signOut` / `deleteAccount` read this so they can call
    /// `removeDeviceToken` under the still-valid session bearer before
    /// wiping the keychain entry. (§5.2)
    static let pushTokenStorageKey = "apns_device_token_v1"
    private var currentNonce: String?
    private var pendingContinuations: [CheckedContinuation<Void, Never>] = []

    /// Handle to the background work spawned after a successful sign-in
    /// (RC link + full Supabase sync). Stored so logout can cancel it
    /// before the late-arriving sync writes back to a stale `AppModel`.
    /// (§3.1)
    private var postLoginSyncTask: Task<Void, Never>?

    /// Handle to the in-flight sign-in flow itself (Apple → Supabase exchange,
    /// profile fetch, optimistic UI update). Cancellation here ensures that a
    /// sign-out racing with sign-in doesn't leave a partial-state user. (§3.1)
    private var signInTask: Task<Void, Never>?
    
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
        // Cancel any in-flight sign-in OR post-login work first so it can't
        // write back to AppModel after we've flipped the user-facing state. (§3.1)
        signInTask?.cancel()
        signInTask = nil
        postLoginSyncTask?.cancel()
        postLoginSyncTask = nil

        // Capture the bearer + userId BEFORE we clear the keychain — the push
        // token DELETE and any other authenticated cleanup need a still-valid
        // session. (§5.2)
        let pendingTeardown = capturePendingTeardown()

        if let userId = currentUser?.id {
            clearCachedProfile(for: userId)
        }
        clearStoredSession()
        currentUser = nil
        isAuthenticated = false
        isAnonymous = false

        Task { @MainActor in
            await Self.performTeardown(pendingTeardown)
        }
    }

    /// Snapshot of credentials and device-token needed to tear down the
    /// previous session AFTER the local keychain entry has been wiped. Pass
    /// to `performTeardown(_:)` from a detached `Task`.
    private struct PendingTeardown {
        let bearer: String
        let userId: String
        let deviceTokenHex: String?
    }

    private func capturePendingTeardown() -> PendingTeardown? {
        guard let session = loadStoredSession() else { return nil }
        let deviceToken = UserDefaults.standard.string(forKey: Self.pushTokenStorageKey)
        return PendingTeardown(
            bearer: session.accessToken,
            userId: session.user.id,
            deviceTokenHex: deviceToken
        )
    }

    /// Runs sign-out side-effects against the *previous* session's bearer.
    ///
    /// Order matters: we must delete the `device_tokens` row before RC logout
    /// because the DELETE call goes through PostgREST (RLS-checked against the
    /// captured bearer), while RC logout only touches the RevenueCat SDK.
    /// Both happen after the keychain has already been wiped — that's fine,
    /// the bearer JWT is still valid until its server-side expiry. (§5.1, §5.2)
    private static func performTeardown(_ pending: PendingTeardown?) async {
        if let pending {
            if let tokenHex = pending.deviceTokenHex {
                await SupabaseSyncService.shared.removeDeviceToken(
                    tokenHex,
                    bearer: pending.bearer,
                    userId: pending.userId
                )
            }
        }
        // Clear the cached APNs token regardless — a fresh registration
        // happens on the next launch via UIApplication.registerForRemoteNotifications.
        UserDefaults.standard.removeObject(forKey: pushTokenStorageKey)

        await SubscriptionStore.shared.logOut()
    }

    // MARK: - Anonymous Auth

    /// Creates a fresh anonymous Supabase session. Throws on any failure so
    /// the caller can surface a real error to the UI instead of leaving the
    /// app in a silently-unauthenticated state. (§5.3)
    private func signInAnonymously() async throws {
        let cfg = try SupabaseConfig.load()
        let url = cfg.baseURL.appendingPathComponent("auth/v1/signup")

        let (data, http) = try await makeJSONRequest(
            url: url,
            method: "POST",
            headers: [
                "apikey": cfg.anonKey,
                "authorization": "Bearer \(cfg.anonKey)"
            ],
            body: Data("{}".utf8)
        )

        guard http.statusCode < 400 else {
            let msg = String(data: data, encoding: .utf8) ?? "Anonymous sign-in failed"
            AppLogger.auth.error("🔐 Anonymous sign-in failed: status \(http.statusCode), body: \(msg.prefix(300))")
            throw AuthError.supabaseError("Anonymous sign-in failed (\(http.statusCode))")
        }

        let session = try supabaseDecoder.decode(SupabaseSessionResponse.self, from: data)
        storeSession(session)
        isAnonymous = session.user.isAnonymous

        applyCachedSessionState(
            userId: session.user.id,
            email: nil,
            createdAt: session.user.createdAt
        )

        AppLogger.auth.debug("🔐 Anonymous sign-in successful, userId: \(session.user.id.prefix(8))…")
    }
    
    /// Permanently deletes the user's account and all associated server-side data
    /// via Supabase Edge Function, then wipes local caches.
    func deleteAccount() async throws {
        guard let session = loadStoredSession() else {
            throw AuthError.supabaseError("No active session")
        }

        // Cancel any in-flight sign-in / post-login work — the user we'd be
        // syncing for is about to stop existing. (§3.1)
        signInTask?.cancel()
        signInTask = nil
        postLoginSyncTask?.cancel()
        postLoginSyncTask = nil

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
        let pendingTeardown = PendingTeardown(
            bearer: session.accessToken,
            userId: userId,
            deviceTokenHex: UserDefaults.standard.string(forKey: Self.pushTokenStorageKey)
        )

        clearStoredSession()
        clearCachedProfile(for: userId)
        storeAvatarData(nil, for: userId)
        UserDefaults.standard.removeObject(forKey: appleNamePrefix + userId)
        UserDefaults.standard.removeObject(forKey: customNicknamePrefix + userId)

        currentUser = nil
        isAuthenticated = false

        // §5.1 / §5.2: remove the push-token row and log out RevenueCat with
        // the captured bearer. The DELETE may 404 if the server-side cascade
        // (auth.users → public.users / device_tokens) already removed it —
        // that's fine, removeDeviceToken treats non-200 as best-effort.
        await Self.performTeardown(pendingTeardown)

        #if DEBUG
        AppLogger.auth.debug("🗑️ Account deleted successfully for user \(userId.prefix(8))…")
        #endif
    }
    
    /// Handle authorization result from SignInWithAppleButton
    func handleAuthorization(_ authorization: ASAuthorization) {
        AppLogger.auth.debug("🔐 handleAuthorization — credential type: \(String(describing: type(of: authorization.credential)))")
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            AppLogger.auth.error("🔐 handleAuthorization — invalid credential type")
            error = AuthError.invalidCredential.localizedDescription
            return
        }
        
        AppLogger.auth.debug("🔐 handleAuthorization — user: \(credential.user.prefix(8))…, email: \(credential.email ?? "nil"), hasFullName: \(credential.fullName != nil)")
        
        guard let nonce = currentNonce else {
            AppLogger.auth.error("🔐 handleAuthorization — missing nonce")
            error = "Missing nonce. Please try again."
            return
        }
        
        guard let identityToken = credential.identityToken,
              let idTokenString = String(data: identityToken, encoding: .utf8) else {
            AppLogger.auth.error("🔐 handleAuthorization — missing identity token (tokenData nil: \(credential.identityToken == nil))")
            error = "Missing identity token from Apple."
            return
        }
        
        AppLogger.auth.debug("🔐 handleAuthorization — got identity token (\(identityToken.count) bytes), nonce present, starting Supabase exchange")
        
        isLoading = true
        error = nil
        
        let appleFullName: String? = {
            guard let fn = credential.fullName else { return nil }
            let formatter = PersonNameComponentsFormatter()
            let formatted = formatter.string(from: fn).trimmingCharacters(in: .whitespacesAndNewlines)
            if !formatted.isEmpty { return formatted }
            let parts = [fn.givenName, fn.familyName].compactMap { $0 }.filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }()
        
        if let name = appleFullName {
            AppLogger.auth.debug("🔐 handleAuthorization — Apple provided fullName: \(name)")
        }
        
        // Replace any prior in-flight sign-in (e.g. user retried mid-flow) and
        // track the new one so signOut/deleteAccount can cancel it. The outer
        // Task inherits MainActor isolation from the enclosing @MainActor
        // class — no explicit `@MainActor in` annotation needed. (§3.1)
        signInTask?.cancel()
        signInTask = Task {
            do {
                AppLogger.auth.debug("🔐 supabaseSignInWithApple — starting token exchange")
                let session = try await self.supabaseSignInWithApple(idToken: idTokenString, nonce: nonce)
                guard !Task.isCancelled else {
                    AppLogger.auth.debug("🔐 Sign-in cancelled after token exchange — discarding session")
                    return
                }
                AppLogger.auth.debug("🔐 supabaseSignInWithApple — success, userId: \(session.user.id.prefix(8))…, expiresAt: \(session.expiresAt)")

                self.storeSession(session)
                self.isAnonymous = false
                if let name = appleFullName {
                    self.storeAppleDisplayName(name, for: session.user.id)
                }

                // Optimistic: token is valid — show logged-in UI before profile fetch finishes.
                self.applyCachedSessionState(
                    userId: session.user.id,
                    email: session.user.email,
                    createdAt: session.user.createdAt
                )
                self.currentNonce = nil
                self.isLoading = false
                AppLogger.auth.debug("🔐 Optimistic sign-in — isAuthenticated: \(self.isAuthenticated)")

                do {
                    AppLogger.auth.debug("🔐 loadCurrentUserFromSupabase — fetching profile")
                    try await self.loadCurrentUserFromSupabase(session: session)
                    guard !Task.isCancelled else { return }
                    AppLogger.auth.debug("🔐 loadCurrentUserFromSupabase — done, user: \(self.currentUser?.displayName ?? "nil")")

                    if let name = appleFullName {
                        await self.promoteAppleNameAsDefaultProfileNameIfNeeded(name, session: session)
                        guard !Task.isCancelled else { return }
                    }
                } catch {
                    if self.isSessionInvalidatingError(error) {
                        AppLogger.auth.error("🔐 Profile fetch invalidated session: \(error.localizedDescription)")
                        self.clearStoredSession()
                        self.clearCachedProfile(for: session.user.id)
                        self.currentUser = nil
                        self.isAuthenticated = false
                        self.error = error.localizedDescription
                        return
                    }
                    AppLogger.auth.warning("🔐 Profile refresh after sign-in deferred: \(error.localizedDescription)")
                    if let user = self.currentUser {
                        self.persistCachedProfile(user)
                    }
                }

                AppLogger.auth.debug("🔐 Sign in complete — isAuthenticated: \(self.isAuthenticated)")

                let uid = self.currentUser?.id ?? session.user.id
                // Replace any previously-running post-login task (e.g. a
                // re-sign-in before the previous sync settled). (§3.1)
                self.postLoginSyncTask?.cancel()
                self.postLoginSyncTask = Task { [weak self] in
                    AppLogger.auth.debug("🔐 Post-login — linking RC userId: \(uid.prefix(8))…")
                    await SubscriptionStore.shared.logIn(supabaseUserID: uid)
                    guard !Task.isCancelled else { return }
                    if let appModel = self?.postLoginSyncModel {
                        AppLogger.auth.debug("🔐 Post-login — starting full Supabase sync")
                        await SupabaseSyncService.shared.performFullSync(model: appModel)
                        AppLogger.auth.debug("🔐 Post-login — full sync finished")
                    }
                }
            } catch {
                AppLogger.auth.error("🔐 Sign in FAILED: \(error.localizedDescription)")
                self.isLoading = false
                self.error = error.localizedDescription
            }
        }
    }
    
    func checkAuthenticationState() async { await loadStoredSessionAndRefreshUser() }
    
    // MARK: - Input Validation

    private static let nicknameMaxLength = 30
    private static let nicknameAllowedPattern: NSRegularExpression? = try? NSRegularExpression(pattern: "^[\\p{L}\\p{N}\\s._\\-]+$")
    private static let countryCodePattern: NSRegularExpression? = try? NSRegularExpression(pattern: "^[A-Z]{2}$")

    private func sanitizedNickname(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return raw }
        let trimmed = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.nicknameMaxLength))
        guard !trimmed.isEmpty else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let pattern = Self.nicknameAllowedPattern,
              pattern.firstMatch(in: trimmed, range: range) != nil else {
            return nil
        }
        return trimmed
    }

    private func validatedCountry(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return raw }
        let upper = raw.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(upper.startIndex..., in: upper)
        guard let pattern = Self.countryCodePattern,
              pattern.firstMatch(in: upper, range: range) != nil else {
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
        setCurrentUserAndCache(user)
        
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
        setCurrentUserAndCache(user)
        
        guard let rawSession = loadStoredSession() else { return }
        let session = (try? await ensureValidSession(rawSession)) ?? rawSession
        if session.accessToken != rawSession.accessToken { storeSession(session) }

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
        AppLogger.auth.debug("🔐 configureAppleRequest — generating nonce")
        do {
            let nonce = try randomNonceString()
            currentNonce = nonce
            request.requestedScopes = [.email, .fullName]
            request.nonce = sha256(nonce)
            AppLogger.auth.debug("🔐 configureAppleRequest — nonce set, scopes: [email, fullName]")
        } catch {
            AppLogger.auth.error("🔐 configureAppleRequest — nonce generation failed: \(error.localizedDescription)")
            self.error = "Authentication setup failed. Please try again."
        }
    }
    
    private static func avatarFileURL(for userId: String) -> URL {
        URL.documentsDirectory.appending(path: "avatar_\(userId).png")
    }

    private func storeAvatarData(_ data: Data?, for userId: String) {
        let fileURL = Self.avatarFileURL(for: userId)
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
    
    func loadAvatarData(for userId: String) -> Data? {
        let fileURL = Self.avatarFileURL(for: userId)
        if let data = try? Data(contentsOf: fileURL) {
            return data
        }
        let key = avatarDefaultsPrefix + userId
        if let legacyData = UserDefaults.standard.data(forKey: key) {
            do {
                try legacyData.write(to: fileURL, options: .atomic)
                // Only drop the legacy copy once the disk write succeeded —
                // otherwise it stays as the source for the next migration attempt.
                UserDefaults.standard.removeObject(forKey: key)
            } catch {
                AppLogger.auth.error("Failed to migrate avatar to disk: \(error.localizedDescription)")
            }
            return legacyData
        }
        return nil
    }
    
    func storeAppleDisplayName(_ name: String, for userId: String) {
        UserDefaults.standard.set(name, forKey: appleNamePrefix + userId)
    }
    
    func loadAppleDisplayName(for userId: String) -> String? {
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
                setCurrentUserAndCache(user)
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
            setCurrentUserAndCache(user)
        }

        do {
            try await patchUserProfile(session: session, userId: user.id, nickname: trimmed, country: user.country)
        } catch {
            // Keep local Apple name for UI even if profile PATCH fails.
            AppLogger.auth.error("⚠️ Failed to promote Apple name as nickname: \(error.localizedDescription)")
        }
    }
    
    func loadHasCustomNickname(for userId: String) -> Bool {
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

        // Prefer Keychain, but fall back to a retained legacy UserDefaults copy when
        // the Keychain is unavailable (e.g. device still locked right after a reboot) so a
        // failed/locked read doesn't sign out a user whose session survived in the migration shadow.
        guard let data = SessionKeychain.loadSession() ?? UserDefaults.standard.data(forKey: userDefaultsKey) else { return nil }
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
            AppLogger.auth.debug("🔐 No stored session found in Keychain, signing in anonymously")
            do {
                try await signInAnonymously()
            } catch {
                // Surface to the UI so the user knows something went wrong
                // instead of seeing a permanently-empty app. (§5.3)
                self.error = String(
                    localized: "Couldn't initialise your account. Please check your connection and try again.",
                    comment: "Auth – anonymous signup failure surfaced on cold launch"
                )
            }
            return
        }
        isAnonymous = session.user.isAnonymous

        #if DEBUG
        AppLogger.auth.debug("🔐 Found stored session, user: \(session.user.id.prefix(8))…, expires: \(session.expiresAt)")
        #endif

        // Show logged-in UI immediately; refresh profile/token in background.
        reapplyCachedState(for: session)

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
            // Re-link RC on cold launch when we already have a session.
            if let uid = currentUser?.id {
                await SubscriptionStore.shared.logIn(supabaseUserID: uid)
            }
        } catch {
            if isSessionInvalidatingError(error) {
                AppLogger.auth.error("🔐 Session invalid — signing out locally: \(error.localizedDescription)")
                clearStoredSession()
                clearCachedProfile(for: session.user.id)
                currentUser = nil
                isAuthenticated = false
            } else {
                AppLogger.auth.warning("🔐 Session refresh deferred (offline/transient): \(error.localizedDescription)")
                if currentUser == nil {
                    reapplyCachedState(for: session)
                }
                isAuthenticated = currentUser != nil
            }
        }
    }

    /// Single source of truth for restoring optimistic logged-in UI from a
    /// (possibly-stale) cached session. Both the cold-launch path and the
    /// transient-error recovery branch route through here. (§9.4)
    private func reapplyCachedState(for session: SupabaseSessionResponse) {
        applyCachedSessionState(
            userId: session.user.id,
            email: session.user.email,
            createdAt: session.user.createdAt
        )
    }
    
    // MARK: - Supabase REST
    // SupabaseConfig is now defined in NetworkClient.swift
    
    // `internal` (not private) so the +SupabaseREST extension can reach it. (§9.2)
    lazy var supabaseDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private lazy var supabaseEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    
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
