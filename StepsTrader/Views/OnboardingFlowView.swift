import SwiftUI
import UIKit

struct OnboardingFlowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var authService: AuthenticationService
    @ObservedObject var locationPermissionRequester: LocationPermissionRequester
    let onComplete: () -> Void

    @State private var onboardingPresented: Bool = true
    
    // Setup values - use @AppStorage for immediate sync with other views
    @AppStorage("userStepsTarget") private var stepsTarget: Double = 10_000
    @AppStorage("userSleepTarget") private var sleepTarget: Double = 8.0
    @State private var userName: String = ""
    @State private var avatarImage: UIImage? = nil

    var body: some View {
        ZStack {
            OnboardingStoriesView(
                isPresented: $onboardingPresented,
                slides: mainSlides(),
                accent: AppColors.brandPink,
                skipText: "Skip",
                nextText: "Next",
                startText: "Start",
                allowText: "Allow",
                showsSkip: false,
                onLocationSlide: nil,
                onHealthSlide: nil,
                onNotificationSlide: nil,
                onFamilyControlsSlide: nil,
                onFinish: { finishOnboarding() },
                model: model,
                stepsTarget: $stepsTarget,
                sleepTarget: $sleepTarget,
                userName: $userName,
                avatarImage: $avatarImage
            )
        }
        .transition(.opacity)
    }

    private func finishOnboarding() {
        // Save setup values to app group (for extensions)
        let defaults = UserDefaults.stepsTrader()
        defaults.set(stepsTarget, forKey: "userStepsTarget")
        defaults.set(sleepTarget, forKey: "userSleepTarget")
        
        // Note: Activity preferences (body/mind/heart) are saved automatically
        // when toggled via model.togglePreferredOption()
        
        // Save username and avatar to profile
        let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let avatarData = avatarImage?.jpegData(compressionQuality: 0.75)
        
        authService.updateProfile(
            nickname: trimmedName.isEmpty ? nil : trimmedName,
            country: authService.currentUser?.country,
            avatarData: avatarData
        )
        
        // Trigger energy recalculation with new settings
        Task { @MainActor in
            model.recalculateDailyEnergy()
        }
        
        Task {
            await SupabaseSyncService.shared.trackAnalyticsEvent(
                name: "onboarding_completed",
                properties: [
                    "flow": "v1_7_slide",
                    "steps_target": String(Int(stepsTarget)),
                    "sleep_target": String(format: "%.1f", sleepTarget)
                ],
                dedupeKey: "onboarding_completed_v1"
            )
        }
        
        // Request core permissions once at the end of the 7-slide flow.
        Task {
            await MainActor.run {
                locationPermissionRequester.requestWhenInUse()
            }
            await model.ensureHealthAuthorizationAndRefresh()
            await model.requestNotificationPermission()
            try? await model.familyControlsService.requestAuthorization()
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            onComplete()
        }
    }
    
    // MARK: - Main onboarding slides (7-step, gallery-first)
    
    private func mainSlides() -> [OnboardingSlide] {
        [
            // 1 - Gallery-first framing
            OnboardingSlide(
                lines: [
                    "Welcome to Proof.",
                    "Your gallery comes first.",
                    "Everything else supports it."
                ],
                symbol: "sparkles.rectangle.stack",
                gradient: [.pink, .purple]
            ),
            
            // 2 - Joys (gallery center)
            OnboardingSlide(
                lines: [
                    "Pick what belongs",
                    "in your daily gallery.",
                    "Choose up to 4."
                ],
                symbol: "heart.fill",
                gradient: [.orange, .pink],
                slideType: .activitySelection(.heart)
            ),
            
            // 3 - Activity
            OnboardingSlide(
                lines: [
                    "Pick up to 4 activity pieces.",
                    "These add energy from movement."
                ],
                symbol: "figure.run",
                gradient: [.green, .teal],
                slideType: .activitySelection(.body)
            ),
            
            // 4 - Creativity
            OnboardingSlide(
                lines: [
                    "Pick up to 4 creativity pieces.",
                    "These support focus and reset."
                ],
                symbol: "brain.head.profile",
                gradient: [.blue, .cyan],
                slideType: .activitySelection(.mind)
            ),
            
            // 5 - Steps setup
            OnboardingSlide(
                lines: [
                    "How many steps a day",
                    "make me feel good?"
                ],
                symbol: "figure.walk",
                gradient: [.green, .mint],
                slideType: .stepsSetup
            ),
            
            // 6 - Sleep setup
            OnboardingSlide(
                lines: [
                    "How much sleep keeps me",
                    "clear and steady?"
                ],
                symbol: "moon.zzz.fill",
                gradient: [.indigo, .purple],
                slideType: .sleepSetup
            ),
            
            // 7 - Final confirm
            OnboardingSlide(
                lines: [
                    "You're set.",
                    "We'll ask permissions next",
                    "to make this work."
                ],
                symbol: "checkmark.circle.fill",
                gradient: [.green, .mint]
            )
        ]
    }
}
