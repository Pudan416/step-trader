import SwiftUI

/// The dock shown while the canvas is raised for viewing.
///
/// Full screen is a viewing state, so its two navigation actions carry visible
/// labels rather than icons a user has to decode — "Edit" must never be
/// something you press by accident on the way out. Share is passed in from the
/// host because its context menu needs routines the dock knows nothing about.
struct CanvasFullScreenDock<Share: View>: View {
    let onExit: () -> Void
    let onEdit: () -> Void
    @ViewBuilder let share: () -> Share

    private var ink: Color { AppColors.Night.textPrimary }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 0) { content }
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(spacing: 8) {
            label(
                String(localized: "Exit full screen", comment: "Full screen dock – collapse action"),
                systemImage: "arrow.down.right.and.arrow.up.left",
                action: onExit
            )
            .accessibilityIdentifier("canvas_exit_fullscreen_button")

            share()

            label(
                String(localized: "Edit", comment: "Full screen dock – enter editing"),
                systemImage: "hand.draw",
                action: onEdit
            )
            .accessibilityIdentifier("canvas_edit_button")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .liquidGlassControl(in: Capsule(style: .continuous))
    }

    private func label(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.geist(size: 15, weight: .regular))
                Text(title)
                    .font(.geist(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
