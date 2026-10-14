import SwiftUI

/// Chrome only. Choices and artwork belong to the live HappeningPaletteView.
struct HappeningOnboardingView: View {
    let profile: HappeningPersonalizationProfile
    let onAdvance: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void
    let onCancel: () -> Void
    var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: profile.hasStarted ? "Question \(profile.questionIndex + 1) of 6" : "A few questions first")
                    .font(.onest(.caption))
                Spacer()
                Button(action: onCancel) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Close questions")
                    .accessibilityIdentifier("happenings.onboarding.close")
            }
            Text(verbatim: profile.hasStarted ? profile.question.title : "Find happenings that fit your days")
                .font(.nowhereDisplay(28, relativeTo: .title))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("happenings.onboarding.invitation")
            Text(verbatim: profile.hasStarted ? "Choose any that fit." : "Six short questions. Choose the things that feel familiar.")
                .font(.onest(.footnote))
        }
    }
    var footer: some View {
        VStack(spacing: 10) {
            Button(action: onAdvance) {
                Text(verbatim: profile.hasStarted ? (profile.questionIndex == 5 ? "Find my happenings" : "Continue") : "Start")
                    .font(.onest(17, weight: .medium))
                    .frame(maxWidth: .infinity).frame(minHeight: 48)
                    .foregroundStyle(.white).background(.black, in: Capsule())
            }.accessibilityIdentifier("happenings.onboarding.continue")
            HStack {
                Button(action: onBack) { Text(verbatim: "Back") }
                Spacer()
                Text(verbatim: profile.hasStarted ? "\(profile.selectedChoiceIDs.count) selected" : "Optional")
                    .font(.onest(.caption))
                Spacer()
                Button(action: onSkip) { Text(verbatim: profile.hasStarted ? "Skip" : "Skip questions") }
                    .accessibilityIdentifier("happenings.onboarding.skip")
            }.font(.onest(.footnote)).frame(minHeight: 36)
        }
    }
    var body: some View { header }
}

#if DEBUG
struct HappeningOnboardingDeveloperPage: View {
    var body: some View {
        Form {
            Section {
                Text(verbatim: "Replay the full tour from welcome. At Add happening, + opens six questions in the live Happenings field. Answers update recommendations only. Recorded happenings stay selected and recorded days are kept. After the questions, use your existing day to continue without adding a happening.")
                Button("Start full onboarding from welcome") { HappeningOnboardingCoordinator.shared.replay() }
                    .accessibilityIdentifier("happenings.onboarding.debug.start")
            }
        }.font(.onest(.body))
            .navigationTitle("Happenings onboarding (Debug)")
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
