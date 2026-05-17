import SwiftUI
import AuthenticationServices

@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private static var activeCoordinator: AppleSignInCoordinator?
    private var authController: ASAuthorizationController?

    let completion: (Result<ASAuthorization, Error>) -> Void

    init(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        for scene in scenes where scene.activationState == .foregroundActive {
            if let w = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
                return w
            }
        }

        if let w = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow })
            ?? scenes.flatMap(\.windows).first {
            return w
        }

        return UIWindow()
        #elseif canImport(AppKit)
        return NSApplication.shared.keyWindow ?? NSWindow()
        #else
        return ASPresentationAnchor()
        #endif
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        AppLogger.auth.debug("🔐 ASAuthorizationController didCompleteWithAuthorization — credential type: \(String(describing: type(of: authorization.credential)))")
        completion(.success(authorization))
        Self.activeCoordinator = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let code = (error as NSError).code
        let domain = (error as NSError).domain
        AppLogger.auth.error("🔐 ASAuthorizationController didCompleteWithError — domain: \(domain), code: \(code), desc: \(error.localizedDescription)")
        completion(.failure(error))
        Self.activeCoordinator = nil
    }

    static func trigger(auth: AuthenticationService, onSuccess: @escaping () -> Void) {
        AppLogger.auth.debug("🔐 AppleSignInCoordinator.trigger — creating request")
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        auth.configureAppleRequest(request)

        let coordinator = AppleSignInCoordinator { result in
            switch result {
            case .success(let authorization):
                AppLogger.auth.debug("🔐 AppleSignInCoordinator — success, forwarding to handleAuthorization")
                auth.handleAuthorization(authorization)
                onSuccess()
            case .failure(let error):
                AppLogger.auth.error("🔐 AppleSignInCoordinator — failure: \(error.localizedDescription)")
            }
        }

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = coordinator
        controller.presentationContextProvider = coordinator
        coordinator.authController = controller
        activeCoordinator = coordinator
        AppLogger.auth.debug("🔐 AppleSignInCoordinator.trigger — calling performRequests()")
        controller.performRequests()
    }
}
