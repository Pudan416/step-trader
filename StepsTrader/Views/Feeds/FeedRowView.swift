import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

/// One row per `TicketGroup`. A single-app group draws a plain icon; a multi-app
/// group draws overlapping icons and the group's name. The lock badge is drawn
/// once, outside the kind switch, so it is provably identical for both.
struct FeedRowView: View {
    @ObservedObject var model: AppModel
    let group: TicketGroup
    let onTap: () -> Void

    @State private var remaining: Int = 0

    private var isUnlocked: Bool { remaining > 0 }

    private var kind: FeedRowKind {
        FeedRowModel.kind(
            templateApp: group.templateApp,
            appTokenCount: group.selection.applicationTokens.count
        )
    }

    private var title: String {
        if let templateApp = group.templateApp {
            return TargetResolver.displayName(for: templateApp)
        }
        return group.name
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                icons
                Text(title)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.Night.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                trailing
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .onAppear(perform: refresh)
        .task {
            // The honest signal arrives once a minute from the monitor extension.
            // Poll a little faster than that so the row is never more than a few
            // seconds stale, but never interpolate between ticks.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                refresh()
            }
        }
    }

    @ViewBuilder
    private var icons: some View {
        switch kind {
        case .single(let source):
            icon(source: source, size: 44, index: 0)
        case .cluster(let sources, _):
            HStack(spacing: -14) {
                ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                    icon(source: source, size: 40, index: index)
                        .overlay {
                            RoundedRectangle(cornerRadius: 40 * 0.24, style: .continuous)
                                .strokeBorder(AppColors.Night.background, lineWidth: 2)
                        }
                        .zIndex(Double(sources.count - index))
                }
            }
        }
    }

    /// `FeedIconView`'s `token` parameter only exists where FamilyControls does,
    /// so the call itself has to be conditional — not just the value passed in.
    @ViewBuilder
    private func icon(source: FeedIconSource, size: CGFloat, index: Int) -> some View {
        #if canImport(FamilyControls)
        FeedIconView(source: source, size: size, token: token(at: index))
        #else
        FeedIconView(source: source, size: size)
        #endif
    }

    @ViewBuilder
    private var trailing: some View {
        if isUnlocked {
            Text(String(localized: "\(remaining)m", comment: "Feeds row – remaining usage minutes"))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.brandAccent)
        }
        // Identical for both row kinds, by construction.
        Image(systemName: isUnlocked ? "lock.open" : "lock.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isUnlocked ? AppColors.brandAccent : Color.white.opacity(0.35))
            .accessibilityLabel(isUnlocked
                ? String(localized: "Unlocked", comment: "Feeds row – lock badge state")
                : String(localized: "Locked", comment: "Feeds row – lock badge state"))
    }

    #if canImport(FamilyControls)
    private func token(at index: Int) -> ApplicationToken? {
        let tokens = Array(group.selection.applicationTokens)
        guard index < tokens.count else { return nil }
        return tokens[index]
    }
    #endif

    private func refresh() {
        remaining = model.remainingUsageBudget(for: group.id)
    }
}
