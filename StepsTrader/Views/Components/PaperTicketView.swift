import SwiftUI
import Combine
#if canImport(FamilyControls)
import FamilyControls
#endif

// MARK: - Paper Ticket View

/// Single-sided ticket card. Two states:
/// - Locked: icon + title + lock badge + unlock pill buttons + gear
/// - Unlocked: icon + title + open badge + progress bar + gear
struct PaperTicketView: View {
    @ObservedObject var model: AppModel
    let group: TicketGroup
    let colorScheme: ColorScheme
    var onSettings: () -> Void = {}

    @Environment(\.openURL) private var openURL
    @State private var isUnlocking = false
    @State private var resolvedTitle: String?
    @State private var liveBudget: Int = 0
    @State private var liveBudgetInitial: Int = 0

    // MARK: - Thread-safe title cache

    private static let titleCacheLock = NSLock()
    private static var _titleCache: [String: String] = [:]

    private static func cachedTitle(forGroupId id: String) -> String? {
        titleCacheLock.withLock { _titleCache[id] }
    }

    private static func setCachedTitle(_ title: String, forGroupId id: String) {
        titleCacheLock.withLock { _titleCache[id] = title }
    }

    static func removeCachedTitle(forGroupId id: String) {
        titleCacheLock.withLock { _titleCache[id] = nil }
    }

    private let accent = AppColors.brandAccent

    private var cardBaseColor: Color {
        isUnlocked ? .white : accent
    }

    private var isUnlocked: Bool { liveBudget > 0 }
    private var appsCount: Int {
        group.selection.applicationTokens.count + group.selection.categoryTokens.count
    }
    private let intervals: [AccessWindow] = [.minutes10, .minutes30, .hour1]

    private var displayTitle: String {
        resolvedTitle ?? (group.name.isEmpty ? String(localized: "Feed") : group.name)
    }

    var body: some View {
        ZStack {
            RayCapsuleSurface(baseColor: cardBaseColor, direction: isUnlocked ? .right : .left)

            if isUnlocked {
                Capsule()
                    .strokeBorder(accent.opacity(0.4), lineWidth: 1)
            }

            HStack(spacing: 0) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.08))
                        ticketIcon
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                    }
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(displayTitle)
                                .font(.body)
                                .foregroundStyle(Color(.label))
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: isUnlocked ? "lock.open" : "lock")
                                .font(.caption2.weight(.regular))
                                .foregroundStyle(isUnlocked ? accent : Color(.label).opacity(0.35))
                        }

                        if isUnlocked {
                            budgetProgressBar
                        } else {
                            unlockPills
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .contentShape(Rectangle())
                .onTapGesture { handleCardTap() }

                Button {
                    onSettings()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.black.opacity(0.3))
                        .frame(width: 40, height: 80)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Feed settings", comment: "PaperTicket – ellipsis button VoiceOver label"))
            }
        }
        .frame(height: 80)
        .accessibilityElement(children: .combine)
        .onAppear { refreshBudget() }
        .task(id: group.id) {
            resolvedTitle = computeTicketTitle()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                refreshBudget()
            }
        }
    }

    private func refreshBudget() {
        let defaults = UserDefaults.stepsTrader()
        liveBudget = defaults.integer(forKey: SharedKeys.usageBudgetKey(group.id))
        liveBudgetInitial = defaults.integer(forKey: SharedKeys.usageBudgetInitialKey(group.id))
    }

    private func handleCardTap() {
        if let bundleId = group.templateApp,
           let scheme = TargetResolver.primaryAndFallbackSchemes(for: bundleId).first,
           let url = URL(string: scheme) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            openURL(url)
        } else {
            onSettings()
        }
    }

    // MARK: - Unlock pills (locked state)

    private var unlockPills: some View {
        let enabledIntervals = intervals.filter { group.enabledIntervals.contains($0) }
        return HStack(spacing: 5) {
            ForEach(enabledIntervals, id: \.self) { interval in
                unlockPill(interval: interval)
            }
            Spacer(minLength: 0)
        }
        #if DEBUG
        .coachMarkAnchor(.tapUnlockPill)
        #endif
    }

    private func unlockPill(interval: AccessWindow) -> some View {
        let cost = group.cost(for: interval)
        let canAfford = model.userEconomyStore.totalStepsBalance >= cost
        let label = interval.displayName

        return Button {
            guard canAfford, !isUnlocking else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #if DEBUG
            CoachMarkManager.postAction(for: .tapUnlockPill)
            #endif
            Task {
                isUnlocking = true
                await model.handlePayGatePaymentForGroup(groupId: group.id, window: interval, costOverride: cost)
                refreshBudget()
                isUnlocking = false
            }
        } label: {
            Text("\(label) · \(cost)")
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(Color.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(accent.opacity(canAfford ? 1.0 : 0.25))
                        .overlay(Capsule().strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
        .disabled(!canAfford || isUnlocking)
        .accessibilityLabel(String(localized: "Unlock for \(label), costs \(cost) colors", comment: "PaperTicket – unlock pill VoiceOver label"))
        .accessibilityHint(canAfford ? String(localized: "Double tap to unlock", comment: "PaperTicket – unlock pill VoiceOver hint") : String(localized: "Not enough colors", comment: "PaperTicket – unlock pill VoiceOver hint"))
    }

    // MARK: - Budget progress bar (unlocked state)

    private var budgetProgressBar: some View {
        let remaining = liveBudget
        let initial = max(liveBudgetInitial, remaining, 1)
        let fraction = Double(remaining) / Double(initial)

        return HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.1))
                    Capsule()
                        .fill(accent)
                        .frame(width: max(geo.size.width * fraction, 4))
                }
            }
            .frame(height: 5)

            Text(String(localized: "\(remaining)m", comment: "PaperTicket – remaining budget in minutes, e.g. '42m'"))
                .font(.caption2.weight(.medium).monospaced())
                .foregroundStyle(.black.opacity(0.5))
                .monospacedDigit()
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var ticketIcon: some View {
        if let templateApp = group.templateApp,
           let imageName = TargetResolver.imageName(for: templateApp),
           let uiImage = UIImage(named: imageName) ?? UIImage(named: imageName.lowercased()) ?? UIImage(named: imageName.capitalized) {
            Image(uiImage: uiImage)
                .resizable().scaledToFill()
        } else {
            #if canImport(FamilyControls)
            if let firstToken = group.selection.applicationTokens.first {
                AppIconView(token: firstToken)
            } else if let firstCat = group.selection.categoryTokens.first {
                CategoryIconView(token: firstCat)
            } else {
                Image(systemName: "app")
                    .font(.title3).foregroundStyle(Color.primary.opacity(0.4))
            }
            #else
            Image(systemName: "app")
                .font(.title3).foregroundStyle(Color.primary.opacity(0.4))
            #endif
        }
    }

    private func computeTicketTitle() -> String {
        if let cached = Self.cachedTitle(forGroupId: group.id) {
            return cached
        }
        if let templateApp = group.templateApp {
            let name = TargetResolver.displayName(for: templateApp)
            Self.setCachedTitle(name, forGroupId: group.id)
            return name
        }
        #if canImport(FamilyControls)
        let defaults = UserDefaults.stepsTrader()
        if appsCount == 1, let firstToken = group.selection.applicationTokens.first,
           let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: firstToken, requiringSecureCoding: true) {
            let tokenKey = SharedKeys.fcAppNameKey(tokenData.base64EncodedString())
            if let name = defaults.string(forKey: tokenKey) {
                Self.setCachedTitle(name, forGroupId: group.id)
                return name
            }
        }
        #endif
        if appsCount == 0 { return String(localized: "Empty Feed", comment: "PaperTicket – empty feed placeholder title") }
        return group.name.isEmpty ? String(localized: "\(appsCount) apps", comment: "PaperTicket – app count subtitle") : group.name
    }

}

enum RayDirection {
    case left
    case right
}

/// Native SwiftUI recreation of ray SVG surfaces:
/// - `ray 1`: radial shade anchored on the left
/// - `ray 2`: radial shade anchored on the right
struct RayCapsuleSurface: View {
    let baseColor: Color
    let direction: RayDirection

    // Extracted from ray1/ray2 SVGs: 341x65 with radial stop at 0.889432.
    private let gradientStop: CGFloat = 0.889432
    private let radiusScale: CGFloat = 310.5 / 341.0

    private var center: UnitPoint {
        switch direction {
        case .left:
            return UnitPoint(x: 26.0 / 341.0, y: 32.5 / 65.0)
        case .right:
            return UnitPoint(x: 315.0 / 341.0, y: 32.5 / 65.0)
        }
    }

    private var alphaGradient: LinearGradient {
        switch direction {
        case .left:
            // Front side: bright left -> transparent right.
            return LinearGradient(
                stops: [
                    .init(color: .white, location: 0.00),
                    .init(color: .white.opacity(0.75), location: 0.20),
                    .init(color: .white.opacity(0.50), location: 0.35),
                    .init(color: .white.opacity(0.20), location: 0.50),
                    .init(color: .clear, location: 0.75)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .right:
            // Back side: bright right -> transparent left.
            return LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.25),
                    .init(color: .white.opacity(0.20), location: 0.50),
                    .init(color: .white.opacity(0.50), location: 0.65),
                    .init(color: .white.opacity(0.75), location: 0.80),
                    .init(color: .white, location: 1.00)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            Capsule()
                .fill(baseColor)
                .overlay(
                    Capsule().fill(
                        RadialGradient(
                            stops: [
                                .init(color: .black.opacity(0.12), location: 0),
                                .init(color: .clear, location: gradientStop)
                            ],
                            center: center,
                            startRadius: 0,
                            endRadius: width * radiusScale
                        )
                    )
                )
                .mask(
                    Capsule()
                        .fill(alphaGradient)
                )
        }
    }
}
