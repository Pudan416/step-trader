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
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

// MARK: - Hairline divider

/// Thin 0.5pt divider between rows on the matte settings surface.
struct DetailDivider: View {
    @Environment(\.appTheme) private var theme
    var inset: CGFloat = 14

    var body: some View {
        Rectangle()
            .fill(theme.adaptiveDividerColor.opacity(0.5))
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

// MARK: - Read-only info row (label + value)

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
        .padding(.vertical, 13)
    }
}

// MARK: - Section label (uppercase tracked, printed-page feel)

struct SettingsSectionLabel: View {
    let text: String
    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(3)
            .foregroundStyle(theme.adaptiveMutedText)
    }
}

// MARK: - Toggle row

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    var subtitle: String? = nil
    @Environment(\.appTheme) private var theme

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(theme.adaptiveSecondaryText)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(theme.adaptivePrimaryText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(theme.adaptiveSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .tint(AppColors.brandAccent)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Navigation row

struct SettingsNavRow: View {
    let icon: String
    let title: String
    var value: String? = nil
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(theme.adaptiveSecondaryText)
                .frame(width: 24)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(theme.adaptivePrimaryText)
            Spacer()
            if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(theme.adaptiveSecondaryText)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.adaptiveMutedText.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

// MARK: - Link row (tappable external link)

struct SettingsLinkRow: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var trailingIcon: String = "arrow.up.right"
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(theme.adaptiveSecondaryText)
                .frame(width: 24)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(theme.adaptivePrimaryText)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(theme.adaptiveSecondaryText)
            }
            Image(systemName: trailingIcon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.adaptiveMutedText.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

// MARK: - Footer hint text

struct SettingsFooter: View {
    let text: String
    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(theme.adaptiveSecondaryText)
            .padding(.horizontal, 4)
    }
}

// MARK: - Settings background

/// Standard energy gradient — same surface used by every other tab, so the
/// settings page reads as continuous with the rest of the app. The "tactile"
/// feel comes from removing all glass cards plus the `SettingsGrainOverlay`
/// rendered above the rows, *not* from a darker backdrop.
struct SettingsGradientBG: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Color.clear.energyGradientBackground(model: model, showGrain: false)
    }
}

/// Grain layer rendered ABOVE settings content. Place as the last sibling of
/// the ZStack so it sits on top of the ScrollView. Pairs with
/// `SettingsGradientBG` which already includes a grain layer in the
/// gradient backdrop — this second layer is what makes the rows read as ink
/// stamped under paper texture.
struct SettingsGrainOverlay: View {
    var body: some View {
        Image("grain (small)")
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea()
            .opacity(0.14)
            .blendMode(.softLight)
            .allowsHitTesting(false)
    }
}

// MARK: - Press style

/// Matte press feedback — dips opacity instead of laying a glossy fill.
/// Glass surfaces highlight by tinting their lens; the matte page never
/// gains a press background.
struct MattePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Gradient preview config

struct GradientPreviewConfig: Identifiable {
    let id = UUID()
    let style: GradientStyle
}
