import SwiftUI

struct SettingsWidgetsWallpaperPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            SettingsDetailBackground(model: model)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    SettingsSectionLabel(text: String(localized: "Widget", comment: "Settings section title"))
                    SettingsGroupedSurface {
                        SettingsWidgetControls()
                            .padding(14)
                    }
                    SettingsSectionLabel(text: String(localized: "Wallpaper", comment: "Settings section title"))
                    SettingsGroupedSurface {
                        SettingsWallpaperControls()
                            .padding(14)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 80)
            }
        }
        .settingsDetailPage(title: String(localized: "Widgets & wallpaper", comment: "Settings row and combined page title"))
    }
}

#Preview {
    NavigationStack {
        SettingsWidgetsWallpaperPage(model: DIContainer.shared.makeAppModel())
    }
}
