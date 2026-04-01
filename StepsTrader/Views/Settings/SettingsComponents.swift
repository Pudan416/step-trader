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
