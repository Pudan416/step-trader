import SwiftUI
#if canImport(FamilyControls) && os(iOS)
import FamilyControls
#endif

struct OnboardingFlowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var authService: AuthenticationService
    /// Shows the top-left "Skip onboarding" shortcut on every slide. Off by
    /// default so the real first-run flow never exposes it (even in DEBUG
    /// builds); the Settings → replay/demo entry point opts in.
    var showsDebugSkip: Bool = false
    let onComplete: () -> Void

    @State private var onboardingPresented: Bool = true
    
    @AppStorage(SharedKeys.userStepsTarget, store: UserDefaults.stepsTrader()) private var stepsTarget: Double = 10_000
    @AppStorage(SharedKeys.userSleepTarget, store: UserDefaults.stepsTrader()) private var sleepTarget: Double = 8.0
    @State private var onboardingSelection = FamilyActivitySelection()
    @State private var selectedFeedApp: String? = nil
    @State private var onboardingStartedAt = Date.now
    /// Default to 23:00. If the user skips the bedtime slide, we still commit a sensible
    /// value (instead of midnight, which silently sliced the day at the wrong boundary).
    @State private var bedtimeMinutes: Int = 23 * 60

    var body: some View {
        ZStack {
            OnboardingStoriesView(
                isPresented: $onboardingPresented,
                slides: OnboardingSlides.makeSlides(),
                accent: AppColors.brandAccent,
                skipText: String(localized: "Skip"),
                nextText: String(localized: "Next"),
                startText: String(localized: "Let's go"),
                allowText: String(localized: "Allow"),
                flowVersion: OnboardingSlides.flowVersion,
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
                bedtimeMinutes: $bedtimeMinutes,
                showsDebugSkipAll: showsDebugSkip
            )
        }
        .transition(.opacity)
        .onAppear { onboardingStartedAt = Date.now }
    }

    private func finishOnboarding() {
        let defaults = UserDefaults.stepsTrader()
        let dayEndHour = bedtimeMinutes / 60
        let dayEndMinute = bedtimeMinutes % 60
        defaults.set(dayEndHour, forKey: SharedKeys.dayEndHour)
        defaults.set(dayEndMinute, forKey: SharedKeys.dayEndMinute)
        
        let hasApps = !onboardingSelection.applicationTokens.isEmpty
            || !onboardingSelection.categoryTokens.isEmpty
        if hasApps {
            let name = selectedFeedApp.map { TargetResolver.displayName(for: $0) } ?? String(localized: "My Apps")
            let group = model.createTicketGroup(name: name, templateApp: selectedFeedApp)
            model.addAppsToGroup(group.id, selection: onboardingSelection)
        }
        
        Task { @MainActor in
            model.updateDayEnd(hour: dayEndHour, minute: dayEndMinute)
        }
        
        let totalDurationMs = Int(Date.now.timeIntervalSince(onboardingStartedAt) * 1000)
        
        Task {
            await SupabaseSyncService.shared.trackAnalyticsEvent(
                name: "onboarding_completed",
                properties: [
                    "flow": OnboardingSlides.flowVersion,
                    "steps_target": String(Int(stepsTarget)),
                    "sleep_target": sleepTarget.formatted(.number.precision(.fractionLength(1))),
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
}

#Preview {
    OnboardingFlowView(
        model: DIContainer.shared.makeAppModel(),
        authService: AuthenticationService.shared,
        onComplete: {}
    )
}
