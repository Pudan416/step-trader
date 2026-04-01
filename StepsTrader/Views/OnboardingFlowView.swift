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
                    "flow": "v5",
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
    
    // MARK: - v5 Onboarding (13 slides — interactive demo-first flow)
    
    private func mainSlides() -> [OnboardingSlide] {
        return [
            // 1 — cold open (emotional hook)
            OnboardingSlide(
                lines: [
                    String(localized: "i keep ending days i never touched.")
                ],
                slideType: .coldOpen
            ),
            
            // 2 — the canvas (concept)
            OnboardingSlide(
                lines: [
                    String(localized: "i wanted a mirror"),
                    String(localized: "that could hold a whole day."),
                    String(localized: "not a dashboard. not a score.")
                ],
                slideType: .theCanvas
            ),
            
            // 3 — paint demo (interactive — user paints their first canvas)
            OnboardingSlide(
                lines: [
                    String(localized: "swipe to color it.")
                ],
                slideType: .paintDemo
            ),
            
            // 4 — the cap (interactive — tap 5 orbs to discover 100 colors)
            OnboardingSlide(
                lines: [
                    String(localized: "one hundred colors. that's a full day."),
                    String(localized: "tap each to see.")
                ],
                slideType: .colorCap
            ),
            
            // 5 — spend demo (interactive — tap to unlock, see depletion)
            OnboardingSlide(
                lines: [
                    String(localized: "spend what you lived"),
                    String(localized: "to open what you chose to close.")
                ],
                slideType: .spendDemo
            ),
            
            // 6 — the loop (animated summary: earn → spend → reset)
            OnboardingSlide(
                lines: [
                    String(localized: "every morning, empty."),
                    String(localized: "earn colors by living."),
                    String(localized: "spend them to scroll.")
                ],
                slideType: .howItWorks
            ),
            
            // 7 — steps setup
            OnboardingSlide(
                lines: [
                    String(localized: "walking brightens the canvas."),
                    String(localized: "set your target.")
                ],
                slideType: .stepsSetup
            ),
            
            // 8 — sleep setup
            OnboardingSlide(
                lines: [
                    String(localized: "sleep lays down the dark."),
                    String(localized: "how much rest colors the night?")
                ],
                slideType: .sleepSetup
            ),
            
            // 9 — health permission
            OnboardingSlide(
                lines: [
                    String(localized: "to paint your real day,"),
                    String(localized: "share what your body already knows.")
                ],
                action: .requestHealth,
                microcopy: String(localized: "steps and sleep — you can change this later")
            ),
            
            // 10 — feed selection (skippable, bundles Family Controls + Notifications)
            OnboardingSlide(
                lines: [
                    String(localized: "what pulls you when you're tired?"),
                    String(localized: "pick an app to close — or skip for now.")
                ],
                slideType: .feedSelection
            ),
            
            // 11 — nowhere → now here (earned reveal)
            OnboardingSlide(
                lines: [
                    String(localized: "i called it nowhere."),
                    String(localized: "i still read it as now here.")
                ],
                slideType: .nowHereReveal
            ),
            
            // 12 — identity
            OnboardingSlide(
                lines: [
                    String(localized: "i'm kosta."),
                    String(localized: "who are you?")
                ],
                slideType: .appleLogin
            ),
            
            // 13 — welcome
            OnboardingSlide(
                lines: [String(localized: "welcome to nowhere")],
                slideType: .welcome
            )
        ]
    }
}
