import SwiftUI
import WidgetKit

struct SettingsWidgetPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            SettingsDetailBackground(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsGroupedSurface {
                        SettingsWidgetControls()
                            .padding(14)
                    }
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 80)
            }
        }
        .overlay { }
        .settingsDetailPage(title: String(localized: "Widget", comment: "Settings section title"))
    }
}

struct SettingsWidgetControls: View {
    @Environment(\.appTheme) private var theme
    @AppStorage(
        SharedKeys.widgetBackgroundMode,
        store: UserDefaults(suiteName: SharedKeys.appGroupId)
    ) private var backgroundMode: String = "basic"

    private var wallpaperThumbnail: UIImage? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedKeys.appGroupId
        ) else { return nil }
        let url = container
            .appendingPathComponent("widget_snapshots", isDirectory: true)
            .appendingPathComponent("wallpaper_bg.jpg")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsSectionLabel(text: String(localized: "Background", comment: "Widget section header"))
                    .padding(.bottom, 12)
                HStack(spacing: 12) {
                    bgCard(
                        title: String(localized: "Solid", comment: "Widget background style"),
                        isSelected: backgroundMode == "basic",
                        value: "basic"
                    ) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 0x22/255, green: 0x28/255, blue: 0x31/255))
                    }
                    bgCard(
                        title: String(localized: "Wallpaper", comment: "Widget background style"),
                        isSelected: backgroundMode == "wallpaper",
                        value: "wallpaper"
                    ) {
                        wallpaperPreview
                    }
                }
                if backgroundMode == "wallpaper" {
                    DetailDivider()
                    wallpaperStatus.padding(.vertical, 12)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.tap")
                    .font(.geist(size: 15))
                    .foregroundStyle(theme.adaptiveSecondaryText)
                    .frame(width: 24)
                Text(String(localized: "Long-press the widget → Edit to choose which group to display."))
                    .font(.geist(.caption))
                    .foregroundStyle(theme.adaptiveSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.widgets.controls")
        .onChange(of: backgroundMode) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: backgroundMode)
    }

    @ViewBuilder
    private var wallpaperPreview: some View {
        if let thumb = wallpaperThumbnail {
            Image(uiImage: thumb)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay { Color.black.opacity(0.3) }
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.4), .orange.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Image(systemName: "photo")
                        .font(.geist(size: 14, weight: .light))
                        .foregroundStyle(.white.opacity(0.5))
                }
        }
    }

    @ViewBuilder
    private var wallpaperStatus: some View {
        if wallpaperThumbnail != nil {
            Label(String(localized: "Synced with wallpaper shortcut"), systemImage: "checkmark.circle.fill")
                .font(.geist(.caption))
                .foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label(String(localized: "Set up the wallpaper shortcut first"), systemImage: "arrow.right.circle")
                    .font(.geist(.caption))
                    .foregroundStyle(AppColors.brandAccent)
                Text(String(localized: "Updates automatically each time the wallpaper shortcut runs."))
                    .font(.geist(.caption2))
                    .foregroundStyle(theme.adaptiveSecondaryText)
            }
        }
    }

    private func bgCard<Preview: View>(
        title: String,
        isSelected: Bool,
        value: String,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                backgroundMode = value
            }
        } label: {
            VStack(spacing: 8) {
                preview()
                    .frame(height: 72)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isSelected ? AppColors.brandAccent : Color.clear,
                                lineWidth: 2
                            )
                    }

                Text(title)
                    .font(.geist(.caption).weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        SettingsWidgetPage(model: DIContainer.shared.makeAppModel())
    }
}
