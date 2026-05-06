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
    @State private var bedtimeMinutes: Int = 0

    @AppStorage("onboardingFlowVersion") private var flowVersionOverride: String = ""

    private var useV8Flow: Bool {
        if !flowVersionOverride.isEmpty { return flowVersionOverride == "v8" }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private var currentFlowVersion: String {
        useV8Flow ? "v8" : "v7"
    }

    var body: some View {
        ZStack {
            let slides = useV8Flow ? v8Slides() : mainSlides()
            OnboardingStoriesView(
                isPresented: $onboardingPresented,
                slides: slides,
                accent: AppColors.brandAccent,
                skipText: String(localized: "Skip"),
                nextText: String(localized: "Next"),
                startText: String(localized: "Let's go"),
                allowText: String(localized: "Allow"),
                flowVersion: currentFlowVersion,
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
                selectedFeedApp: $selectedFeedApp,
                bedtimeMinutes: $bedtimeMinutes
            )
        }
        .transition(.opacity)
        .onAppear { onboardingStartedAt = Date() }
    }

    private func finishOnboarding() {
        let defaults = UserDefaults.stepsTrader()
        defaults.set(stepsTarget, forKey: "userStepsTarget")
        defaults.set(sleepTarget, forKey: "userSleepTarget")
        defaults.set(bedtimeMinutes / 60, forKey: SharedKeys.dayEndHour)
        defaults.set(bedtimeMinutes % 60, forKey: SharedKeys.dayEndMinute)
        
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
                    "flow": currentFlowVersion,
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
    
    // MARK: - v8 Onboarding (13 slides)

    private func v8Slides() -> [OnboardingSlide] {
        [
            // 0 — recognition
            OnboardingSlide(
                lines: [
                    String(localized: "i live mostly online. working. scrolling. staring at a screen."),
                    String(localized: "probably just like you.")
                ],
                slideType: .coldOpen
            ),

            // 1 — the app
            OnboardingSlide(
                lines: [
                    String(localized: "for me it feels like being stuck in nowhere."),
                    String(localized: "so i made this app.")
                ],
                slideType: .theApp
            ),

            // 2 — canvas + sleep
            OnboardingSlide(
                lines: [
                    String(localized: "each day forms a canvas."),
                    String(localized: "sleep deepens the dark."),
                    String(localized: "how many hours of sleep you need?")
                ],
                slideType: .canvasSleep
            ),

            // 3 — canvas + steps
            OnboardingSlide(
                lines: [
                    String(localized: "steps brighten it."),
                    String(localized: "how many steps a day is your goal?")
                ],
                slideType: .canvasSteps
            ),

            // 4 — reset + bedtime
            OnboardingSlide(
                lines: [
                    String(localized: "each day the canvas resets."),
                    String(localized: "when does your day end?")
                ],
                slideType: .resetBedtime
            ),

            // 5 — balance (summary)
            OnboardingSlide(
                lines: [],
                slideType: .balance
            ),

            // 6 — body, mind, heart
            OnboardingSlide(
                lines: [
                    String(localized: "but what truly colors your canvas is what you do for your body, mind, and heart.")
                ],
                slideType: .bodyMindHeart
            ),

            // 7 — color cap
            OnboardingSlide(
                lines: [
                    String(localized: "colors are the currency you earn for living a real life."),
                    String(localized: "each day can bring you a maximum of")
                ],
                slideType: .colorCapV8
            ),

            // 8 — health permission (pre-permission context)
            OnboardingSlide(
                lines: [
                    String(localized: "the app needs access to apple health."),
                    String(localized: "we read steps, sleep, and workouts. nothing else.")
                ],
                action: .requestHealth,
                microcopy: String(localized: "you can change this in settings anytime.")
            ),

            // 9 — feed selection (with spend context + pre-permission)
            OnboardingSlide(
                lines: [
                    String(localized: "you can spend your colors on screen time."),
                    String(localized: "pick the one app that drains you the most.")
                ],
                slideType: .feedSelection,
                microcopy: String(localized: "this uses apple's screen time. you'll see a system prompt.")
            ),

            // 11 — notifications
            OnboardingSlide(
                lines: [
                    String(localized: "also, allow notifications."),
                    String(localized: "they're needed to unlock the apps."),
                    String(localized: "you can control them in settings later.")
                ],
                action: .requestNotifications,
                slideType: .notificationPermission
            ),

            // 12 — identity (unskippable)
            OnboardingSlide(
                lines: [
                    String(localized: "btw, my name is kosta."),
                    String(localized: "and who are you?")
                ],
                slideType: .appleLogin
            ),

            // 13 — welcome
            OnboardingSlide(
                lines: [],
                slideType: .welcomeV8
            ),
        ]
    }

    // MARK: - v7 Onboarding (11 slides)
    
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

            // 2 — color cap (interactive — tap 5 orbs)
            OnboardingSlide(
                lines: [
                    String(localized: "each day you get 100 colors — your daily balance."),
                    String(localized: "earn them by living. spend them to scroll."),
                    String(localized: "tap each to see.")
                ],
                slideType: .colorCap
            ),
            
            // 3 — spend demo (feeds-style — the cost)
            OnboardingSlide(
                lines: [
                    String(localized: "spend them on the apps that pull you away."),
                    String(localized: "pick how long."),
                    String(localized: "the time runs only when the app is being used.")
                ],
                slideType: .spendDemo
            ),
            
            // 4 — the economy
            OnboardingSlide(
                lines: [
                    String(localized: "an economy between online and offline."),
                    String(localized: "earn by living. spend to scroll."),
                    String(localized: "tomorrow, it resets.")
                ],
                slideType: .howItWorks
            ),
            
            // 5 — steps target
            OnboardingSlide(
                lines: [
                    String(localized: "walking fills the canvas."),
                    String(localized: "how far do you go?")
                ],
                slideType: .stepsSetup
            ),
            
            // 6 — sleep target
            OnboardingSlide(
                lines: [
                    String(localized: "sleep deepens the dark."),
                    String(localized: "how many hours feel right?")
                ],
                slideType: .sleepSetup,
                microcopy: String(localized: "sleep data may lag a bit — ios updates it on its own schedule.")
            ),
            
            // 7 — health permission (pre-permission context)
            OnboardingSlide(
                lines: [
                    String(localized: "to track your colors, the app needs access to apple health."),
                    String(localized: "we read steps, sleep, and workouts. nothing else.")
                ],
                action: .requestHealth,
                microcopy: String(localized: "you can change this in settings anytime.")
            ),
            
            // 8 — feed selection (skippable, pre-permission context)
            OnboardingSlide(
                lines: [
                    String(localized: "which app pulls you away the most?"),
                    String(localized: "pick one to manage with your colors — or skip for now.")
                ],
                slideType: .feedSelection,
                microcopy: String(localized: "this uses apple's screen time. you'll see a system prompt.")
            ),
            
            // 9 — identity
            OnboardingSlide(
                lines: [
                    String(localized: "i'm kosta."),
                    String(localized: "who are you?")
                ],
                slideType: .appleLogin
            ),
            
            // 10 — welcome
            OnboardingSlide(
                lines: [String(localized: "welcome to nowhere")],
                slideType: .welcome
            )
        ]
    }
}
