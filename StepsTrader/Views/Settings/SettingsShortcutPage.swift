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
            setupStep("1", title: String(localized: "Install the shortcut"), detail: String(localized: "Add the Nowhere wallpaper shortcut in Shortcuts, then run it once and allow the requested access."))
            Button { openURL(shortcutURL) } label: {
                Label(String(localized: "Get Wallpaper Shortcut"), systemImage: "square.and.arrow.down")
                    .font(.geist(.subheadline).weight(.semibold))
                    .foregroundStyle(AppAccentInk.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(AppColors.brandAccent))
            }
            .buttonStyle(MattePressStyle())
            .accessibilityIdentifier("settings.wallpaper.install")

            VStack(alignment: .leading, spacing: 20) {
                setupStep("2", title: String(localized: "Create an automation"), detail: String(localized: "In Shortcuts → Automation → +, choose App → Nowhere → Is Closed. Choose Run Immediately (or turn off Ask Before Running), then select the wallpaper shortcut as the action."))
                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label(String(localized: "Open Shortcuts"), systemImage: "arrow.up.forward.app")
                        .font(.geist(.subheadline).weight(.semibold))
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("settings.wallpaper.openShortcuts")
                setupStep("3", title: String(localized: "Check your Lock Screen"), detail: String(localized: "Open Nowhere, then leave the app. Lock your phone and check that the wallpaper changes to today's Canvas. If it does not, run the shortcut manually and check the automation in Shortcuts."))
                SettingsFooter(text: String(localized: "Nowhere cannot check whether a Shortcuts automation is installed or running. A saved wallpaper image only confirms that an image was saved."))
            }
            .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.wallpaper.instructions")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.wallpaper.controls")
    }

    private func setupStep(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.geist(.caption).weight(.bold).monospacedDigit())
                .foregroundStyle(AppColors.brandAccent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(AppColors.brandAccent.opacity(0.15)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.geist(.subheadline).weight(.semibold))
                    .foregroundStyle(theme.adaptivePrimaryText)
                Text(detail)
                    .font(.geist(.subheadline))
                    .foregroundStyle(theme.adaptiveSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

}

#Preview {
    NavigationStack {
        SettingsShortcutPage(model: DIContainer.shared.makeAppModel())
    }
}
