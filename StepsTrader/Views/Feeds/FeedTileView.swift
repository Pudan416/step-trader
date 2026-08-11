import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

/// One app in the Feeds dock: a frosted translucent disc with the app's icon.
///
/// Two independent channels, per the reference. The **ring** says which app the
/// surface is currently showing; the **fill's warmth** says whether that app's
/// window is open. They have to be independent, because a window keeps draining
/// in the background while a different app is selected — so an open-but-
/// unselected tile stays warm without a ring, and a selected-but-locked tile
/// gets a ring over a cool fill.
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

    /// 118pt in the reference's 590pt-wide mock, ÷1.5.
    static let diameter: CGFloat = 79

    private var isUnlocked: Bool { remainingMinutes > 0 }

    /// Warmth carries the window's state. Both fills are translucent so the
    /// canvas reads through them — the dock sits directly on the artwork, with
    /// no card between.
    private var fill: Color {
        isUnlocked
            ? AppColors.brandAccent.opacity(0.28)
            : Color.white.opacity(0.13)
    }

    private var kind: FeedRowKind {
        FeedRowModel.kind(
            templateApp: group.templateApp,
            appTokenCount: group.selection.applicationTokens.count
        )
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(fill)
                    .overlay(
                        // A hairline so the disc has an edge even where the
                        // canvas behind it happens to be pale.
                        Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                    )

                icon
            }
            .frame(width: Self.diameter, height: Self.diameter)
            // Selection is the ring, drawn outside the fill so it never tints
            // the icon or the disc.
            .overlay(
                Circle()
                    .strokeBorder(AppColors.brandAccent, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            )
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
                    .fill(Color.white.opacity(0.13))
                    .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
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
