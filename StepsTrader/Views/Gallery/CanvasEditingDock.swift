import SwiftUI

/// Editing chrome: Done in the top-left, Remix at the bottom, and a one-time
/// line telling the user the only gesture there is.
///
/// There is no Select / Draw / Text / Elements toolbar. The canvas is not a
/// drawing surface — it is an arrangement of things that happened, and the only
/// thing worth arranging is where they sit.
struct CanvasEditingDock: View {
    let showsDragHint: Bool
    let onDone: () -> Void
    let onRemix: () -> Void

    private var ink: Color { AppColors.Night.textPrimary }

    var body: some View {
        ZStack {
            VStack {
                HStack {
                    doneControl
                    Spacer(minLength: 0)
                }
                if showsDragHint {
                    dragHint
                        .padding(.top, 12)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }

            VStack {
                Spacer(minLength: 0)
                remixControl
            }
        }
    }

    private var doneControl: some View {
        Button(action: onDone) {
            Text(String(localized: "Done", comment: "Canvas editing – finish editing"))
                .font(.geist(size: 15, weight: .semibold))
                .foregroundStyle(ink)
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                .liquidGlassControl(in: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Done editing", comment: "Canvas editing – Done VoiceOver label"))
        .accessibilityIdentifier("canvas_done_button")
    }

    private var remixControl: some View {
        Button(action: onRemix) {
            Text(String(localized: "Remix", comment: "Canvas editing – restyle every element"))
                .font(.geist(size: 16, weight: .semibold))
                .foregroundStyle(AppAccentInk.primary)
                .padding(.horizontal, 28)
                .frame(minHeight: 56)
                .background(AppColors.brandAccent, in: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("canvas_remix_button")
    }

    private var dragHint: some View {
        Text(String(localized: "Drag elements to move", comment: "Canvas editing – one-time coach text"))
            .font(.geist(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .liquidGlassControl(in: Capsule(style: .continuous))
            .contrastingOnGlass()
            .allowsHitTesting(false)
    }
}
