import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

/// One app in the Feeds dock. Hue says whether a window is open; brightness says
/// whether this is the app the surface is currently showing. The two are
/// independent — a window keeps draining while another app is selected.
struct FeedTileView: View {
    let group: TicketGroup
    let isSelected: Bool
    /// Unspent minutes on this group's window, polled once for the whole page
    /// by `AppsPageSimplified`. The tile does not read the budget itself: when
    /// it had its own 15s loop it and the surface drifted apart, so a freshly
    /// bought window showed a running timer above a tile that still looked
    /// locked.
    let remainingMinutes: Int
    let onTap: () -> Void

    static let diameter: CGFloat = 83

    private var isUnlocked: Bool { remainingMinutes > 0 }

    private var glowColor: Color {
        isUnlocked ? AppColors.brandAccent : Color.white.opacity(0.55)
    }

    /// Selection is brightness. Unselected tiles stay legible rather than vanishing.
    private var glowOpacity: Double { isSelected ? 1.0 : 0.45 }

    private var kind: FeedRowKind {
        FeedRowModel.kind(
            templateApp: group.templateApp,
            appTokenCount: group.selection.applicationTokens.count
        )
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // The glow is a soft radial wash behind the icon, not a ring on it.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [glowColor.opacity(0.85), glowColor.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: Self.diameter * 0.62
                        )
                    )
                    .frame(width: Self.diameter, height: Self.diameter)
                    .opacity(glowOpacity)

                icon
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.22), value: isSelected)
            .animation(.easeOut(duration: 0.22), value: isUnlocked)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var icon: some View {
        switch kind {
        case .single(let source):
            tileIcon(source: source, size: 42, index: 0)
        case .cluster(let sources, _):
            HStack(spacing: -10) {
                ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                    tileIcon(source: source, size: 30, index: index)
                        .zIndex(Double(sources.count - index))
                }
            }
        }
    }

    /// `FeedIconView`'s `token:` parameter only exists where FamilyControls does, so
    /// the call itself must be conditional, not just the value passed in.
    @ViewBuilder
    private func tileIcon(source: FeedIconSource, size: CGFloat, index: Int) -> some View {
        #if canImport(FamilyControls)
        FeedIconView(source: source, size: size, token: token(at: index))
        #else
        FeedIconView(source: source, size: size)
        #endif
    }

    #if canImport(FamilyControls)
    private func token(at index: Int) -> ApplicationToken? {
        let tokens = Array(group.selection.applicationTokens)
        guard index < tokens.count else { return nil }
        return tokens[index]
    }
    #endif

    private var accessibilityLabel: String {
        let name = group.templateApp.map { TargetResolver.displayName(for: $0) } ?? group.name
        return isUnlocked
            ? String(localized: "\(name), unlocked, \(remainingMinutes) minutes left", comment: "Feeds tile – VoiceOver, window open")
            : String(localized: "\(name), locked", comment: "Feeds tile – VoiceOver, window closed")
    }
}

/// The trailing `+` tile. Same footprint as an app tile so the dock stays even.
struct FeedAddTileView: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: FeedTileView.diameter * 0.62
                        )
                    )
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(AppColors.Night.textPrimary)
            }
            .frame(width: FeedTileView.diameter, height: FeedTileView.diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Add a feed", comment: "Feeds dock – add button VoiceOver label"))
    }
}
