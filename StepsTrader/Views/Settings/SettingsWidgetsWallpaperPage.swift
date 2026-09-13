import SwiftUI

/// Compatibility entry point; installation flows stay on separate destinations.
struct SettingsWidgetsWallpaperPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            SettingsDetailBackground(model: model)
            VStack {
                SettingsGroupedSurface {
                    NavigationLink { SettingsWidgetPage(model: model) } label: {
                        SettingsNavRow(icon: "rectangle.grid.1x2", title: String(localized: "Widgets"))
                    }
                    DetailDivider()
                    NavigationLink { SettingsShortcutPage(model: model) } label: {
                        SettingsNavRow(icon: "photo", title: String(localized: "Wallpaper"))
                    }
                }
                .padding(16)
                Spacer()
            }
        }
        .settingsDetailPage(title: String(localized: "Home Screen"))
    }
}
