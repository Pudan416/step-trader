import Foundation
import Security

// Supporting types for `AuthenticationService`: the auth error enum, the
// Keychain-backed session store, and the Supabase request/response DTOs.
// These were extracted from AuthenticationService.swift (§9.2) so the service
// file stays focused on auth flow logic. They are `internal` (module-scoped)
// rather than file-`private` because the service + its extensions reference
// them across files.

// MARK: - Session Keychain Helper

enum SessionKeychain {
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
    case sessionExpired
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
        case .sessionExpired:
            return "Session expired"
        case .supabaseError(let message):
            return message
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

// MARK: - Supabase DTOs

struct SupabaseIdTokenGrantRequest: Codable {
    let provider: String
    let idToken: String
    let nonce: String

    enum CodingKeys: String, CodingKey {
        case provider
        case idToken = "id_token"
        case nonce
    }
}

struct SupabaseRefreshGrantRequest: Codable {
    let refreshToken: String
    enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
}

struct SupabaseAuthUser: Codable {
    let id: String
    let email: String?
    let createdAt: Date?
    let isAnonymous: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case createdAt = "created_at"
        case isAnonymous = "is_anonymous"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        isAnonymous = try c.decodeIfPresent(Bool.self, forKey: .isAnonymous) ?? false
    }
}

struct SupabaseSessionResponse: Codable {
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
            expiresAt = Date.now.addingTimeInterval(TimeInterval(expiresIn))
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

struct SupabasePublicUserRow: Codable {
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

struct SupabasePublicUserPatch: Codable {
    let nickname: String?
    let country: String?

    init(nickname: String? = nil, country: String? = nil) {
        self.nickname = nickname
        self.country = country
    }
}
