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
                    .font(.geist(size: 28, weight: .light))
                    .foregroundStyle(AppColors.Night.textPrimary)
            }
            .frame(width: FeedTileView.diameter, height: FeedTileView.diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Add a feed", comment: "Feeds dock – add button VoiceOver label"))
    }
}

/// An empty slot in the dock, shown only before the first feed exists.
///
/// It teaches the shape of the page rather than describing it: the row of
/// circles is where your apps will live, and the one carrying a `+` is where
/// you start. Inert and hidden from VoiceOver — there is nothing here to act
/// on, and announcing three empty slots would be noise.
struct FeedPlaceholderTileView: View {
    var body: some View {
        Circle()
            .strokeBorder(.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
            .frame(width: FeedTileView.diameter, height: FeedTileView.diameter)
            .accessibilityHidden(true)
    }
}

// MARK: - Row timer design

/// An asymmetric ticket with a concave trailing edge for the management menu.
/// The shape is deliberately more expressive than a rounded rectangle, while
/// remaining stable when a progress fill is clipped through it.
struct FeedTicketShape: Shape {
    func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }

        let leadingRadius = min(28, rect.height / 2)
        let trailingRadius = min(18, rect.height / 2)
        let notchHalfHeight = min(26, rect.height * 0.32)
        let notchDepth = min(42, rect.width * 0.18)
        let notchTop = rect.midY - notchHalfHeight
        let notchBottom = rect.midY + notchHalfHeight

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + leadingRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - trailingRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + trailingRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: notchTop))
        path.addCurve(
            to: CGPoint(x: rect.maxX - notchDepth, y: rect.midY),
            control1: CGPoint(x: rect.maxX, y: notchTop + notchHalfHeight * 0.55),
            control2: CGPoint(x: rect.maxX - notchDepth, y: rect.midY - notchHalfHeight * 0.55)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: notchBottom),
            control1: CGPoint(x: rect.maxX - notchDepth, y: rect.midY + notchHalfHeight * 0.55),
            control2: CGPoint(x: rect.maxX, y: notchBottom - notchHalfHeight * 0.55)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - trailingRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - trailingRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + leadingRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - leadingRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + leadingRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + leadingRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// One feed ticket carries both the action and the timer. A locked ticket opens
/// the duration picker; an active one opens its app. No social-network artwork
/// is repeated here — the app name is the identifier, and the yellow body is
/// reserved for the one thing unique to this screen: remaining access.
struct FeedRowView: View {
    let group: TicketGroup
    let accessState: FeedRowAccessState
    let canOpen: Bool
    let onTap: () -> Void
    let onSettings: () -> Void
    let onDelete: () -> Void

    private let rowHeight: CGFloat = 82

    private var fillFraction: Double {
        if case .active(_, let fraction) = accessState { return fraction }
        return 0
    }

    private var remainingMinutes: Int? {
        if case .active(let minutes, _) = accessState { return minutes }
        return nil
    }

    private var displayName: String {
        group.templateApp.map { TargetResolver.displayName(for: $0) }
            ?? (group.name.isEmpty ? String(localized: "Feed") : group.name)
    }

    var body: some View {
        rowGeometry
            .frame(height: rowHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
            .accessibilityAction(.default, onTap)
            .accessibilityAction(named: String(localized: "Settings"), onSettings)
            .accessibilityAction(named: String(localized: "Delete"), onDelete)
    }

    private var rowGeometry: some View {
        GeometryReader { geometry in
            rowSurface(fillWidth: geometry.size.width * CGFloat(fillFraction))
        }
    }

    private func rowSurface(fillWidth: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            ticketBody(fillWidth: fillWidth)
            optionsMenu
                .offset(x: 1)
        }
        // Usage is metered in whole-minute observations. Let the row step
        // with that source of truth instead of inventing a smooth timer.
        .animation(nil, value: fillFraction)
    }

    private func ticketBody(fillWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.27)

            Rectangle()
                .fill(AppColors.brandAccent.opacity(0.86))
                .frame(width: fillWidth)
                .frame(maxHeight: .infinity)

            // A permanent scrim keeps one text colour readable at every fill
            // fraction. No word changes colour when the timer crosses it.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.24), location: 0),
                    .init(color: .black.opacity(0.12), location: 0.62),
                    .init(color: .black.opacity(0.28), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .allowsHitTesting(false)

            Button(action: onTap) {
                rowContent
                    .contentShape(FeedTicketShape())
            }
            .buttonStyle(.plain)
        }
        .clipShape(FeedTicketShape())
        .overlay {
            FeedTicketShape()
                .stroke(Color.white.opacity(0.16), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(displayName)
                    .font(.geist(size: 19, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: remainingMinutes == nil ? "lock.fill" : "clock.fill")
                        .font(.geist(size: 12, weight: .semibold))
                    Text(statusText)
                        .font(.geist(size: 14, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .opacity(0.82)
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.leading, 22)
        .padding(.trailing, 68)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var statusText: String {
        guard let remainingMinutes else {
            return String(localized: "Choose time")
        }
        return String(localized: "\(remainingMinutes) min left", comment: "Active feed row status")
    }

    private var optionsMenu: some View {
        Menu {
            Button(action: onSettings) {
                Label(String(localized: "Settings"), systemImage: "gearshape")
            }
            Button(role: .destructive, action: onDelete) {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.geist(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
                .contentShape(Circle())
        }
        .accessibilityLabel(String(localized: "Feed options"))
    }

    private var accessibilityLabel: String {
        guard let remainingMinutes else {
            return String(localized: "\(displayName), locked", comment: "Locked feed row")
        }
        return String(localized: "\(displayName), \(remainingMinutes) minutes left", comment: "Active feed row")
    }

    private var accessibilityHint: String {
        if remainingMinutes == nil {
            return String(localized: "Double tap to choose unlock time")
        }
        return canOpen
            ? String(localized: "Double tap to open the app")
            : String(localized: "Double tap to open feed settings")
    }
}

/// Compact purchase sheet used only for a locked row. It disappears after a
/// successful purchase; the row then becomes the persistent timer and action.
struct FeedDurationSheet: View {
    @ObservedObject var model: AppModel
    let group: TicketGroup
    let onPurchased: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var isPurchasing = false

    private var displayName: String {
        group.templateApp.map { TargetResolver.displayName(for: $0) }
            ?? (group.name.isEmpty ? String(localized: "Feed") : group.name)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayName)
                        .font(.geist(size: 28, weight: .bold, design: .rounded))
                    Text(String(localized: "Choose how long to unlock"))
                        .font(.geist(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    ForEach(AccessWindow.allCases.filter(group.enabledIntervals.contains), id: \.self) { window in
                        durationButton(window)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .background(theme.backgroundColor.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isPurchasing)
    }

    private func durationButton(_ window: AccessWindow) -> some View {
        let cost = group.cost(for: window)
        let canAfford = model.totalStepsBalance >= cost

        return Button {
            purchase(window: window, cost: cost)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(window.displayName)
                        .font(.geist(size: 18, weight: .semibold, design: .rounded))
                    if !canAfford {
                        Text(String(localized: "Not enough colors"))
                            .font(.geist(size: 12, weight: .medium, design: .rounded))
                            .opacity(0.65)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                    Text("\(cost)")
                        .monospacedDigit()
                }
                .font(.geist(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundStyle(canAfford ? Color.black.opacity(0.82) : Color.primary)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(canAfford ? AppColors.brandAccent : Color.primary.opacity(0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(canAfford ? 0.05 : 0.1), lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
        .disabled(!canAfford || isPurchasing)
        .opacity((!canAfford || isPurchasing) ? 0.55 : 1)
    }

    private func purchase(window: AccessWindow, cost: Int) {
        guard !isPurchasing else { return }
        isPurchasing = true
        Task { @MainActor in
            await model.handlePayGatePaymentForGroup(
                groupId: group.id,
                window: window,
                costOverride: cost
            )
            isPurchasing = false

            guard model.unspentUsageBudgetMatchingShield(for: group.id) > 0 else { return }
            onPurchased()
            dismiss()
        }
    }
}
