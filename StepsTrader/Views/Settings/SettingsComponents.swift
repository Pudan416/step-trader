import SwiftUI

// MARK: - Detail page header (replaces hidden nav bar)

struct DetailHeader: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "Back", comment: "SettingsComponents – back button label"))
                        .font(.subheadline)
                }
                .foregroundStyle(theme.adaptivePrimaryText)
            }
            Spacer()
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.adaptivePrimaryText)
            Spacer()
            Color.clear.frame(width: 50, height: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

// MARK: - Shared detail page helpers

struct DetailDivider: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.adaptiveDividerColor)
            .frame(height: 0.5)
            .padding(.leading, 14)
    }
}

struct DetailInfoRow: View {
    let label: String
    let value: String
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(theme.adaptivePrimaryText)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(theme.adaptiveSecondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Section label (consistent across all settings pages)

struct SettingsSectionLabel: View {
    let text: String
    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(theme.adaptiveMutedText)
            .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Toggle row (consistent across settings pages)

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    var subtitle: String? = nil
    @Environment(\.appTheme) private var theme

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(theme.adaptiveSecondaryText)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(theme.adaptivePrimaryText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(theme.adaptiveSecondaryText)
                    }
                }
            }
        }
        .tint(AppColors.brandAccent)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Navigation row inside a glass card

struct SettingsNavRow: View {
    let icon: String
    let title: String
    var value: String? = nil
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(theme.adaptiveSecondaryText)
                .frame(width: 24)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(theme.adaptivePrimaryText)
            Spacer()
            if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(theme.adaptiveSecondaryText)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.adaptiveMutedText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

// MARK: - Link row (tappable external link)

struct SettingsLinkRow: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var trailingIcon: String = "arrow.up.right"
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(theme.adaptiveSecondaryText)
                .frame(width: 24)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(theme.adaptivePrimaryText)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(theme.adaptiveSecondaryText)
            }
            Image(systemName: trailingIcon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.adaptiveMutedText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

// MARK: - Footer hint text

struct SettingsFooter: View {
    let text: String
    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(theme.adaptiveSecondaryText)
            .padding(.horizontal, 4)
    }
}

// MARK: - Shared gradient background for detail pages

struct SettingsGradientBG: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Color.clear.energyGradientBackground(model: model)
    }
}

// MARK: - Gradient preview config

struct GradientPreviewConfig: Identifiable {
    let id = UUID()
    let style: GradientStyle
}
