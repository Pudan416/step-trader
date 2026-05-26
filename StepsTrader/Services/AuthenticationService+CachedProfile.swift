import Foundation

// MARK: - Offline profile cache & optimistic session restore

extension AuthenticationService {

  private static let cachedProfileFilePrefix = "cached_user_profile_v1_"

  private static func cachedProfileURL(for userId: String) -> URL {
    URL.documentsDirectory.appending(path: "\(cachedProfileFilePrefix)\(userId).json")
  }

  func persistCachedProfile(_ user: AppUser) {
    var snapshot = user
    snapshot.avatarData = nil
    let url = Self.cachedProfileURL(for: user.id)
    do {
      let data = try JSONEncoder().encode(snapshot)
      try data.write(to: url, options: .atomic)
    } catch {
      AppLogger.auth.error("Failed to cache user profile: \(error.localizedDescription)")
    }
  }

  func loadCachedProfile(for userId: String) -> AppUser? {
    let url = Self.cachedProfileURL(for: userId)
    guard let data = try? Data(contentsOf: url),
      let user = try? JSONDecoder().decode(AppUser.self, from: data)
    else { return nil }
    var hydrated = user
    hydrated.avatarData = loadAvatarData(for: userId)
    return hydrated
  }

  func clearCachedProfile(for userId: String) {
    try? FileManager.default.removeItem(at: Self.cachedProfileURL(for: userId))
  }

  /// Restores logged-in UI immediately from disk while network refresh runs.
  func applyCachedSessionState(userId: String, email: String?, createdAt: Date?) {
    if let cached = loadCachedProfile(for: userId) {
      currentUser = cached
      isAuthenticated = true
      return
    }
    currentUser = minimalUser(userId: userId, email: email, createdAt: createdAt)
    isAuthenticated = true
  }

  func minimalUser(userId: String, email: String?, createdAt: Date?) -> AppUser {
    AppUser(
      id: userId,
      email: email,
      nickname: nil,
      country: nil,
      avatarData: loadAvatarData(for: userId),
      createdAt: createdAt ?? .now,
      appleDisplayName: loadAppleDisplayName(for: userId),
      hasSetCustomNickname: loadHasCustomNickname(for: userId)
    )
  }

  func setCurrentUserAndCache(_ user: AppUser) {
    currentUser = user
    isAuthenticated = true
    persistCachedProfile(user)
  }

  /// Only auth failures that mean the stored session is dead — not offline/5xx.
  func isSessionInvalidatingError(_ error: Error) -> Bool {
    if let auth = error as? AuthError {
      switch auth {
      case .sessionExpired, .invalidCredential:
        return true
      case .cancelled, .misconfiguredSupabase, .unknown:
        return false
      case .supabaseError(let message):
        let lower = message.lowercased()
        if lower.contains("invalid_grant") { return true }
        if lower.contains("refresh_token") && lower.contains("not found") { return true }
        if lower.contains("jwt") && lower.contains("expired") { return true }
        return false
      }
    }
    return false
  }

}
