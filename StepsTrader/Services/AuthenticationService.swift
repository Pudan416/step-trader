import Foundation
import AuthenticationServices
import SwiftUI

// MARK: - User Model

struct AppUser: Codable {
    let id: String
    let email: String?
    let firstName: String?
    let lastName: String?
    let createdAt: Date
    
    var displayName: String {
        if let firstName = firstName, !firstName.isEmpty {
            if let lastName = lastName, !lastName.isEmpty {
                return "\(firstName) \(lastName)"
            }
            return firstName
        }
        return email ?? "User"
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
        request.requestedScopes = [.fullName, .email]
        
        let authorization = try await performSignIn(request: request)
        
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.invalidCredential
        }
        
        let user = AppUser(
            id: credential.user,
            email: credential.email ?? loadStoredEmail(for: credential.user),
            firstName: credential.fullName?.givenName ?? loadStoredFirstName(for: credential.user),
            lastName: credential.fullName?.familyName ?? loadStoredLastName(for: credential.user),
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
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: "appleUserEmail")
        UserDefaults.standard.removeObject(forKey: "appleUserFirstName")
        UserDefaults.standard.removeObject(forKey: "appleUserLastName")
    }
    
    // Store user details separately (Apple only provides them on first sign-in)
    private func storeUserDetails(_ user: AppUser) {
        if let email = user.email {
            UserDefaults.standard.set(email, forKey: "appleUserEmail_\(user.id)")
        }
        if let firstName = user.firstName {
            UserDefaults.standard.set(firstName, forKey: "appleUserFirstName_\(user.id)")
        }
        if let lastName = user.lastName {
            UserDefaults.standard.set(lastName, forKey: "appleUserLastName_\(user.id)")
        }
    }
    
    private func loadStoredEmail(for userId: String) -> String? {
        UserDefaults.standard.string(forKey: "appleUserEmail_\(userId)")
    }
    
    private func loadStoredFirstName(for userId: String) -> String? {
        UserDefaults.standard.string(forKey: "appleUserFirstName_\(userId)")
    }
    
    private func loadStoredLastName(for userId: String) -> String? {
        UserDefaults.standard.string(forKey: "appleUserLastName_\(userId)")
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
    
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
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

