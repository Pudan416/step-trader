import Foundation

// MARK: - Supabase REST plumbing
//
// Extracted from AuthenticationService.swift (§9.2): the low-level HTTP calls
// against Supabase GoTrue (token exchange / refresh), PostgREST (profile read /
// patch) and Storage (avatar upload / delete). The service core keeps the
// auth-flow orchestration; this extension holds the request builders.
// `network` and `supabaseDecoder` live on the core class and are `internal`
// so these methods can reach them across files.

extension AuthenticationService {

    func makeJSONRequest(
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

    func supabaseSignInWithApple(idToken: String, nonce: String) async throws -> SupabaseSessionResponse {
        let cfg = try SupabaseConfig.load()
        AppLogger.auth.debug("🔐 supabaseSignInWithApple — posting to \(cfg.baseURL.host ?? "?")/auth/v1/token?grant_type=id_token")

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
        // Use existing session token (anonymous or otherwise) so GoTrue can
        // link the Apple identity to the current anonymous user.
        let authToken = self.accessToken ?? cfg.anonKey
        let (data, http) = try await makeJSONRequest(
            url: finalURL,
            method: "POST",
            headers: ["apikey": cfg.anonKey, "authorization": "Bearer \(authToken)"],
            body: body
        )

        AppLogger.auth.debug("🔐 supabaseSignInWithApple — response status: \(http.statusCode), body size: \(data.count) bytes")

        if http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "Supabase auth failed"
            AppLogger.auth.error("🔐 supabaseSignInWithApple — FAILED: status \(http.statusCode), body: \(msg.prefix(500))")
            throw AuthError.supabaseError(msg)
        }

        return try supabaseDecoder.decode(SupabaseSessionResponse.self, from: data)
    }

    func ensureValidSession(_ session: SupabaseSessionResponse) async throws -> SupabaseSessionResponse {
        let threshold = Date.now.addingTimeInterval(AppConstants.Timing.sessionRefreshThreshold)
        if session.expiresAt > threshold {
            AppLogger.auth.debug("🔐 ensureValidSession — token still valid (expires: \(session.expiresAt))")
            return session
        }

        AppLogger.auth.debug("🔐 ensureValidSession — token expired/expiring, refreshing")
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

        AppLogger.auth.debug("🔐 ensureValidSession — refresh response status: \(http.statusCode)")

        if http.statusCode == 401 || http.statusCode == 403 {
            AppLogger.auth.error("🔐 ensureValidSession — refresh rejected (\(http.statusCode))")
            throw AuthError.sessionExpired
        }
        if http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "Supabase refresh failed"
            AppLogger.auth.error("🔐 ensureValidSession — refresh FAILED: \(msg.prefix(300))")
            throw AuthError.supabaseError(msg)
        }

        AppLogger.auth.debug("🔐 ensureValidSession — token refreshed successfully")
        return try supabaseDecoder.decode(SupabaseSessionResponse.self, from: data)
    }

    func loadCurrentUserFromSupabase(session: SupabaseSessionResponse) async throws {
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

        if http.statusCode == 401 || http.statusCode == 403 {
            throw AuthError.sessionExpired
        }
        if http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "Failed to load profile"
            throw AuthError.supabaseError(msg)
        }

        let rows = try supabaseDecoder.decode([SupabasePublicUserRow].self, from: data)
        guard let row = rows.first else {
            // Trigger might not have created the row yet; fallback to auth user.
            // Do not auto-generate nicknames; prefer Apple name or email fallback in UI.
            setCurrentUserAndCache(minimalUser(
                userId: session.user.id,
                email: session.user.email,
                createdAt: session.user.createdAt
            ))
            return
        }

        let avatarData = loadAvatarData(for: row.id)

        if row.isBanned {
            let until = row.banUntil
            if until == nil || (until.map { $0 > Date.now } ?? true) {
                setCurrentUserAndCache(AppUser(
                    id: row.id,
                    email: row.email,
                    nickname: row.nickname,
                    country: row.country,
                    avatarData: avatarData,
                    createdAt: row.createdAt,
                    appleDisplayName: loadAppleDisplayName(for: row.id),
                    hasSetCustomNickname: loadHasCustomNickname(for: row.id)
                ))
                error = "Account is banned."
                return
            }
        }

        setCurrentUserAndCache(AppUser(
            id: row.id,
            email: row.email,
            nickname: row.nickname,
            country: row.country,
            avatarData: avatarData,
            createdAt: row.createdAt,
            appleDisplayName: loadAppleDisplayName(for: row.id),
            hasSetCustomNickname: loadHasCustomNickname(for: row.id)
        ))
    }

    func patchUserProfile(session: SupabaseSessionResponse, userId: String, nickname: String?, country: String?) async throws {
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
    func uploadAvatarToStorage(session: SupabaseSessionResponse, userId: String, imageData: Data) async throws -> String {
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

        let responseString = String(data: data, encoding: .utf8) ?? "(empty)"
        #if DEBUG
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
    func deleteAvatarFromStorage(session: SupabaseSessionResponse, userId: String) async throws {
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
}
