import SwiftUI

/// The two Canvas actions that flank the tab bar: listen to the day, add
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
    let isHappeningPalettePresented: Bool
    let soundAppearance: CanvasSoundButtonAppearance
    let onSound: () -> Void
    let onOpenHappeningList: () -> Void
    let onToggleHappeningPalette: () -> Void

    @Environment(\.canvasChromePalette) private var palette
    private var ink: Color { palette.textColor }

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
                if isHappeningPalettePresented {
                    listControl
                } else {
                    soundControl
                }
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

    // MARK: - Left: sound + full screen

    private var soundControl: some View {
        Button(action: onSound) {
            Image(systemName: soundAppearance.systemImage)
                .font(.geist(size: 20, weight: .regular))
                .foregroundStyle(palette.accentColor)
                .frame(width: 48, height: 48)
                .canvasChromeSurface(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(soundAppearance == .starting)
        .accessibilityLabel(soundAppearance.accessibilityLabel)
        .accessibilityHint(
            String(localized: "Starts the day's music and opens the canvas full screen",
                   comment: "Canvas – sound button VoiceOver hint")
        )
        .accessibilityValue(soundAppearance.accessibilityValue)
        .accessibilityIdentifier("canvas_sound_button")
    }

    private var listControl: some View {
        Button(action: onOpenHappeningList) {
            Image(systemName: "list.bullet")
                .font(.geist(size: 20, weight: .regular))
                .foregroundStyle(ink)
                .frame(width: 52, height: 52)
                .canvasChromeSurface(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Choose happenings"))
        .accessibilityIdentifier("canvas_happening_list_button")
    }

    // MARK: - Right: add

    private var addControl: some View {
        Button(action: onToggleHappeningPalette) {
            Image(systemName: "plus")
                .font(.geist(size: 22, weight: .regular))
                .foregroundStyle(palette.onAccentColor)
                .rotationEffect(.degrees(isHappeningPalettePresented ? 45 : 0))
                .frame(width: 52, height: 52)
                .background(palette.accentColor, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: isHappeningPalettePresented)
        .accessibilityLabel(
            String(
                localized: isHappeningPalettePresented ? "Close" : "Add happening",
                comment: "Canvas add or palette close button"
            )
        )
        .accessibilityIdentifier(
            isHappeningPalettePresented ? "canvas_palette_close_button" : "canvas_add_button"
        )
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

enum CanvasSoundButtonAppearance: Equatable {
    case readyToPlay
    case starting
    case playing
    case retry

    var systemImage: String {
        switch self {
        case .readyToPlay: "play.fill"
        case .starting: "hourglass"
        case .playing: "waveform"
        case .retry: "arrow.clockwise"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .readyToPlay: String(localized: "Play day music")
        case .starting: String(localized: "Starting day music")
        case .playing: String(localized: "Day music is playing")
        case .retry: String(localized: "Retry day music")
        }
    }

    var accessibilityValue: String {
        switch self {
        case .readyToPlay: "off"
        case .starting: "starting"
        case .playing: "on"
        case .retry: "error, retry available"
        }
    }
}
