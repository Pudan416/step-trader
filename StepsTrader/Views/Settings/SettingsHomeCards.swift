import SwiftUI

struct SettingsAccountCardLabel: View {
    let presentation: SettingsAccountPresentation
    @Environment(\.appTheme) private var theme

    private var title: String {
        switch presentation {
        case .signedOut:
            String(localized: "Sign in with Apple", comment: "Settings signed-out account card title")
        case let .signedIn(displayName, _, _):
            displayName
        }
    }

    private var subtitle: String {
        switch presentation {
        case .signedOut:
            String(localized: "Sync settings and history across devices", comment: "Settings signed-out account card subtitle")
        case .signedIn:
            String(localized: "Automatic sync on", comment: "Settings signed-in account card subtitle")
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.adaptivePrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(theme.adaptiveSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.adaptiveMutedText.opacity(0.7))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .contentShape(Rectangle())
        .settingsCardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
    }

    @ViewBuilder
    private var avatar: some View {
        switch presentation {
        case .signedOut:
            ZStack {
                Circle()
                    .fill(theme.adaptivePrimaryText.opacity(0.08))
                Image(systemName: "apple.logo")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(theme.adaptivePrimaryText)
            }
            .frame(width: 56, height: 56)
            .accessibilityHidden(true)

        case let .signedIn(_, initials, avatarData):
            if let avatarData, let image = UIImage(data: avatarData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
            } else {
                ZStack {
                    Circle()
                        .fill(theme.adaptivePrimaryText.opacity(0.08))
                    Text(initials)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(theme.adaptivePrimaryText)
                }
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            }
        }
    }
}

struct SettingsYourDayCardLabel: View {
    let summary: SettingsYourDaySummary
    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var title: String {
        String(localized: "Your day", comment: "Settings Your day card title")
    }

    private var stepsLabel: String {
        String(localized: "Steps", comment: "Settings Your day steps metric label")
    }

    private var sleepLabel: String {
        String(localized: "Sleep", comment: "Settings Your day sleep metric label")
    }

    private var newDayLabel: String {
        String(localized: "New day", comment: "Settings Your day boundary metric label")
    }

    private var accessibilitySummary: String {
        String(
            localized: "\(summary.stepsText()) steps, \(summary.sleepText()) sleep, \(summary.dayStartText()) new day",
            comment: "Settings Your day card accessibility summary"
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(theme.adaptivePrimaryText)
                .padding(.bottom, 24)

            metrics

            Spacer(minLength: 20)

            Rectangle()
                .fill(theme.adaptiveDividerColor.opacity(0.6))
                .frame(height: 0.5)
                .accessibilityHidden(true)

            HStack {
                Text(String(localized: "Goals & schedule", comment: "Settings Your day card action"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.adaptivePrimaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.adaptiveMutedText.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .contentShape(Rectangle())
        .settingsCardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilitySummary)
    }

    @ViewBuilder
    private var metrics: some View {
        if SettingsYourDayLayout.stacksMetrics(for: dynamicTypeSize) {
            VStack(spacing: 12) {
                stackedMetric(value: summary.stepsText(), label: stepsLabel)
                stackedMetric(value: summary.sleepText(), label: sleepLabel)
                stackedMetric(value: summary.dayStartText(), label: newDayLabel)
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                metric(value: summary.stepsText(), label: stepsLabel)
                metric(value: summary.sleepText(), label: sleepLabel)
                metric(value: summary.dayStartText(), label: newDayLabel)
            }
        }
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundStyle(theme.adaptivePrimaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(SettingsLocalizedCasing.uppercase(label))
                .font(.caption2.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(
                    theme.adaptivePrimaryText.opacity(SettingsCardAppearance.captionOpacity)
                )
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stackedMetric(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(SettingsLocalizedCasing.uppercase(label))
                .font(.caption2.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(
                    theme.adaptivePrimaryText.opacity(SettingsCardAppearance.captionOpacity)
                )
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(value)
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundStyle(theme.adaptivePrimaryText)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SettingsDestinationCardLabel: View {
    let icon: String
    let title: String
    var warningText: String? = nil
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.adaptiveSecondaryText)
                .frame(width: 38, height: 38)
                .background(theme.adaptivePrimaryText.opacity(0.07), in: Circle())
                .accessibilityHidden(true)

            if let warningText {
                Text(SettingsLocalizedCasing.uppercase(warningText))
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            HStack(alignment: .bottom, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.adaptivePrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.adaptiveMutedText.opacity(0.7))
                    .accessibilityHidden(true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .contentShape(Rectangle())
        .settingsCardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(warningText ?? "")
    }
}

struct SettingsInformationGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .settingsCardSurface()
    }
}
