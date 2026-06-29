import SwiftUI

// MARK: - Routing

extension Notification.Name {
    /// Posted when a feature-tip CTA is accepted. `userInfo["page"]` carries the
    /// target settings page (`FeatureTip.settingsPage`). `MainTabView` switches
    /// to the Settings tab; `SettingsSheet` pushes the matching sub-page.
    static let openFeatureTipSettings = Notification.Name("com.steps.trader.openSettings")
}

/// The settings sub-page a feature tip deep-links into. Raw value travels in the
/// notification `userInfo` so the (separate) tab and settings views stay in sync.
enum FeatureTipSettingsPage: String {
    case wallpaper
    case widget
}

// MARK: - Feature Tip Model

/// Lightweight, one-shot promotional nudges shown a few launches in, pointing
/// users at features that are easy to miss (wallpaper auto-export, home-screen
/// widgets).
///
/// Design mirrors the existing review-prompt gating in `StepsTraderApp`
/// (`requestAppReviewIfNeeded`): a launch-count threshold plus a per-tip
/// one-shot `@AppStorage` flag. At most one tip is shown per launch, and never
/// in the same session the App Store review prompt fires (see the scenePhase
/// `.active` handler).
///
/// Timeline (one "quiet" launch between each prompt):
///   - launch 3 → App Store review (existing)
///   - launch 5 → widgets tip
///   - launch 7 → wallpaper tip
enum FeatureTip: String, Identifiable, CaseIterable {
    case widgets
    case wallpaper

    var id: String { rawValue }

    /// Evaluated in priority order; the first eligible & unseen tip wins for a
    /// given launch. Widgets first so a user updating from an old build (with an
    /// already-high launch count) sees widgets one session, wallpaper the next.
    static var orderedByPriority: [FeatureTip] { [.widgets, .wallpaper] }

    /// Minimum cold-launch count before the tip becomes eligible.
    var minLaunch: Int {
        switch self {
        case .widgets:   return 5
        case .wallpaper: return 7
        }
    }

    /// One-shot `UserDefaults` flag key. Versioned so copy/behavior changes can
    /// re-show the tip later by bumping the suffix.
    private var seenKey: String { "featureTipSeen_\(rawValue)_v1" }

    var hasBeenSeen: Bool {
        UserDefaults.standard.bool(forKey: seenKey)
    }

    func markSeen() {
        UserDefaults.standard.set(true, forKey: seenKey)
    }

    /// Debug helper: clears every tip's one-shot flag (Settings → diagnostics).
    static func resetAllSeenFlags() {
        for tip in allCases {
            UserDefaults.standard.removeObject(forKey: tip.seenKey)
        }
    }

    /// Per-tip preconditions beyond the launch threshold. The wallpaper tip only
    /// makes sense once the user actually has a canvas to put on their wallpaper.
    private var preconditionMet: Bool {
        switch self {
        case .widgets:
            return true
        case .wallpaper:
            return !CanvasStorageService.shared.availableDayKeys().isEmpty
        }
    }

    func isEligible(launchCount: Int) -> Bool {
        launchCount >= minLaunch && !hasBeenSeen && preconditionMet
    }

    // MARK: Presentation content

    var iconSystemName: String {
        switch self {
        case .widgets:   return "square.stack.3d.up.fill"
        case .wallpaper: return "photo.on.rectangle.angled"
        }
    }

    var title: String {
        switch self {
        case .widgets:
            return String(localized: "Add a widget", comment: "Feature tip title — home screen widget")
        case .wallpaper:
            return String(localized: "Set your canvas as wallpaper", comment: "Feature tip title — wallpaper")
        }
    }

    var message: String {
        switch self {
        case .widgets:
            return String(localized: "Keep today's energy canvas on your Home Screen. Long-press an empty area, tap +, search \"Nowhere\", and pick a widget size.", comment: "Feature tip body — widget setup steps")
        case .wallpaper:
            return String(localized: "Your daily canvas can live on your Lock Screen — refreshed automatically every time you close the app. Set it up once in a few taps.", comment: "Feature tip body — wallpaper setup")
        }
    }

    /// Settings sub-page this tip's primary CTA navigates to.
    var settingsPage: FeatureTipSettingsPage {
        switch self {
        case .widgets:   return .widget
        case .wallpaper: return .wallpaper
        }
    }

    /// Title for the primary call-to-action button.
    var primaryActionTitle: String {
        switch self {
        case .widgets:
            return String(localized: "Open widget settings", comment: "Feature tip primary button — widgets")
        case .wallpaper:
            return String(localized: "Set it up", comment: "Feature tip primary button — wallpaper")
        }
    }
}

// MARK: - Feature Tip Sheet

/// Bottom-sheet card presenting a `FeatureTip` with a real canvas preview and a
/// primary CTA that deep-links into the relevant Settings page.
struct FeatureTipSheet: View {
    let tip: FeatureTip

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    /// Real preview of today's canvas, falling back to any most-recent canvas,
    /// so the card shows the user their own art rather than a generic mock.
    private var previewImage: UIImage? {
        let todayKey = AppModel.dayKey(for: .now)
        if let img = CanvasStorageService.shared.loadSnapshotImage(for: todayKey) {
            return img
        }
        if let recent = CanvasStorageService.shared.availableDayKeys().first {
            return CanvasStorageService.shared.loadSnapshotImage(for: recent)
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            preview
                .padding(.top, 28)
                .padding(.bottom, 24)

            VStack(spacing: 10) {
                Text(tip.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.adaptivePrimaryText)
                    .multilineTextAlignment(.center)

                Text(tip.message)
                    .font(.subheadline)
                    .foregroundStyle(theme.adaptiveSecondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Button {
                    dismiss()
                    // Deep-link into the relevant Settings sub-page. MainTabView
                    // switches to the Settings tab; SettingsSheet pushes the page.
                    NotificationCenter.default.post(
                        name: .openFeatureTipSettings,
                        object: nil,
                        userInfo: ["page": tip.settingsPage.rawValue]
                    )
                } label: {
                    Text(tip.primaryActionTitle)
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(AppColors.brandAccent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button {
                    dismiss()
                } label: {
                    Text(String(localized: "Maybe later", comment: "Feature tip dismiss button"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.adaptiveSecondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundColor)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.backgroundColor)
    }

    // MARK: Preview visuals

    @ViewBuilder
    private var preview: some View {
        switch tip {
        case .widgets:
            widgetMock
        case .wallpaper:
            wallpaperMock
        }
    }

    /// A rounded "widget tile" containing the canvas snapshot (mirrors how the
    /// real widget renders the canvas).
    private var widgetMock: some View {
        canvasFill
            .frame(width: 150, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    /// A phone-frame mock with the canvas as the Lock Screen wallpaper.
    private var wallpaperMock: some View {
        canvasFill
            .frame(width: 116, height: 232)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 3)
            }
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
    }

    @ViewBuilder
    private var canvasFill: some View {
        if let image = previewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            // Fallback gradient so the card never looks broken pre-first-canvas.
            LinearGradient(
                colors: [AppColors.brandAccent.opacity(0.5), .purple.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: tip.iconSystemName)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}
