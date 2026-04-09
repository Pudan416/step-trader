import SwiftUI
import WidgetKit

struct SettingsWidgetPage: View {
    @ObservedObject var model: AppModel
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.appTheme) private var theme

    @AppStorage(SharedKeys.widgetBackgroundMode, store: UserDefaults(suiteName: SharedKeys.appGroupId))
    private var backgroundMode: String = "basic"

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
        ZStack {
            SettingsGradientBG(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DetailHeader(title: String(localized: "Widget", comment: "Settings section title"))
                        .padding(.horizontal, 16)

                    // MARK: - Background Picker
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionLabel(text: String(localized: "BACKGROUND", comment: "Widget section header"))
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                            .padding(.bottom, 10)

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
                                if let thumb = wallpaperThumbnail {
                                    Image(uiImage: thumb)
                                        .resizable()
                                        .scaledToFill()
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(Color.black.opacity(0.3))
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
                                        .overlay(
                                            Image(systemName: "photo")
                                                .font(.system(size: 14, weight: .light))
                                                .foregroundStyle(.white.opacity(0.5))
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)

                        if backgroundMode == "wallpaper" {
                            DetailDivider()
                            wallpaperStatus
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                        }
                    }
                    .glassCard()
                    .padding(.horizontal, 16)

                    // MARK: - Configuration Hint
                    HStack(spacing: 10) {
                        Image(systemName: "hand.tap")
                            .font(.system(size: 15))
                            .foregroundStyle(theme.adaptiveSecondaryText)
                            .frame(width: 24)
                        Text(String(localized: "Long-press the widget → Edit to choose which group to display."))
                            .font(.caption)
                            .foregroundStyle(theme.adaptiveSecondaryText)
                    }
                    .padding(14)
                    .glassCard()
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 80)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: backgroundMode) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Wallpaper Status

    @ViewBuilder
    private var wallpaperStatus: some View {
        if wallpaperThumbnail != nil {
            Label(String(localized: "Synced with wallpaper shortcut"), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label(String(localized: "Set up the wallpaper shortcut first"), systemImage: "arrow.right.circle")
                    .font(.caption)
                    .foregroundStyle(AppColors.brandAccent)
                Text(String(localized: "Updates automatically each time the wallpaper shortcut runs."))
                    .font(.caption2)
                    .foregroundStyle(theme.adaptiveSecondaryText)
            }
        }
    }

    // MARK: - Background Card

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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 8) {
                preview()
                    .frame(height: 72)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isSelected ? AppColors.brandAccent : Color.clear,
                                lineWidth: 2
                            )
                    )

                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
