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
                slides: OnboardingSlides.makeSlides(),
                accent: AppColors.brandAccent,
                skipText: "Skip",
                nextText: "Next",
                startText: "Let's go",
                allowText: "Allow",
                flowVersion: OnboardingSlides.flowVersion,
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
}

#Preview("Onboarding Demo") {
    OnboardingDemoView()
}
#endif
