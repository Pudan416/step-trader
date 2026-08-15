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
}
