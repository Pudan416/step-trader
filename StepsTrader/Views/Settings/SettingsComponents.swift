import SwiftUI

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedContent
            } else {
                ViewThatFits(in: .horizontal) {
                    horizontalContent
                    stackedContent
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private var horizontalContent: some View {
        HStack {
            labelText
                .fixedSize(horizontal: true, vertical: false)
            Spacer()
            valueText
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var stackedContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            labelText
            valueText
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var labelText: some View {
        Text(label)
            .font(.geist(.subheadline))
            .foregroundStyle(theme.adaptivePrimaryText)
    }

    private var valueText: some View {
        Text(value)
            .font(.geist(.subheadline))
            .foregroundStyle(theme.adaptiveSecondaryText)
    }
}

// MARK: - Section label (uppercase tracked, printed-page feel)

struct SettingsSectionLabel: View {
    let text: String
    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(SettingsLocalizedCasing.uppercase(text))
            .font(.geist(.caption2).weight(.semibold))
            .tracking(3)
            .foregroundStyle(theme.adaptiveMutedText)
    }
}

/// A section heading with deliberate breathing room before its matte card.
/// Keeping the heading outside the clipped surface prevents the card outline
/// from running through the text at both default and accessibility sizes.
struct SettingsLabeledGroup<Content: View>: View {
    let title: String
    let surfaceIdentifier: String?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        surfaceIdentifier: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.surfaceIdentifier = surfaceIdentifier
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel(text: title)
                .padding(.horizontal, 14)

            SettingsGroupedSurface(content: content)
                .modifier(OptionalSettingsSurfaceIdentifier(identifier: surfaceIdentifier))
        }
    }
}

private struct OptionalSettingsSurfaceIdentifier: ViewModifier {
    let identifier: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier {
            content
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(identifier)
        } else {
            content
        }
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
                    .font(.geist(size: 15))
                    .foregroundStyle(theme.adaptiveSecondaryText)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.geist(.subheadline))
                        .foregroundStyle(theme.adaptivePrimaryText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.geist(.caption))
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
                .font(.geist(size: 15))
                .foregroundStyle(theme.adaptiveSecondaryText)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(title)
                .font(.geist(.subheadline))
                .foregroundStyle(theme.adaptivePrimaryText)
            Spacer()
            if let value {
                Text(value)
                    .font(.geist(.subheadline))
                    .foregroundStyle(theme.adaptiveSecondaryText)
            }
            Image(systemName: "chevron.right")
                .font(.geist(size: 12, weight: .semibold))
                .foregroundStyle(theme.adaptiveMutedText.opacity(0.7))
                .accessibilityHidden(true)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedContent
            } else {
                ViewThatFits(in: .horizontal) {
                    horizontalContent
                    stackedContent
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private var horizontalContent: some View {
        HStack(spacing: 12) {
            leadingContent
            Spacer()
            trailingContent
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var stackedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            leadingContent
            trailingContent
                .padding(.leading, 36)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var leadingContent: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.geist(size: 15))
                .foregroundStyle(theme.adaptiveSecondaryText)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(title)
                .font(.geist(.subheadline))
                .foregroundStyle(theme.adaptivePrimaryText)
        }
    }

    private var trailingContent: some View {
        HStack(spacing: 8) {
            if let detail {
                Text(detail)
                    .font(.geist(.caption))
                    .foregroundStyle(theme.adaptiveSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Image(systemName: trailingIcon)
                .font(.geist(size: 10, weight: .semibold))
                .foregroundStyle(theme.adaptiveMutedText.opacity(0.7))
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Footer hint text

struct SettingsFooter: View {
    let text: String
    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(text)
            .font(.geist(.caption))
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

/// A calmer form of the energy wash for pushed Settings destinations. The
/// root page keeps the full-strength gradient while details recede behind
/// their controls.
struct SettingsDetailBackground: View {
    @ObservedObject var model: AppModel
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)
            theme.backgroundColor.opacity(0.78)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .accessibilityIdentifier("settings.detail.background")
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

// MARK: - Card surface

struct SettingsCardSurface: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content
            .background(Color.black.opacity(SettingsCardAppearance.surfaceOpacity))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        theme.adaptivePrimaryText.opacity(SettingsCardAppearance.outlineOpacity),
                        lineWidth: 0.75
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    func settingsCardSurface() -> some View { modifier(SettingsCardSurface()) }

    func settingsSelectable(label: String, isSelected: Bool) -> some View {
        modifier(SettingsSelectableModifier(label: label, isSelected: isSelected))
    }
}

private struct SettingsSelectableModifier: ViewModifier {
    let label: String
    let isSelected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            selectableContent(content)
                .accessibilityAddTraits(.isSelected)
        } else {
            selectableContent(content)
        }
    }

    private func selectableContent(_ content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(isSelected
                ? String(localized: "Selected", comment: "Settings selectable choice state")
                : String(localized: "Not selected", comment: "Settings selectable choice state")))
    }
}

/// Shared matte container for rows that belong to one Settings group.
struct SettingsGroupedSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0, content: content)
            .settingsCardSurface()
    }
}

private struct SettingsDetailPageModifier: ViewModifier {
    let title: String
    @Environment(\.topCardHeight) private var topCardHeight

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: topCardHeight)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    func settingsDetailPage(title: String) -> some View {
        modifier(SettingsDetailPageModifier(title: title))
    }
}

// MARK: - Gradient preview config

struct GradientPreviewConfig: Identifiable {
    let id = UUID()
    let style: GradientStyle
}
