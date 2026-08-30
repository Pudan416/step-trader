import SwiftUI

/// The two Canvas actions that flank the data drawer: raise the canvas, add
/// something that happened.
///
/// "Show data" no longer lives here — it moved up to a strip under the
/// energy pill (`CanvasDataPanel`'s own handle), which is the drawer's
/// control as well as its top edge. This row keeps its left/right anchors
/// so the corner controls stay where a finger already expects them, with
/// the centre now empty.
///
/// The order is spatial, not linguistic — these are utility controls anchored
/// to corners of the screen — so it is pinned left-to-right even in RTL.
struct CanvasBottomActionRow: View {
    /// True while the data drawer is open. The circle and the `+` are then
    /// removed from the tree entirely, not merely covered — a panel the user
    /// can't see through must not leave a live hit region under it.
    let isDataPanelOpen: Bool
    let onFullScreen: () -> Void
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
        // GalleryView already supplies the 16pt screen guard rail. Four more
        // points land the circular controls at the Figma frame's 20pt edge.
        .padding(.horizontal, 4)
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 0) {
            if !isDataPanelOpen {
                fullScreenControl
            }
            Spacer(minLength: 8)
            if !isDataPanelOpen {
                addControl
            }
        }
        // Keep the row's layout slot when its controls are hidden. The
        // suggestion banner shares this VStack, so collapsing the row used to
        // pull Resting down underneath the floating tab bar.
        .frame(height: 52)
        .environment(\.layoutDirection, .leftToRight)
    }

    // MARK: - Left: full screen

    private var fullScreenControl: some View {
        Button(action: onFullScreen) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.geist(size: 20, weight: .regular))
                .foregroundStyle(ink)
                .frame(width: 48, height: 48)
                // Outline, not glass: the canvas is the subject here, and a
                // filled pill in the corner competes with it.
                .overlay(Circle().strokeBorder(ink.opacity(outlineOpacity), lineWidth: 1))
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

    // MARK: - Right: add

    private var addControl: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.geist(size: 22, weight: .regular))
                .foregroundStyle(AppAccentInk.primary)
                .frame(width: 52, height: 52)
                .background(AppColors.brandAccent, in: Circle())
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
