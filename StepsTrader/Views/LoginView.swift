import SwiftUI
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#endif

struct LoginView: View {
    @ObservedObject var authService: AuthenticationService
    var showsClose: Bool = true
    var useLogin1Background: Bool = false
    var onAuthenticated: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme
    @Environment(\.resolvedAppTheme) private var resolvedTheme
    @State private var showError: Bool = false
    @State private var appeared = false

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
                    hasSleepData: false,
                    showGrain: false
                )
            }

            if useLogin1Background {
                login1Layout
            } else {
                standardLayout
            }
        }
        .alert(String(localized: "Error"), isPresented: $showError) {
            Button(String(localized: "OK")) { showError = false }
        } message: {
            Text(authService.error ?? String(localized: "Something went wrong"))
        }
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated && !authService.isAnonymous {
                onAuthenticated?()
                if showsClose { dismiss() }
            }
        }
        .onChange(of: authService.isAnonymous) { _, isAnonymous in
            if !isAnonymous && authService.isAuthenticated {
                onAuthenticated?()
                if showsClose { dismiss() }
            }
        }
        .onChange(of: authService.error) { _, newError in
            if newError != nil, !authService.hasAppleAccount {
                showError = true
            }
        }
        .task {
            withAnimation(.easeOut(duration: 0.7).delay(0.15)) {
                appeared = true
            }
        }
    }

    // MARK: - Login1 background variant (onboarding)

    private var login1Layout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if authService.isLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            }
            Spacer(minLength: 0)
            appleSignInButton
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
        }
    }

    // MARK: - Standard layout

    private var standardLayout: some View {
        VStack(spacing: 0) {
            // Close button
            if showsClose {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(appTheme.adaptiveSecondaryText)
                            .frame(width: 30, height: 30)
                            .background(appTheme.adaptiveMutedText.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .accessibilityLabel(String(localized: "Dismiss"))
                    .padding(.trailing, 8)
                    .padding(.top, 8)
                }
            } else {
                Spacer(minLength: 24)
            }

            Spacer()

            // Brand mark
            VStack(spacing: 18) {
                loginAppIconMark
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color(red: 0.12, green: 0.08, blue: 0.35).opacity(0.35), radius: 20, x: 0, y: 10)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.85)

                VStack(spacing: 6) {
                    Text(String(localized: "Nowhere"))
                        .font(.systemSerif(32, weight: .black, relativeTo: .title))
                        .foregroundStyle(appTheme.textPrimary)

                    Text(String(localized: "The sense of being present"))
                        .font(.subheadline)
                        .foregroundStyle(appTheme.adaptiveSecondaryText)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
            }

            Spacer()

            // Features — lightweight, no cards
            VStack(alignment: .leading, spacing: 18) {
                featureRow(
                    icon: "figure.walk",
                    text: String(localized: "Turn movement into energy"),
                    tint: Color(hex: "#FFBF65")
                )
                featureRow(
                    icon: "eye.fill",
                    text: String(localized: "Stay present, control screen time"),
                    tint: AppColors.brandAccent
                )
                featureRow(
                    icon: "chart.line.uptrend.xyaxis",
                    text: String(localized: "Track what matters"),
                    tint: Color(hex: "#FD8973")
                )
            }
            .padding(.horizontal, 32)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)

            Spacer()

            // Sign in
            VStack(spacing: 12) {
                appleSignInButton

                Text(String(localized: "Sign in to keep your data safe and synced across devices"))
                    .font(.caption)
                    .foregroundStyle(appTheme.adaptiveMutedText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 44)

            if authService.isLoading {
                ProgressView()
                    .tint(AppColors.brandAccent)
                    .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Components

    private var appleSignInButton: some View {
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
        .signInWithAppleButtonStyle(resolvedTheme.isLight ? .black : .white)
        .frame(height: 52)
        .shadow(color: .black.opacity(resolvedTheme.isLight ? 0.08 : 0.2), radius: 12, x: 0, y: 6)
        .disabled(authService.isLoading || authService.hasAppleAccount)
    }

    private func featureRow(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(appTheme.textPrimary.opacity(0.8))
        }
    }

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
}

#if canImport(UIKit)
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
