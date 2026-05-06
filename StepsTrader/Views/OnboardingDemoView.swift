#if DEBUG
import SwiftUI
#if canImport(FamilyControls) && os(iOS)
import FamilyControls
#endif

/// Standalone onboarding preview that runs without AppModel, real permissions,
/// or network calls. Use from Settings → Debug → "Preview Onboarding (Demo)"
/// or directly via SwiftUI Preview.
struct OnboardingDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isPresented = true
    @State private var stepsTarget: Double = 10_000
    @State private var sleepTarget: Double = 8.0
    @State private var onboardingSelection = FamilyActivitySelection()
    @State private var selectedFeedApp: String? = nil
    @State private var bedtimeMinutes: Int = 23 * 60

    var body: some View {
        ZStack {
            OnboardingStoriesView(
                isPresented: $isPresented,
                slides: demoV8Slides(),
                accent: AppColors.brandAccent,
                skipText: "Skip",
                nextText: "Next",
                startText: "Let's go",
                allowText: "Allow",
                flowVersion: "v8-demo",
                onHealthSlide: { print("[Demo] HealthKit requested (no-op)") },
                onNotificationSlide: { print("[Demo] Notifications requested (no-op)") },
                onFamilyControlsSlide: { print("[Demo] Family Controls requested (no-op)") },
                onFinish: {
                    print("[Demo] Onboarding finished — steps: \(Int(stepsTarget)), sleep: \(sleepTarget)h, bedtime: \(bedtimeMinutes)m, feed: \(selectedFeedApp ?? "none")")
                    dismiss()
                },
                model: nil,
                stepsTarget: $stepsTarget,
                sleepTarget: $sleepTarget,
                authService: nil,
                onboardingSelection: $onboardingSelection,
                selectedFeedApp: $selectedFeedApp,
                bedtimeMinutes: $bedtimeMinutes
            )

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 16)
                }
                Spacer()
            }
        }
        .statusBarHidden()
    }

    private func demoV8Slides() -> [OnboardingSlide] {
        [
            OnboardingSlide(
                lines: [
                    "i live mostly online. working. scrolling. staring at a screen.",
                    "probably just like you."
                ],
                slideType: .coldOpen
            ),
            OnboardingSlide(
                lines: [
                    "for me it feels like being stuck in nowhere.",
                    "so i made this app."
                ],
                slideType: .theApp
            ),
            OnboardingSlide(
                lines: [
                    "each day forms a canvas.",
                    "sleep deepens the dark.",
                    "how many hours feel right?"
                ],
                slideType: .canvasSleep
            ),
            OnboardingSlide(
                lines: [
                    "steps brighten it.",
                    "how many steps a day is your goal?"
                ],
                slideType: .canvasSteps
            ),
            OnboardingSlide(
                lines: [],
                slideType: .balance
            ),
            OnboardingSlide(
                lines: [
                    "each day the canvas resets.",
                    "when does your day end?"
                ],
                slideType: .resetBedtime
            ),
            OnboardingSlide(
                lines: [
                    "but the real color comes from what you do.",
                    "body, mind, or heart."
                ],
                slideType: .bodyMindHeart
            ),
            OnboardingSlide(
                lines: [
                    "each day can bring you a maximum of 100 colors — your daily balance.",
                    "20 from each source."
                ],
                slideType: .colorCapV8
            ),
            OnboardingSlide(
                lines: [
                    "to track your colors, the app needs access to apple health.",
                    "we read steps, sleep, and workouts. nothing else."
                ],
                action: .requestHealth,
                microcopy: "you can change this in settings anytime."
            ),
            OnboardingSlide(
                lines: [
                    "you can spend your colors on screen time.",
                    "pick the one app that drains you the most."
                ],
                slideType: .feedSelection,
                microcopy: "this uses apple's screen time. you'll see a system prompt."
            ),
            OnboardingSlide(
                lines: [
                    "also, allow notifications.",
                    "they're needed to unlock the apps.",
                    "you can control them in settings later."
                ],
                action: .requestNotifications,
                slideType: .notificationPermission
            ),
            OnboardingSlide(
                lines: [
                    "btw, my name is kosta.",
                    "and who are you?"
                ],
                slideType: .appleLogin
            ),
            OnboardingSlide(
                lines: [],
                slideType: .welcomeV8
            ),
        ]
    }
}

#Preview("Onboarding Demo") {
    OnboardingDemoView()
}
#endif
