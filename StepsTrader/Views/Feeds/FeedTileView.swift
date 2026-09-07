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

/// Dark pigment under the labels, the unmodified bright color at the free edge.
/// Multiplying RGB keeps its hue/saturation, unlike mixing in gray or white glass.
enum FeedPigment {
    struct Stop {
        let color: DayObjectRGB
        let location: Double
    }

    static let textEdge = 0.64

    static func stops(for palette: TodayCanvasUnlockPalette, textEdge: Double = FeedPigment.textEdge) -> [Stop] {
        let colors = palette.colors.sorted { $0.perceptualOKLab.x < $1.perceptualOKLab.x }
        guard let bright = colors.last else {
            return [Stop(color: DayObjectRGB(hex: "#332F3B"), location: 0)]
        }
        let readingColors = colors.count > 2 ? Array(colors.dropLast()) : colors
        var result = readingColors.enumerated().map { index, color in
            Stop(color: readable(color), location: Double(index) / Double(max(1, readingColors.count - 1)) * textEdge)
        }
        if readingColors.count == 1 {
            result.append(Stop(color: readable(bright), location: textEdge))
        }
        result.append(Stop(color: bright, location: 1))
        return result
    }

    static func menuUsesDarkInk(palette: TodayCanvasUnlockPalette, fraction: Double, position: Double,
                               textEdge: Double = FeedPigment.textEdge) -> Bool {
        guard position < fraction else { return false }
        let stops = stops(for: palette, textEdge: textEdge)
        var color = stops[0].color
        for (left, right) in zip(stops, stops.dropFirst()) where position >= left.location {
            let progress = Float(min(max((position - left.location) / (right.location - left.location), 0), 1))
            color = DayObjectRGB(sRGB: left.color.sRGB + (right.color.sRGB - left.color.sRGB) * progress)
        }
        return relativeLuminance(color.linearRGB) > 0.18
    }

    private static func readable(_ color: DayObjectRGB) -> DayObjectRGB {
        let white = SIMD3<Float>(repeating: 1)
        guard contrastRatio(color.linearRGB, white) < 5.5 else { return color }
        var lower: Float = 0
        var upper: Float = 1
        for _ in 0..<16 {
            let middle = (lower + upper) / 2
            if contrastRatio(color.darkened(by: middle).linearRGB, white) >= 5.5 {
                lower = middle
            } else {
                upper = middle
            }
        }
        return color.darkened(by: lower)
    }
}

struct FeedProgressFill: View {
    let palette: TodayCanvasUnlockPalette
    let fraction: Double
    var textEdge = FeedPigment.textEdge

    var body: some View {
        GeometryReader { geometry in
            LinearGradient(
                stops: FeedPigment.stops(for: palette, textEdge: textEdge).map { stop in
                    .init(color: Color(.sRGB, red: Double(stop.color.sRGB.x),
                                       green: Double(stop.color.sRGB.y), blue: Double(stop.color.sRGB.z)),
                          location: stop.location)
                },
                startPoint: .leading, endPoint: .trailing
            )
            .mask(alignment: .leading) {
                Rectangle().frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .animation(nil, value: fraction)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A full-height continuous capsule. The management menu sits inside the
/// trailing cap, matching the approved reference instead of cutting a notch
/// out of the card.
struct FeedTicketShape: Shape {
    func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let cornerRadius = min(rect.height / 2, FeedCardLayout.collapsedHeight / 2)
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .path(in: rect)
    }
}

/// One feed ticket carries both the action and the timer. A locked ticket opens
/// the duration picker; an active one opens its app. No social-network artwork
/// is repeated here — the app name is the identifier, and the shared canvas
/// gradient expresses remaining access while locked cards disclose choices inline.
struct FeedRowView: View {
    @ObservedObject var model: AppModel
    let group: TicketGroup
    let accessState: FeedRowAccessState
    let canOpen: Bool
    let showsUnlockOptions: Bool
    let onTap: () -> Void
    let onSettings: () -> Void
    let onDelete: () -> Void
    let onPurchased: () -> Void
    @ObservedObject var backdrop: TodayCanvasBackdropStore = .shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .body) private var headerHeight = FeedCardLayout.collapsedHeight
    @ScaledMetric(relativeTo: .body) private var choiceHeight: CGFloat = 70

    private var textEdge: Double {
        dynamicTypeSize.isAccessibilitySize || remainingMinutes == nil ? 0.80 : FeedPigment.textEdge
    }

    private var optionsHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? choiceHeight * CGFloat(group.enabledIntervals.count) + CGFloat(max(0, group.enabledIntervals.count - 1)) * 8 + 20
            : choiceHeight + 20
    }

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
            .frame(height: headerHeight + (showsUnlockOptions ? optionsHeight : 0))
    }

    private var rowGeometry: some View {
        GeometryReader { geometry in
            rowSurface(width: geometry.size.width)
        }
    }

    private func rowSurface(width: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            ticketBody(width: width)
            optionsMenu(width: width)
                .padding(.trailing, 12)
                .padding(
                    .top,
                    (headerHeight - FeedCardLayout.optionsControlDiameter) / 2
                )
        }
    }

    private func ticketBody(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color(red: 0.16, green: 0.13, blue: 0.19).opacity(reduceTransparency ? 1 : 0.86))

            FeedProgressFill(palette: backdrop.feedPalette, fraction: fillFraction, textEdge: textEdge)

            VStack(spacing: 0) {
                Button(action: onTap) {
                    rowContent(width: width)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(height: headerHeight)
                .accessibilityIdentifier("feed.\(group.id).access")
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint(accessibilityHint)
                .accessibilityAction(named: String(localized: "Settings"), onSettings)
                .accessibilityAction(named: String(localized: "Delete"), onDelete)

                if showsUnlockOptions {
                    FeedInlineDurationOptions(
                        model: model,
                        group: group,
                        onPurchased: onPurchased
                    )
                    .frame(height: optionsHeight)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .clipShape(FeedTicketShape())
    }

    private func rowContent(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(displayName)
                    .font(.geist(19, relativeTo: .body))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

                HStack(spacing: 6) {
                    if remainingMinutes == nil && !showsUnlockOptions {
                        Image(systemName: "lock.fill")
                            .font(.geist(12, relativeTo: .caption))
                    }
                    Text(statusText)
                        .font(.geist(14, relativeTo: .body))
                        .monospacedDigit()
                        .lineLimit(2)
                }
                .opacity(0.92)
            }
            .frame(width: max(0, width * textEdge - 22), alignment: .leading)

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.leading, 22)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var statusText: String {
        guard let remainingMinutes else {
            return showsUnlockOptions
                ? String(localized: "Open for a little while", comment: "Gentle prompt above a feed's inline duration choices")
                : String(localized: "Choose time")
        }
        return String(localized: "\(remainingMinutes) min left", comment: "Active feed row status")
    }

    private func optionsMenu(width: CGFloat) -> some View {
        Menu {
            Button(action: onSettings) {
                Label(String(localized: "Settings"), systemImage: "gearshape")
            }
            Button(role: .destructive, action: onDelete) {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        } label: {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    let position = (width - 12 - FeedCardLayout.optionsControlDiameter / 2 + CGFloat(index - 1) * 8) / max(1, width)
                    let darkInk = FeedPigment.menuUsesDarkInk(palette: backdrop.feedPalette,
                        fraction: fillFraction, position: position, textEdge: textEdge)
                    Circle()
                        .fill(darkInk ? Color.black.opacity(0.85) : Color.white)
                        .overlay(Circle().stroke(darkInk ? Color.white.opacity(0.5) : Color.black.opacity(0.5), lineWidth: 0.5))
                        .frame(width: 4, height: 4)
                }
            }
            .frame(
                width: FeedCardLayout.optionsControlDiameter,
                height: FeedCardLayout.optionsControlDiameter
            )
            .contentShape(Circle())
        }
        .accessibilityLabel(String(localized: "Feed options"))
        .accessibilityIdentifier("feed.\(group.id).options")
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

/// Horizontal unlock choices living inside the expanded feed surface.
struct FeedInlineDurationOptions: View {
    @ObservedObject var model: AppModel
    let group: TicketGroup
    let onPurchased: () -> Void

    @State private var purchasingWindow: AccessWindow?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var choiceHeight: CGFloat = 70

    private var windows: [AccessWindow] {
        AccessWindow.allCases.filter(group.enabledIntervals.contains)
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            ForEach(windows, id: \.self) { window in
                durationButton(window)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Choose how long to unlock"))
    }

    private func durationButton(_ window: AccessWindow) -> some View {
        let cost = group.cost(for: window)
        let canAfford = model.totalStepsBalance >= cost

        return Button {
            purchase(window: window, cost: cost)
        } label: {
            VStack(spacing: 7) {
                Text(String(localized: "\(window.minutes) min", comment: "Compact feed duration in minutes"))
                    .font(.geist(16, relativeTo: .body))
                    .lineLimit(1)

                Group {
                    if purchasingWindow == window {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(AppColors.brandAccent)
                    } else {
                        HStack(spacing: 5) {
                            Image(systemName: "drop.fill")
                                .font(.geist(12, relativeTo: .caption))
                            Text(FeedCardLayout.priceLabel(cost: cost))
                                .font(.geist(16, relativeTo: .body))
                                .monospacedDigit()
                        }
                    }
                }
                .foregroundStyle(canAfford ? AppColors.brandAccent : Color.white.opacity(0.58))
            }
            .frame(maxWidth: .infinity)
            .frame(height: choiceHeight)
            .foregroundStyle(.white)
            .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canAfford || purchasingWindow != nil)
        .opacity((!canAfford || purchasingWindow != nil) ? 0.55 : 1)
        .accessibilityLabel(
            String(localized: "\(window.displayName), \(cost) colors")
        )
        .accessibilityIdentifier("feed.\(group.id).duration.\(window.minutes)")
        .accessibilityHint(
            canAfford
                ? String(localized: "Double tap to unlock")
                : String(localized: "Not enough colors")
        )
    }

    private func purchase(window: AccessWindow, cost: Int) {
        guard purchasingWindow == nil else { return }
        purchasingWindow = window
        Task { @MainActor in
            await model.handlePayGatePaymentForGroup(
                groupId: group.id,
                window: window,
                costOverride: cost
            )
            purchasingWindow = nil

            guard model.unspentUsageBudgetMatchingShield(for: group.id) > 0 else { return }
            onPurchased()
        }
    }
}
