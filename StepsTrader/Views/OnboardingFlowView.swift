import SwiftUI
import UIKit
#if canImport(FamilyControls)
import FamilyControls
#endif

struct OnboardingFlowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var authService: AuthenticationService
    @ObservedObject var locationPermissionRequester: LocationPermissionRequester
    let onComplete: () -> Void

    @State private var onboardingPresented: Bool = true
    
    @AppStorage("userStepsTarget") private var stepsTarget: Double = 10_000
    @AppStorage("userSleepTarget") private var sleepTarget: Double = 8.0
    @State private var userName: String = ""
    @State private var avatarImage: UIImage? = nil
    @State private var onboardingSelection = FamilyActivitySelection()
    @State private var selectedFeedApp: String? = nil

    var body: some View {
        ZStack {
            OnboardingStoriesView(
                isPresented: $onboardingPresented,
                slides: mainSlides(),
                accent: AppColors.brandAccent,
                skipText: "Skip",
                nextText: "Next",
                startText: "Let's go",
                allowText: "Allow",
                showsSkip: false,
                onLocationSlide: nil,
                onHealthSlide: {
                    Task { await model.ensureHealthAuthorizationAndRefresh() }
                },
                onNotificationSlide: {
                    Task { await model.requestNotificationPermission() }
                },
                onFamilyControlsSlide: {
                    Task { try? await model.familyControlsService.requestAuthorization() }
                },
                onFinish: { finishOnboarding() },
                model: model,
                stepsTarget: $stepsTarget,
                sleepTarget: $sleepTarget,
                userName: $userName,
                avatarImage: $avatarImage,
                authService: authService,
                onboardingSelection: $onboardingSelection,
                selectedFeedApp: $selectedFeedApp
            )
        }
        .transition(.opacity)
    }

    private func finishOnboarding() {
        let defaults = UserDefaults.stepsTrader()
        defaults.set(stepsTarget, forKey: "userStepsTarget")
        defaults.set(sleepTarget, forKey: "userSleepTarget")
        
        let hasApps = !onboardingSelection.applicationTokens.isEmpty
            || !onboardingSelection.categoryTokens.isEmpty
        if hasApps {
            let name = selectedFeedApp.map { TargetResolver.displayName(for: $0) } ?? "My Apps"
            let group = model.createTicketGroup(name: name, templateApp: selectedFeedApp)
            model.addAppsToGroup(group.id, selection: onboardingSelection)
        }
        
        Task { @MainActor in
            model.recalculateDailyEnergy()
        }
        
        Task {
            await SupabaseSyncService.shared.trackAnalyticsEvent(
                name: "onboarding_completed",
                properties: [
                    "flow": "v3_nowhere_philosophy",
                    "steps_target": String(Int(stepsTarget)),
                    "sleep_target": String(format: "%.1f", sleepTarget),
                    "selected_feed": selectedFeedApp ?? "none",
                    "selected_apps_count": String(onboardingSelection.applicationTokens.count)
                ],
                dedupeKey: "onboarding_completed_v1"
            )
        }
        
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
    
    // MARK: - Philosophy-driven onboarding (13 slides)
    
    private func mainSlides() -> [OnboardingSlide] {
        [
            // 1 — the feeling
            OnboardingSlide(
                lines: [
                    "Recently I've found myself",
                    "living the same day over and over.",
                    "Working, scrolling, staring at the screen."
                ],
                symbol: "eye.slash",
                gradient: [Color(white: 0.15), Color(white: 0.08)]
            ),
            
            // 2 — the thought
            OnboardingSlide(
                lines: [
                    "So I thought —",
                    "am I even being present?",
                    "And I made this app."
                ],
                symbol: "paintpalette",
                gradient: [.indigo, .purple]
            ),
            
            // 3 — the canvas
            OnboardingSlide(
                lines: [
                    "It presents each day as a canvas",
                    "you color by doing real things.",
                ],
                symbol: "rectangle.on.rectangle.angled",
                gradient: [.blue, .teal],
                slideType: .canvasDemo
            ),
            
            // 4 — steps
            OnboardingSlide(
                lines: [
                    "Walking adds bright color.",
                    "I need about 7k steps to feel nice.",
                    "How about you?"
                ],
                symbol: "figure.walk",
                gradient: [.green, .mint],
                slideType: .stepsSetup
            ),
            
            // 5 — sleep
            OnboardingSlide(
                lines: [
                    "Sleep adds the dark tones.",
                    "I feel like 9 hours is my sweet spot.",
                    "What about you?"
                ],
                symbol: "moon.zzz",
                gradient: [.indigo, .purple],
                slideType: .sleepSetup
            ),
            
            // 6 — health
            OnboardingSlide(
                lines: [
                    "To color up your canvas",
                    "share your steps and sleep data.",
                ],
                symbol: "heart.text.square",
                gradient: [.pink, .red],
                action: .requestHealth
            ),
            
            // 7 — rays
            OnboardingSlide(
                lines: [
                    "Hitting your sleep and steps targets brings rays.",
                    "Body, mind, heart activities",
                    "give you even more."
                ],
                symbol: "sun.max",
                gradient: [.orange, .yellow],
                slideType: .raysDemo
            ),
            
            // 8 — feeds concept
            OnboardingSlide(
                lines: [
                    "Rays are a currency you earn",
                    "just by being present.",
                    "You can't buy them, but..."
                ],
                symbol: "iphone.slash",
                gradient: [.red, .orange],
                action: .requestFamilyControls
            ),
            
            // 9 — pick app
            OnboardingSlide(
                lines: [
                    "...you can spend them on opening apps.",
                    "Set the first one to try it."
                ],
                symbol: "apps.iphone",
                gradient: [.red, .pink],
                slideType: .feedSelection
            ),
            
            // 10 — notifications
            OnboardingSlide(
                lines: [
                    "To unlock the chosen app",
                    "you'll get a notification.",
                    "Better to allow them."
                ],
                symbol: "bell",
                gradient: [.blue, .cyan],
                action: .requestNotifications
            ),
            
            // 11 — wallpaper
            OnboardingSlide(
                lines: [
                    "Your canvas is different every day.",
                    "You can set it as your wallpaper.",
                    "Pretty convenient and... pretty."
                ],
                symbol: "photo",
                gradient: [.teal, .blue]
            ),
            
            // 12 — login
            OnboardingSlide(
                lines: [
                    "By the way, I'm Konstantin.",
                    "Who are you?"
                ],
                symbol: "person",
                gradient: [.indigo, .purple],
                slideType: .appleLogin
            ),
            
            // 13 — close
            OnboardingSlide(
                lines: [
                    "Welcome to Nowhere"
                ],
                symbol: "eye",
                gradient: [.indigo, .purple]
            )
        ]
    }
}
