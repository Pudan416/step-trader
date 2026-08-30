import Foundation

/// Which artwork a row can draw for one app.
///
/// `FamilyActivitySelection` yields opaque `ApplicationToken`s and Apple provides no
/// API to read a name or icon from one. Registry apps carry a bundled asset we can
/// style freely; everything else must fall back to the system-drawn `Label(token)`,
/// which cannot be recoloured, masked, or reshaped. The list looks visually mixed as
/// a result, and that is accepted — see `Feeds-Spec.md`.
enum FeedIconSource: Equatable, Sendable {
    case asset(String)
    case systemLabel
}

/// How one `TicketGroup` renders as a row. Always one row per group.
enum FeedRowKind: Equatable, Sendable {
    case single(FeedIconSource)
    case cluster(sources: [FeedIconSource], total: Int)
}

/// The row is the timer: once access is bought, its yellow fill shows the
/// exact share of purchased usage that remains.
enum FeedRowAccessState: Equatable, Sendable {
    case locked
    case active(remainingMinutes: Int, fillFraction: Double)
}

enum FeedRowTapAction: Equatable, Sendable {
    case chooseDuration
    case openApp
    case openSettings
}

/// Single-open disclosure state for the inline unlock controls on Feeds.
struct FeedInlineExpansion: Equatable, Sendable {
    private(set) var expandedGroupID: String?

    init(expandedGroupID: String? = nil) {
        self.expandedGroupID = expandedGroupID
    }

    var scrollTargetID: String? {
        expandedGroupID.map { "\($0)-unlock-options" }
    }

    func toggling(groupID: String) -> Self {
        Self(expandedGroupID: expandedGroupID == groupID ? nil : groupID)
    }

    func collapsing(groupID: String) -> Self {
        guard expandedGroupID == groupID else { return self }
        return Self()
    }
}

enum FeedInlineLayout {
    static let coordinateSpaceName = "feeds-scroll-viewport"
    static let tabBarClearance: CGFloat = 16

    static func needsAutoScroll(
        optionsBottom: CGFloat,
        viewportHeight: CGFloat,
        tabBarHeight: CGFloat
    ) -> Bool {
        optionsBottom > viewportHeight - tabBarHeight - tabBarClearance
    }
}

enum FeedCardLayout {
    static let collapsedHeight: CGFloat = 82
    static let unlockOptionsHeight: CGFloat = 56
    static let addControlDiameter: CGFloat = 44
    static let optionsControlDiameter: CGFloat = 44

    static func height(showsUnlockOptions: Bool) -> CGFloat {
        collapsedHeight + (showsUnlockOptions ? unlockOptionsHeight : 0)
    }

    static func priceLabel(cost: Int) -> String {
        "− \(cost)"
    }
}

enum FeedRowModel {

    /// Overlapping icons beyond this add noise without adding information.
    /// The true count is carried separately so the row can still say "+4".
    static let clusterDisplayLimit = 3

    static func iconSource(forBundleId bundleId: String?) -> FeedIconSource {
        guard let bundleId, let imageName = TargetResolver.imageName(for: bundleId) else {
            return .systemLabel
        }
        return .asset(imageName)
    }

    static func kind(templateApp: String?, appTokenCount: Int) -> FeedRowKind {
        // A template group is validated to exactly one app at creation time
        // (`TargetResolver.singleAppPresetValidationMessage`), so its template
        // bundle id is authoritative regardless of what the token count reads.
        if let templateApp {
            return .single(iconSource(forBundleId: templateApp))
        }
        if appTokenCount <= 1 {
            return .single(.systemLabel)
        }
        let shown = min(appTokenCount, clusterDisplayLimit)
        return .cluster(
            sources: Array(repeating: .systemLabel, count: shown),
            total: appTokenCount
        )
    }

    static func accessState(
        remainingMinutes: Int,
        initialMinutes: Int
    ) -> FeedRowAccessState {
        guard remainingMinutes > 0 else { return .locked }

        // Older windows may not have an initial value persisted. In that
        // recovery case, treat the current observation as a fresh full row.
        let effectiveInitial = max(initialMinutes, remainingMinutes, 1)
        let fillFraction = min(
            1,
            max(0, Double(remainingMinutes) / Double(effectiveInitial))
        )
        return .active(
            remainingMinutes: remainingMinutes,
            fillFraction: fillFraction
        )
    }

    static func tapAction(
        for accessState: FeedRowAccessState,
        canOpen: Bool
    ) -> FeedRowTapAction {
        switch accessState {
        case .locked:
            return .chooseDuration
        case .active:
            return canOpen ? .openApp : .openSettings
        }
    }
}
