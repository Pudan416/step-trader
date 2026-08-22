import SwiftUI

/// The three Canvas actions, in a fixed order: raise the canvas, show the data
/// behind it, add something that happened.
///
/// The order is spatial, not linguistic — these are utility controls anchored
/// to corners of the screen — so it is pinned left-to-right even in RTL. Only
/// the text inside "Show data" localises.
struct CanvasBottomActionRow: View {
    let isDataExpanded: Bool
    let onFullScreen: () -> Void
    let onToggleData: () -> Void
    let onAdd: () -> Void

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var ink: Color { AppColors.Night.textPrimary }

    /// Increase Contrast lifts the outlined circle off a busy canvas.
    private var outlineOpacity: Double {
        colorSchemeContrast == .increased ? 0.65 : 0.35
    }

    var body: some View {
        Group {
            // Without the container, iOS 26 merges sibling interactive glass
            // surfaces and routes every tap to the first one in the hierarchy.
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 0) { content }
            } else {
                content
            }
        }
        .padding(.horizontal, 24)
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 0) {
            fullScreenControl
            Spacer(minLength: 8)
            showDataControl
            Spacer(minLength: 8)
            addControl
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    // MARK: - Left: full screen

    private var fullScreenControl: some View {
        Button(action: onFullScreen) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(ink)
                .frame(width: 56, height: 56)
                // Outline, not glass: the canvas is the subject here, and a
                // filled pill in the corner competes with it.
                .overlay(Circle().strokeBorder(ink.opacity(outlineOpacity), lineWidth: 1))
                .frame(width: 72, height: 72)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(localized: "Expand canvas", comment: "Canvas – full screen button VoiceOver label")
        )
        .accessibilityHint(
            String(localized: "Opens the canvas without editing",
                   comment: "Canvas – full screen button VoiceOver hint")
        )
        .accessibilityIdentifier("canvas_fullscreen_button")
    }

    // MARK: - Center: show / hide data

    private var showDataControl: some View {
        Button(action: onToggleData) {
            HStack(spacing: 4) {
                Text(
                    isDataExpanded
                        ? String(localized: "Hide data", comment: "Canvas – collapse the data panel")
                        : String(localized: "Show data", comment: "Canvas – expand the data panel")
                )
                .lineLimit(1)
                .minimumScaleFactor(0.85)

                Image(systemName: isDataExpanded ? "chevron.down" : "chevron.up")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 16)
            .frame(minWidth: 128, minHeight: 56)
            .liquidGlassControl(in: Capsule(style: .continuous), style: .lens)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(localized: "Show canvas data", comment: "Canvas – data panel VoiceOver label")
        )
        .accessibilityValue(
            isDataExpanded
                ? String(localized: "Expanded", comment: "Canvas – data panel VoiceOver value")
                : String(localized: "Collapsed", comment: "Canvas – data panel VoiceOver value")
        )
        .accessibilityIdentifier("canvas_show_data_button")
        .coachMarkAnchor(.expandChevron)
    }

    // MARK: - Right: add

    private var addControl: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(AppAccentInk.primary)
                .frame(width: 56, height: 56)
                .background(AppColors.brandAccent, in: Circle())
                .frame(width: 72, height: 72)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Add happening", comment: "Canvas add button"))
        .accessibilityIdentifier("canvas_add_button")
        .coachMarkAnchor(.tapPlusButton)
        // The palette docks on this button's line rather than re-deriving it
        // from tab-bar height and paddings.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CanvasAddButtonCenterKey.self,
                    value: proxy.frame(in: .global).midY
                )
            }
        )
    }
}
