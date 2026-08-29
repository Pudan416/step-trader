import SwiftUI

struct SettingsShortcutPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            SettingsDetailBackground(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsGroupedSurface {
                        SettingsWallpaperControls()
                            .padding(14)
                    }
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 80)
            }
        }
        .overlay { }
        .settingsDetailPage(title: String(localized: "Wallpaper", comment: "Settings section title"))
    }
}

struct SettingsWallpaperControls: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.appTheme) private var theme

    private let shortcutURL = AppConstants.URLs.wallpaperShortcut
    private let steps: [(number: String, text: LocalizedStringKey)] = [
        ("1", "Tap the button below to add the wallpaper shortcut"),
        ("2", "Open Shortcuts → Automation → +"),
        ("3", "Choose App → select Nowhere → pick \"Is Closed\""),
        ("4", "Set the action to the wallpaper shortcut"),
        ("5", "Turn off \"Ask Before Running\""),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Label(String(localized: "Auto-wallpaper"), systemImage: "sparkles")
                    .font(.geist(.subheadline).weight(.semibold))
                    .foregroundStyle(theme.adaptivePrimaryText)
                Text(String(localized: "Set today's energy canvas as your Lock Screen wallpaper automatically each time you close the app."))
                    .font(.geist(.subheadline))
                    .foregroundStyle(theme.adaptiveSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 0) {
                SettingsSectionLabel(text: String(localized: "Setup", comment: "Wallpaper section header"))
                    .padding(.bottom, 10)
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 { DetailDivider() }
                    HStack(alignment: .top, spacing: 12) {
                        Text(step.number)
                            .font(.geist(.caption).weight(.bold).monospacedDigit())
                            .foregroundStyle(AppColors.brandAccent)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(AppColors.brandAccent.opacity(0.15)))
                        Text(step.text)
                            .font(.geist(.subheadline))
                            .foregroundStyle(theme.adaptiveSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 10)
                }
            }
            Button { openURL(shortcutURL) } label: {
                Label(String(localized: "Get Wallpaper Shortcut"), systemImage: "square.and.arrow.down")
                    .font(.geist(.subheadline).weight(.semibold))
                    .foregroundStyle(AppAccentInk.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(AppColors.brandAccent))
            }
            .buttonStyle(MattePressStyle())
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.wallpaper.controls")
    }
}

#Preview {
    NavigationStack {
        SettingsShortcutPage(model: DIContainer.shared.makeAppModel())
    }
}
