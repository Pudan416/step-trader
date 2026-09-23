import Foundation

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
