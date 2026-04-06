import SwiftUI
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#endif

struct LoginView: View {
    @ObservedObject var authService: AuthenticationService
    var showsClose: Bool = true
    /// When true, use full-screen "login1" image as background (onboarding step 9).
    var useLogin1Background: Bool = false
    var onAuthenticated: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme
    @State private var showError: Bool = false

    /// Warm Sunset roles (BRANDBOOK §8) for feature icons — ties login to the canvas gradient story.
    private static let featureWalkTint = Color(hex: "#FFBF65")
    private static let featureAwarenessTint = AppColors.brandAccent
    private static let featureTrackTint = Color(hex: "#FD8973")

    var body: some View {
        ZStack {
            if useLogin1Background {
                Image("login1")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea()
            } else {
                EnergyGradientBackground(
                    stepsPoints: 0,
                    sleepPoints: 0,
                    hasStepsData: false,
                    hasSleepData: false
                )
            }

            VStack(spacing: 0) {
                if useLogin1Background {
                    Spacer(minLength: 0)
                    if authService.isLoading {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                    }
                    Spacer(minLength: 0)
                    SignInWithAppleButton(.signIn) { request in
                        authService.configureAppleRequest(request)
                    } onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            AppLogger.auth.debug("🔐 SignInWithAppleButton completed successfully")
                            authService.handleAuthorization(authorization)
                        case .failure(let error):
                            AppLogger.auth.error("❌ SignInWithAppleButton failed: \(error.localizedDescription)")
                            authService.error = error.localizedDescription
                            showError = true
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 54)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    .disabled(authService.isLoading || authService.isAuthenticated)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 50)
                } else {
                    if showsClose {
                        HStack {
                            Spacer()
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(appTheme.textPrimary.opacity(0.45))
                            }
                            .padding()
                        }
                    } else {
                        Spacer(minLength: 24)
                    }
                    Spacer()
                    VStack(spacing: 20) {
                        loginAppIconMark
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .shadow(color: Color(red: 0.12, green: 0.08, blue: 0.35).opacity(0.45), radius: 16, x: 0, y: 10)
                            .accessibilityLabel(String(localized: "Nowhere", comment: "App name"))
                        VStack(spacing: 8) {
                            Text(String(localized: "Nowhere", comment: "App name"))
                                .font(.systemSerif(32, weight: .black, relativeTo: .title))
                                .foregroundStyle(appTheme.textPrimary)
                            Text(String(localized: "The sense of being present", comment: "App tagline"))
                                .font(.subheadline)
                                .foregroundStyle(appTheme.adaptiveSecondaryText)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 24)
                    Spacer()
                    VStack(spacing: 12) {
                        featureRow(
                            icon: "figure.walk",
                            title: String(localized: "Turn movement into energy"),
                            tint: Self.featureWalkTint
                        )
                        featureRow(
                            icon: "eye.fill",
                            title: String(localized: "Stay present, control screen time"),
                            tint: Self.featureAwarenessTint
                        )
                        featureRow(
                            icon: "chart.line.uptrend.xyaxis",
                            title: String(localized: "Track what matters"),
                            tint: Self.featureTrackTint
                        )
                    }
                    .padding(.horizontal, 24)
                    Spacer()
                    VStack(spacing: 16) {
                        SignInWithAppleButton(.signIn) { request in
                            authService.configureAppleRequest(request)
                        } onCompletion: { result in
                            switch result {
                            case .success(let authorization):
                                AppLogger.auth.debug("🔐 SignInWithAppleButton completed successfully")
                                authService.handleAuthorization(authorization)
                            case .failure(let error):
                                AppLogger.auth.error("❌ SignInWithAppleButton failed: \(error.localizedDescription)")
                                authService.error = error.localizedDescription
                                showError = true
                            }
                        }
                        .signInWithAppleButtonStyle(appTheme.isLightTheme ? .black : .white)
                        .frame(height: 54)
                        .shadow(color: .black.opacity(appTheme.isLightTheme ? 0.12 : 0.25), radius: 12, x: 0, y: 6)
                        .disabled(authService.isLoading || authService.isAuthenticated)
                        Text(String(localized: "Account syncs across devices"))
                            .font(.caption)
                            .foregroundStyle(appTheme.adaptiveMutedText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 50)
                    if authService.isLoading {
                        ProgressView()
                            .tint(AppColors.brandAccent)
                            .padding(.bottom, 20)
                    }
                }
            }
        }
        .alert(String(localized: "Error"), isPresented: $showError) {
            Button(String(localized: "OK")) { showError = false }
        } message: {
            Text(authService.error ?? String(localized: "Something went wrong"))
        }
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                onAuthenticated?()
                if showsClose {
                    dismiss()
                }
            }
        }
    }

    /// Same artwork as **App Icon** (`AppIcon.appiconset`), read from the main bundle.
    @ViewBuilder
    private var loginAppIconMark: some View {
        #if canImport(UIKit)
        if let ui = BundlePrimaryAppIcon.uiImage {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
        } else {
            loginAppIconFallbackMark
        }
        #else
        loginAppIconFallbackMark
        #endif
    }

    private var loginAppIconFallbackMark: some View {
        Image(systemName: "app.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(appTheme.adaptiveMutedText)
    }

    @ViewBuilder
    private func featureRow(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.22))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(appTheme.textPrimary.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(appTheme.textPrimary.opacity(appTheme.isLightTheme ? 0.1 : 0.12), lineWidth: 1)
                }
        }
    }
}

#if canImport(UIKit)
/// Resolves the primary icon installed for the app (driven by `AppIcon` in the asset catalog).
private enum BundlePrimaryAppIcon {
    static var uiImage: UIImage? {
        if let named = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String,
           let img = UIImage(named: named), img.size.width > 0 {
            return img
        }
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any] else {
            return UIImage(named: "AppIcon")
        }
        if let files = primary["CFBundleIconFiles"] as? [String] {
            var best: UIImage?
            var bestArea: CGFloat = 0
            for name in files {
                guard let img = UIImage(named: name) else { continue }
                let area = img.size.width * img.size.height
                if area > bestArea {
                    bestArea = area
                    best = img
                }
            }
            if let best { return best }
        }
        return UIImage(named: "AppIcon")
    }
}
#endif

#Preview {
    LoginView(authService: AuthenticationService.shared)
        .themed(.night)
}
