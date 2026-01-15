import Foundation
import AuthenticationServices
import SwiftUI

// MARK: - User Model

struct AppUser: Codable {
    let id: String
    let email: String?
    var nickname: String?
    var country: String?
    let createdAt: Date
    
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
}

// MARK: - Authentication Service

@MainActor
class AuthenticationService: NSObject, ObservableObject {
    
    static let shared = AuthenticationService()
    
    @Published var currentUser: AppUser?
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    private let userDefaultsKey = "authenticatedUser"
    private var authContinuation: CheckedContinuation<ASAuthorization, Error>?
    
    override init() {
        super.init()
        loadStoredUser()
    }
    
    // MARK: - Public Methods
    
    func signInWithApple() async throws {
        isLoading = true
        error = nil
        
        defer { isLoading = false }
        
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email]
        
        let authorization = try await performSignIn(request: request)
        
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.invalidCredential
        }
        
        let user = AppUser(
            id: credential.user,
            email: credential.email ?? loadStoredEmail(for: credential.user),
            nickname: loadStoredNickname(for: credential.user),
            country: loadStoredCountry(for: credential.user),
            createdAt: Date()
        )
        
        // Store user details for future logins (Apple only sends name/email on first sign-in)
        storeUserDetails(user)
        
        currentUser = user
        isAuthenticated = true
        saveUser(user)
    }
    
    func signOut() {
        currentUser = nil
        isAuthenticated = false
        clearStoredUser()
    }
    
    /// Handle authorization result from SignInWithAppleButton
    func handleAuthorization(_ authorization: ASAuthorization) {
        // Prevent double processing
        guard !isAuthenticated else {
            print("⚠️ Already authenticated, skipping duplicate authorization")
            return
        }
        
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            error = AuthError.invalidCredential.localizedDescription
            return
        }
        
        let user = AppUser(
            id: credential.user,
            email: credential.email ?? loadStoredEmail(for: credential.user),
            nickname: loadStoredNickname(for: credential.user),
            country: loadStoredCountry(for: credential.user),
            createdAt: Date()
        )
        
        storeUserDetails(user)
        currentUser = user
        isAuthenticated = true
        saveUser(user)
        print("✅ User authenticated: \(user.displayName)")
    }
    
    func checkAuthenticationState() async {
        guard let user = currentUser else { return }
        
        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: user.id)
            
            switch state {
            case .authorized:
                isAuthenticated = true
            case .revoked, .notFound:
                signOut()
            case .transferred:
                // Handle account transfer if needed
                break
            @unknown default:
                break
            }
        } catch {
            print("❌ Failed to check credential state: \(error)")
        }
    }
    
    // MARK: - Profile Update Methods
    
    func updateProfile(nickname: String?, country: String?) {
        guard var user = currentUser else { return }
        user.nickname = nickname
        user.country = country
        currentUser = user
        saveUser(user)
        storeUserDetails(user)
        print("✅ Profile updated: \(user.displayName)")
    }
    
    // MARK: - Private Methods
    
    private func performSignIn(request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorization {
        return try await withCheckedThrowingContinuation { continuation in
            self.authContinuation = continuation
            
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
    
    private func loadStoredUser() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let user = try? JSONDecoder().decode(AppUser.self, from: data) else {
            return
        }
        currentUser = user
        isAuthenticated = true
    }
    
    private func saveUser(_ user: AppUser) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
    
    private func clearStoredUser() {
        guard let userId = currentUser?.id else {
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            return
        }
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: "appleUserEmail_\(userId)")
        UserDefaults.standard.removeObject(forKey: "appleUserNickname_\(userId)")
        UserDefaults.standard.removeObject(forKey: "appleUserCountry_\(userId)")
    }
    
    // Store user details separately (Apple only provides them on first sign-in)
    private func storeUserDetails(_ user: AppUser) {
        let ud = UserDefaults.standard
        let id = user.id
        
        if let email = user.email {
            ud.set(email, forKey: "appleUserEmail_\(id)")
        }
        if let nickname = user.nickname, !nickname.isEmpty {
            ud.set(nickname, forKey: "appleUserNickname_\(id)")
        } else {
            ud.removeObject(forKey: "appleUserNickname_\(id)")
        }
        if let country = user.country, !country.isEmpty {
            ud.set(country, forKey: "appleUserCountry_\(id)")
        } else {
            ud.removeObject(forKey: "appleUserCountry_\(id)")
        }
    }
    
    private func loadStoredEmail(for userId: String) -> String? {
        UserDefaults.standard.string(forKey: "appleUserEmail_\(userId)")
    }
    
    private func loadStoredNickname(for userId: String) -> String? {
        UserDefaults.standard.string(forKey: "appleUserNickname_\(userId)")
    }
    
    private func loadStoredCountry(for userId: String) -> String? {
        UserDefaults.standard.string(forKey: "appleUserCountry_\(userId)")
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthenticationService: ASAuthorizationControllerDelegate {
    
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            authContinuation?.resume(returning: authorization)
            authContinuation = nil
        }
    }
    
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            self.error = error.localizedDescription
            authContinuation?.resume(throwing: error)
            authContinuation = nil
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthenticationService: ASAuthorizationControllerPresentationContextProviding {
    
    @MainActor
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return UIWindow()
        }
        return window
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case invalidCredential
    case cancelled
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Invalid credentials received"
        case .cancelled:
            return "Sign in was cancelled"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

