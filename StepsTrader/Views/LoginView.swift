import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @ObservedObject var authService: AuthenticationService
    var showsClose: Bool = true
    /// When true, use full-screen "login1" image as background (onboarding step 9).
    var useLogin1Background: Bool = false
    var onAuthenticated: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showError: Bool = false
    @ScaledMetric(relativeTo: .body) private var decorCircleLarge: CGFloat = 300
    @ScaledMetric(relativeTo: .body) private var decorCircleSmall: CGFloat = 250
    
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
                // Background gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.08, blue: 0.12),
                        Color(red: 0.12, green: 0.10, blue: 0.18),
                        Color(red: 0.08, green: 0.08, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // Decorative circles
                GeometryReader { geo in
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: decorCircleLarge, height: decorCircleLarge)
                        .blur(radius: 60)
                        .offset(x: -100, y: -50)
                    
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: decorCircleSmall, height: decorCircleSmall)
                        .blur(radius: 50)
                        .offset(x: geo.size.width - 100, y: geo.size.height - 200)
                }
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
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .padding()
                        }
                    } else {
                        Spacer(minLength: 24)
                    }
                    Spacer()
                    VStack(spacing: 24) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 28)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.45, green: 0.35, blue: 0.85),
                                            Color(red: 0.30, green: 0.20, blue: 0.65)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 100, height: 100)
                                .shadow(color: Color.indigo.opacity(0.4), radius: 20, x: 0, y: 10)
                            Image(systemName: "eye.fill")
                                .font(.systemSerif(44, weight: .bold, relativeTo: .largeTitle))
                                .foregroundColor(.white)
                        }
                        VStack(spacing: 8) {
                            Text(String(localized: "Nowhere", comment: "App name"))
                                .font(.systemSerif(32, weight: .black, relativeTo: .title))
                                .foregroundColor(.white)
                            Text(String(localized: "The sense of being present", comment: "App tagline"))
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    Spacer()
                    VStack(spacing: 16) {
                        featureRow(
                            icon: "figure.walk",
                            title: String(localized: "Turn movement into energy"),
                            color: .green
                        )
                        featureRow(
                            icon: "eye.fill",
                            title: String(localized: "Stay present, control screen time"),
                            color: .indigo
                        )
                        featureRow(
                            icon: "chart.line.uptrend.xyaxis",
                            title: String(localized: "Track what matters"),
                            color: .orange
                        )
                    }
                    .padding(.horizontal, 32)
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
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                        .disabled(authService.isLoading || authService.isAuthenticated)
                        Text(String(localized: "Account syncs across devices"))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 50)
                    if authService.isLoading {
                        ProgressView()
                            .tint(.white)
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
    
    @ViewBuilder
    private func featureRow(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.systemSerif(18, weight: .semibold, relativeTo: .body))
                    .foregroundColor(color)
            }
            
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

#Preview {
    LoginView(authService: AuthenticationService.shared)
}
