import SwiftUI
import AuthenticationServices

@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    let completion: (Result<ASAuthorization, Error>) -> Void

    init(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            return UIWindow()
        }
        return window
        #elseif canImport(AppKit)
        return NSApplication.shared.keyWindow ?? NSWindow()
        #else
        return ASPresentationAnchor()
        #endif
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        completion(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion(.failure(error))
    }

    static func trigger(auth: AuthenticationService, onSuccess: @escaping () -> Void) {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        auth.configureAppleRequest(request)

        let coordinator = AppleSignInCoordinator { result in
            switch result {
            case .success(let authorization):
                auth.handleAuthorization(authorization)
                onSuccess()
            case .failure(let error):
                AppLogger.auth.error("Apple Sign In failed: \(error.localizedDescription)")
            }
        }

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = coordinator
        controller.presentationContextProvider = coordinator
        objc_setAssociatedObject(controller, "delegate", coordinator, .OBJC_ASSOCIATION_RETAIN)
        controller.performRequests()
    }
}
