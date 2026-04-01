import SwiftUI

@main
struct OnboardingPreviewApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var authService = AuthenticationService.shared
    @State private var completed = false
    
    var body: some Scene {
        WindowGroup("Nowhere — Onboarding v5") {
            Group {
                if completed {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)
                        Text("Onboarding completed.")
                            .font(.title2)
                        Text("13 slides · v5 interactive flow")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Restart") {
                            completed = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
                    .foregroundColor(.white)
                } else {
                    OnboardingFlowView(
                        model: model,
                        authService: authService
                    ) {
                        withAnimation { completed = true }
                    }
                }
            }
            .frame(width: 393, height: 852)
            .clipShape(RoundedRectangle(cornerRadius: 44))
            .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 10)
            .padding(20)
            .background(Color(white: 0.12))
        }
        .defaultSize(width: 433, height: 892)
    }
}
