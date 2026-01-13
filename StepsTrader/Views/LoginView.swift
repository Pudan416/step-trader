import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @ObservedObject var authService: AuthenticationService
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    
    @State private var showError: Bool = false
    
    var body: some View {
        ZStack {
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
                    .frame(width: 300, height: 300)
                    .blur(radius: 60)
                    .offset(x: -100, y: -50)
                
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 250, height: 250)
                    .blur(radius: 50)
                    .offset(x: geo.size.width - 100, y: geo.size.height - 200)
            }
            
            VStack(spacing: 0) {
                Spacer()
                
                // Logo & Title
                VStack(spacing: 24) {
                    // App icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 28)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.88, green: 0.51, blue: 0.85),
                                        Color(red: 0.65, green: 0.35, blue: 0.85)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                            .shadow(color: Color.purple.opacity(0.4), radius: 20, x: 0, y: 10)
                        
                        Image(systemName: "flame.fill")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(spacing: 8) {
                        Text("DOOM CTRL")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text(loc(appLanguage, "Trade steps for screen time", "Меняй шаги на экранное время"))
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                // Features list
                VStack(spacing: 16) {
                    featureRow(
                        icon: "figure.walk",
                        title: loc(appLanguage, "Earn energy by walking", "Зарабатывай энергию ходьбой"),
                        color: .green
                    )
                    featureRow(
                        icon: "app.badge.checkmark",
                        title: loc(appLanguage, "Control app access", "Контролируй доступ к приложениям"),
                        color: .blue
                    )
                    featureRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: loc(appLanguage, "Track your progress", "Отслеживай прогресс"),
                        color: .orange
                    )
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Sign in button
                VStack(spacing: 16) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        Task {
                            do {
                                try await authService.signInWithApple()
                            } catch {
                                showError = true
                            }
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 54)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    
                    Text(loc(appLanguage, "Your data stays on your device", "Твои данные остаются на устройстве"))
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
        .alert(loc(appLanguage, "Error", "Ошибка"), isPresented: $showError) {
            Button("OK") { showError = false }
        } message: {
            Text(authService.error ?? loc(appLanguage, "Something went wrong", "Что-то пошло не так"))
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
                    .font(.system(size: 18, weight: .semibold))
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

