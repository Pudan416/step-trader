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
                .font(.onest(.title3).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("happenings.onboarding.invitation")
            if !profile.hasStarted {
                Text(verbatim: "Six short questions. Choose the things that feel familiar.")
                    .font(.geist(.callout))
            }
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
                Button(action: onSkip) { Text(verbatim: profile.hasStarted ? "Skip" : "Skip questions") }
                    .accessibilityIdentifier("happenings.onboarding.skip")
            }.font(.onest(.footnote)).frame(minHeight: 36)
        }
    }
    var body: some View { header }
}

/// Shares the surrounding tour's card typography and padding. Measuring its
/// destination up front keeps the first and last All reveal frames identical.
struct HappeningTodayChoiceCoach: View {
    static let title = "Choose one thing you’ve done today."

    static func idealHeight(width: CGFloat, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let font = AppTypography.scaledUIFont(size: 20, weight: .semibold, relativeTo: .title3,
            compatibleWith: UITraitCollection(preferredContentSizeCategory:
                HappeningFieldLabelTypography.contentSizeCategory(for: dynamicTypeSize)))
        let textWidth = max(1, min(360, width - 32) - 40)
        let bounds = (title as NSString).boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
        return ceil(bounds.height) + 40
    }

    var body: some View {
        Text(verbatim: Self.title)
            .font(.onest(20, weight: .semibold, relativeTo: .title3))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("happenings.onboarding.chooseToday")
    }
}

#if DEBUG
struct HappeningOnboardingDeveloperPage: View {
    var body: some View {
        Form {
            Section {
                Text(verbatim: "Replay the full tour from welcome. At Add happening, + opens six questions in the live Happenings field. Answers update recommendations only. Recorded happenings stay selected and recorded days are kept. After the questions, tap a real happening to continue. Tapping one already recorded keeps it in your day.")
                Button("Start full onboarding from welcome") { HappeningOnboardingCoordinator.shared.replay() }
                    .accessibilityIdentifier("happenings.onboarding.debug.start")
            }
        }.font(.onest(.body))
            .navigationTitle("Happenings onboarding (Debug)")
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
