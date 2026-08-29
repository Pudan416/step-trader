import SwiftUI

struct SettingsWidgetsWallpaperPage: View {
    @ObservedObject var model: AppModel
    @Environment(\.topCardHeight) private var topCardHeight

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    SettingsSectionLabel(text: String(localized: "Widget", comment: "Settings section title"))
                    SettingsWidgetControls()
                    DetailDivider()
                    SettingsSectionLabel(text: String(localized: "Wallpaper", comment: "Settings section title"))
                    SettingsWallpaperControls()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 80)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .navigationTitle(String(localized: "Widgets & wallpaper", comment: "Settings row and combined page title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsWidgetsWallpaperPage(model: DIContainer.shared.makeAppModel())
    }
}
