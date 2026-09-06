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
                        SettingsWidgetControls(model: model)
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
    @ObservedObject var model: AppModel
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Add a widget"))
                    .font(.geist(.subheadline).weight(.semibold))
                Text(String(localized: "Touch and hold your Home Screen, then tap Edit → Add Widget. Search for Nowhere, choose a size and tap Add Widget."))
                    .font(.geist(.subheadline))
                    .foregroundStyle(theme.adaptiveSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("settings.widgets.addInstructions")

            representativePreview

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

    private var wallpaperStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(wallpaperThumbnail != nil
                 ? String(localized: "A saved wallpaper image is available. This does not confirm that your automation is running.")
                 : String(localized: "Run the wallpaper shortcut to save a background image for your widget."))
                .font(.geist(.caption))
                .foregroundStyle(theme.adaptiveSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                SettingsShortcutPage(model: model)
            } label: {
                Label(String(localized: "Set up wallpaper"), systemImage: "arrow.right.circle")
                    .font(.geist(.subheadline).weight(.semibold))
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("settings.widgets.wallpaperSetup")
        }
    }

    private var representativePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Example widget", comment: "Representative widget preview label"))
                .font(.geist(.caption))
                .foregroundStyle(theme.adaptiveSecondaryText)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(AppColors.brandAccent)
                    Text("60")
                        .font(.geist(.title3).weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .background(Capsule().fill(AppColors.brandAccent))
                    Text("/ 80 / 100")
                        .font(.geist(.subheadline).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule().fill(AppColors.brandAccent.opacity(0.4)).frame(width: geometry.size.width * 0.8)
                        Capsule().fill(AppColors.brandAccent).frame(width: geometry.size.width * 0.6)
                    }
                }
                .frame(height: 14)
                Text(String(localized: "Remaining · Earned · Daily maximum"))
                    .font(.geist(.caption))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(18)
            .background {
                if backgroundMode == "wallpaper" {
                    wallpaperPreview
                } else {
                    RoundedRectangle(cornerRadius: 20).fill(Color(red: 0x22/255, green: 0x28/255, blue: 0x31/255))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Example widget: 60 remaining, 80 earned, 100 daily maximum."))
        }
        .accessibilityIdentifier("settings.widgets.preview")
    }

    private func bgCard<Preview: View>(
        title: String,
        isSelected: Bool,
        value: String,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        Button {
            withMotionAnimation(
                .spring(response: 0.3, dampingFraction: 0.7),
                reduceMotion: reduceMotion
            ) {
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
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.geist(size: 16, weight: .bold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, AppColors.brandAccent)
                                .padding(6)
                        }
                    }

                Text(title)
                    .font(.geist(.caption).weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .settingsSelectable(label: title, isSelected: isSelected)
    }
}

#Preview {
    NavigationStack {
        SettingsWidgetPage(model: DIContainer.shared.makeAppModel())
    }
}
