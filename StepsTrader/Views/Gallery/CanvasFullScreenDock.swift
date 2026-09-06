import SwiftUI

/// The dock shown while the canvas is raised for viewing.
///
/// Full screen is a viewing state, so its two navigation actions carry visible
/// labels rather than icons a user has to decode — "Edit" must never be
/// something you press by accident on the way out. Share is passed in from the
/// host because its context menu needs routines the dock knows nothing about.
struct CanvasFullScreenDock<Share: View>: View {
    let soundAppearance: CanvasSoundButtonAppearance
    let onSound: () -> Void
    let onEdit: () -> Void
    var showsEdit = true
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
        let sound = CanvasFullScreenSoundControlPresentation(appearance: soundAppearance)
        return HStack(spacing: 8) {
            label(
                sound.title,
                systemImage: sound.systemImage,
                action: onSound
            )
            .disabled(!sound.isEnabled)
            .accessibilityHint(String(localized: "Stops the day's music and closes full screen"))
            .accessibilityValue(soundAppearance.accessibilityValue)
            .accessibilityIdentifier("canvas_sound_off_button")

            share()

            if showsEdit {
                label(
                    String(localized: "Edit", comment: "Full screen dock – enter editing"),
                    systemImage: "hand.draw",
                    action: onEdit
                )
                .accessibilityIdentifier("canvas_edit_button")
            }
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

struct CanvasFullScreenSoundControlPresentation: Equatable {
    let title: String
    let systemImage: String
    let isEnabled: Bool

    init(appearance: CanvasSoundButtonAppearance) {
        switch appearance {
        case .readyToPlay:
            self.init(title: "Start sound", systemImage: "speaker.wave.2", isEnabled: true)
        case .starting:
            self.init(title: "Starting sound", systemImage: "hourglass", isEnabled: false)
        case .playing:
            self.init(title: "Sound off", systemImage: "speaker.slash.fill", isEnabled: true)
        case .retry:
            self.init(title: "Retry sound", systemImage: "arrow.clockwise", isEnabled: true)
        }
    }

    init(title: String, systemImage: String, isEnabled: Bool) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
    }
}

enum CanvasFullScreenSoundAction: Equatable {
    case retryInPlace
    case turnOffAndExit
    case none

    static func resolve(appearance: CanvasSoundButtonAppearance) -> Self {
        switch appearance {
        case .readyToPlay, .retry: .retryInPlace
        case .playing: .turnOffAndExit
        case .starting: .none
        }
    }
}
