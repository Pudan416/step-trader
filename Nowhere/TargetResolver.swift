import Foundation
#if canImport(FamilyControls)
import FamilyControls
#endif

enum TargetResolver {

    // MARK: - Single-source registry

    private static let registry = AppLaunchCatalog.targets

    // MARK: - Derived lookup tables (built once, lazily)

    private static let targetToBundleId: [String: String] = {
        var map: [String: String] = [:]
        for entry in registry {
            for t in entry.targets { map[t] = entry.bundleId }
        }
        return map
    }()

    private static let targetToScheme: [String: String] = {
        var map: [String: String] = [:]
        for entry in registry {
            for t in entry.targets { map[t] = entry.scheme }
        }
        return map
    }()

    private static let bundleToEntry: [String: AppLaunchCatalog.Target] = {
        var map: [String: AppLaunchCatalog.Target] = [:]
        for entry in registry { map[entry.bundleId] = entry }
        return map
    }()

    // MARK: - Public API (unchanged)

    static func bundleId(from target: String?) -> String? {
        guard let target else { return nil }
        let canonical = AppLaunchCatalog.canonicalBundleId(target)
        if canonical.contains(".") { return canonical }
        return targetToBundleId[canonical.lowercased()] ?? canonical
    }

    static func displayName(for bundleId: String) -> String {
        bundleToEntry[AppLaunchCatalog.canonicalBundleId(bundleId)]?.displayName ?? bundleId
    }

    static func urlScheme(for target: String) -> String? {
        targetToScheme[target.lowercased()]
    }

    static func urlScheme(forBundleId bundleId: String) -> String? {
        bundleToEntry[AppLaunchCatalog.canonicalBundleId(bundleId)]?.scheme
    }

    static func primaryAndFallbackSchemes(for bundleId: String) -> [String] {
        if let entry = bundleToEntry[AppLaunchCatalog.canonicalBundleId(bundleId)] {
            return entry.fallbackSchemes
        }
        return []
    }

    /// Apple-verified Universal Links for a target app, preferred over custom schemes
    /// when re-opening it (see `AppLaunchCatalog.Target.universalLinks`). Empty for apps with none.
    static func universalLinks(forBundleId bundleId: String) -> [String] {
        bundleToEntry[AppLaunchCatalog.canonicalBundleId(bundleId)]?.universalLinks ?? []
    }

    /// Whether we know how to re-open this app (has at least one Universal Link or
    /// custom scheme). Callers gate their "open" affordance on this.
    static func canOpen(bundleId: String) -> Bool {
        guard let entry = bundleToEntry[AppLaunchCatalog.canonicalBundleId(bundleId)] else { return false }
        return !entry.universalLinks.isEmpty || !entry.fallbackSchemes.isEmpty
    }

#if canImport(FamilyControls)
    static func supportsSingleAppPreset(_ selection: FamilyActivitySelection) -> Bool {
        selection.categoryTokens.isEmpty && selection.applicationTokens.count == 1
    }

    static func singleAppPresetValidationMessage(
        for selection: FamilyActivitySelection,
        templateBundleId: String?
    ) -> String? {
        let hasAnySelection = !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
        guard hasAnySelection else { return nil }
        guard !supportsSingleAppPreset(selection) else { return nil }

        if let templateBundleId {
            return "This preset should include only one app. Find \(displayName(for: templateBundleId)) in the list of your apps or use a search to find it."
        }
        return "This preset should include only one app. Use the search to find the app you need."
    }
#endif
}
