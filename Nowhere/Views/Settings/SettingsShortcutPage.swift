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
            Button { openURL(shortcutURL) } label: {
                SettingsActionLabel(title: String(localized: "Install wallpaper shortcut"), icon: "square.and.arrow.down")
            }
            .buttonStyle(MattePressStyle())
            .accessibilityIdentifier("settings.wallpaper.install")

            DisclosureGroup(String(localized: "Setup")) {
                VStack(alignment: .leading, spacing: 16) {
                    setupStep("1", title: String(localized: "Run once"), detail: String(localized: "Run the installed shortcut and allow access."))
                    setupStep("2", title: String(localized: "Create an automation"), detail: String(localized: "Shortcuts → Automation → Nowhere → Is Closed → Run Immediately. Add the wallpaper shortcut."))
                    Button {
                        if let url = URL(string: "shortcuts://") { openURL(url) }
                    } label: {
                        Label(String(localized: "Open Shortcuts"), systemImage: "arrow.up.forward.app")
                            .font(.geist(.subheadline).weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("settings.wallpaper.openShortcuts")
                    setupStep("3", title: String(localized: "Check your Lock Screen"), detail: String(localized: "Leave Nowhere, then lock your phone."))
                }
                .padding(.top, 12)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("settings.wallpaper.instructions")
            .tint(.white)
            .environment(\.colorScheme, .dark)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.wallpaper.controls")
        .foregroundStyle(.white)
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
                    .foregroundStyle(.white)
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
