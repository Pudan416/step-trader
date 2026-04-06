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

    var body: some View {
        ZStack {
            OnboardingStoriesView(
                isPresented: $isPresented,
                slides: demoSlides(),
                accent: AppColors.brandAccent,
                skipText: "Skip",
                nextText: "Next",
                startText: "Let's go",
                allowText: "Allow",
                onHealthSlide: { print("[Demo] HealthKit requested (no-op)") },
                onNotificationSlide: { print("[Demo] Notifications requested (no-op)") },
                onFamilyControlsSlide: { print("[Demo] Family Controls requested (no-op)") },
                onFinish: {
                    print("[Demo] Onboarding finished — steps: \(Int(stepsTarget)), sleep: \(sleepTarget)h, feed: \(selectedFeedApp ?? "none")")
                    dismiss()
                },
                model: nil,
                stepsTarget: $stepsTarget,
                sleepTarget: $sleepTarget,
                authService: nil,
                onboardingSelection: $onboardingSelection,
                selectedFeedApp: $selectedFeedApp
            )

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
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

    private func demoSlides() -> [OnboardingSlide] {
        [
            OnboardingSlide(
                lines: [
                    "i found that i live one day over and over.",
                    "working. scrolling. staring at a screen."
                ],
                slideType: .coldOpen
            ),
            OnboardingSlide(
                lines: ["it felt like being stuck in"],
                slideType: .nowHereReveal
            ),
            OnboardingSlide(
                lines: [
                    "your day lives on a canvas.",
                    "the background comes from steps and sleep.",
                    "what colors it are the things you notice."
                ]
            ),
            OnboardingSlide(
                lines: [
                    "one hundred colors. that's a full day.",
                    "tap each to see."
                ],
                slideType: .colorCap
            ),
            OnboardingSlide(
                lines: [
                    "spend them on the apps that pull you away.",
                    "pick how long.",
                    "the clock runs only when the screen is on."
                ],
                slideType: .spendDemo
            ),
            OnboardingSlide(
                lines: [
                    "an economy between online and offline.",
                    "earn by living. spend to scroll.",
                    "tomorrow, it resets."
                ],
                slideType: .howItWorks
            ),
            OnboardingSlide(
                lines: [
                    "walking fills the canvas.",
                    "how far do you go?"
                ],
                slideType: .stepsSetup
            ),
            OnboardingSlide(
                lines: [
                    "sleep deepens the dark.",
                    "how many hours feel right?"
                ],
                slideType: .sleepSetup,
                microcopy: "sleep data may lag a bit — ios updates it on its own schedule."
            ),
            OnboardingSlide(
                lines: [
                    "let your phone see what your body already knows.",
                    "steps, sleep, and the things you notice."
                ],
                action: .requestHealth,
                microcopy: "you'll add activities after."
            ),
            OnboardingSlide(
                lines: [
                    "where does your reality fade?",
                    "close one — or skip for now."
                ],
                slideType: .feedSelection
            ),
            OnboardingSlide(
                lines: [
                    "i'm kosta.",
                    "who are you?"
                ],
                slideType: .appleLogin
            ),
            OnboardingSlide(
                lines: [
                    "set your canvas as a wallpaper.",
                    "add widgets — they update on their own.",
                    "if they feel behind, tap refresh. ios thing."
                ]
            ),
            OnboardingSlide(
                lines: ["welcome to nowhere"],
                slideType: .welcome
            )
        ]
    }
}

#Preview("Onboarding Demo") {
    OnboardingDemoView()
}
#endif
