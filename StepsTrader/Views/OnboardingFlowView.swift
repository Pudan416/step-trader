import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(FamilyControls) && os(iOS)
import FamilyControls
#endif

struct OnboardingFlowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var authService: AuthenticationService
    let onComplete: () -> Void

    @State private var onboardingPresented: Bool = true
    
    @AppStorage(SharedKeys.userStepsTarget) private var stepsTarget: Double = 10_000
    @AppStorage(SharedKeys.userSleepTarget) private var sleepTarget: Double = 8.0
    @State private var onboardingSelection = FamilyActivitySelection()
    @State private var selectedFeedApp: String? = nil
    @State private var onboardingStartedAt = Date()

    var body: some View {
        ZStack {
            OnboardingStoriesView(
                isPresented: $onboardingPresented,
                slides: mainSlides(),
                accent: AppColors.brandAccent,
                skipText: String(localized: "Skip"),
                nextText: String(localized: "Next"),
                startText: String(localized: "Let's go"),
                allowText: String(localized: "Allow"),
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
                authService: authService,
                onboardingSelection: $onboardingSelection,
                selectedFeedApp: $selectedFeedApp
            )
        }
        .transition(.opacity)
        .onAppear { onboardingStartedAt = Date() }
    }

    private func finishOnboarding() {
        let defaults = UserDefaults.stepsTrader()
        defaults.set(stepsTarget, forKey: "userStepsTarget")
        defaults.set(sleepTarget, forKey: "userSleepTarget")
        
        let hasApps = !onboardingSelection.applicationTokens.isEmpty
            || !onboardingSelection.categoryTokens.isEmpty
        if hasApps {
            let name = selectedFeedApp.map { TargetResolver.displayName(for: $0) } ?? String(localized: "My Apps")
            let group = model.createTicketGroup(name: name, templateApp: selectedFeedApp)
            model.addAppsToGroup(group.id, selection: onboardingSelection)
        }
        
        Task { @MainActor in
            model.recalculateDailyEnergy()
        }
        
        let totalDurationMs = Int(Date().timeIntervalSince(onboardingStartedAt) * 1000)
        
        Task {
            await SupabaseSyncService.shared.trackAnalyticsEvent(
                name: "onboarding_completed",
                properties: [
                    "flow": "v7",
                    "steps_target": String(Int(stepsTarget)),
                    "sleep_target": String(format: "%.1f", sleepTarget),
                    "selected_feed": selectedFeedApp ?? "none",
                    "selected_apps_count": String(onboardingSelection.applicationTokens.count),
                    "signed_in": String(authService.isAuthenticated),
                    "skipped_feed_selection": String(!hasApps),
                    "total_duration_ms": String(totalDurationMs)
                ],
                dedupeKey: "onboarding_completed_v1"
            )
        }
        
        // Permissions are requested exactly once on their designated slides.
        // No duplicate requests here.
        
        withAnimation(.easeInOut(duration: 0.3)) {
            onComplete()
        }
    }
    
    // MARK: - v7 Onboarding (13 slides)
    
    private func mainSlides() -> [OnboardingSlide] {
        return [
            // 0 — recognition
            OnboardingSlide(
                lines: [
                    String(localized: "i found that i live one day over and over."),
                    String(localized: "working. scrolling. staring at a screen.")
                ],
                slideType: .coldOpen
            ),
            
            // 1 — nowhere → now here (the turn)
            OnboardingSlide(
                lines: [
                    String(localized: "it felt like being stuck in")
                ],
                slideType: .nowHereReveal
            ),
            
            // 2 — the canvas concept
            OnboardingSlide(
                lines: [
                    String(localized: "your day lives on a canvas."),
                    String(localized: "the background comes from steps and sleep."),
                    String(localized: "what colors it are the things you notice.")
                ]
            ),
            
            // 3 — color cap (interactive — tap 5 orbs)
            OnboardingSlide(
                lines: [
                    String(localized: "one hundred colors. that's a full day."),
                    String(localized: "tap each to see.")
                ],
                slideType: .colorCap
            ),
            
            // 4 — spend demo (feeds-style — the cost)
            OnboardingSlide(
                lines: [
                    String(localized: "spend them on the apps that pull you away."),
                    String(localized: "pick how long."),
                    String(localized: "the time runs only when the app is being used.")
                ],
                slideType: .spendDemo
            ),
            
            // 5 — the economy
            OnboardingSlide(
                lines: [
                    String(localized: "an economy between online and offline."),
                    String(localized: "earn by living. spend to scroll."),
                    String(localized: "tomorrow, it resets.")
                ],
                slideType: .howItWorks
            ),
            
            // 6 — steps target
            OnboardingSlide(
                lines: [
                    String(localized: "walking fills the canvas."),
                    String(localized: "how far do you go?")
                ],
                slideType: .stepsSetup
            ),
            
            // 7 — sleep target
            OnboardingSlide(
                lines: [
                    String(localized: "sleep deepens the dark."),
                    String(localized: "how many hours feel right?")
                ],
                slideType: .sleepSetup,
                microcopy: String(localized: "sleep data may lag a bit — ios updates it on its own schedule.")
            ),
            
            // 8 — health permission
            OnboardingSlide(
                lines: [
                    String(localized: "let your phone see what your body already knows."),
                    String(localized: "steps, sleep, and the things you notice.")
                ],
                action: .requestHealth,
                microcopy: String(localized: "you'll add activities after.")
            ),
            
            // 9 — feed selection (skippable)
            OnboardingSlide(
                lines: [
                    String(localized: "where does your reality fade?"),
                    String(localized: "close one — or skip for now.")
                ],
                slideType: .feedSelection
            ),
            
            // 10 — identity
            OnboardingSlide(
                lines: [
                    String(localized: "i'm kosta."),
                    String(localized: "who are you?")
                ],
                slideType: .appleLogin
            ),
            
            // 11 — make it yours
            OnboardingSlide(
                lines: [
                    String(localized: "set your canvas as a wallpaper."),
                    String(localized: "add widgets — they update on their own."),
                    String(localized: "if they feel behind, tap refresh. ios thing.")
                ]
            ),
            
            // 12 — welcome
            OnboardingSlide(
                lines: [String(localized: "welcome to nowhere")],
                slideType: .welcome
            )
        ]
    }
}
