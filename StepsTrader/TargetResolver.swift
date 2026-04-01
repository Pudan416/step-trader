import Foundation
#if canImport(FamilyControls)
import FamilyControls
#endif

enum TargetResolver {

    // MARK: - Single-source registry

    private struct AppTarget {
        let targets: [String]
        let bundleId: String
        let displayName: String
        let imageName: String
        let scheme: String
        let fallbackSchemes: [String]
    }

    private static let registry: [AppTarget] = [
        AppTarget(targets: ["instagram"],
                  bundleId: "com.burbn.instagram",
                  displayName: "Instagram",
                  imageName: "instagram",
                  scheme: "instagram://",
                  fallbackSchemes: ["instagram://app", "instagram://", "instagram://feed", "instagram://camera"]),

        AppTarget(targets: ["tiktok"],
                  bundleId: "com.zhiliaoapp.musically",
                  displayName: "TikTok",
                  imageName: "tiktok",
                  scheme: "tiktok://",
                  fallbackSchemes: ["tiktok://"]),

        AppTarget(targets: ["youtube"],
                  bundleId: "com.google.ios.youtube",
                  displayName: "YouTube",
                  imageName: "youtube",
                  scheme: "youtube://",
                  fallbackSchemes: ["youtube://"]),

        AppTarget(targets: ["telegram"],
                  bundleId: "ph.telegra.Telegraph",
                  displayName: "Telegram",
                  imageName: "telegram",
                  scheme: "tg://",
                  fallbackSchemes: ["tg://", "telegram://"]),

        AppTarget(targets: ["whatsapp"],
                  bundleId: "net.whatsapp.WhatsApp",
                  displayName: "WhatsApp",
                  imageName: "whatsapp",
                  scheme: "whatsapp://",
                  fallbackSchemes: ["whatsapp://"]),

        AppTarget(targets: ["snapchat"],
                  bundleId: "com.toyopagroup.picaboo",
                  displayName: "Snapchat",
                  imageName: "snapchat",
                  scheme: "snapchat://",
                  fallbackSchemes: ["snapchat://"]),

        AppTarget(targets: ["facebook"],
                  bundleId: "com.facebook.Facebook",
                  displayName: "Facebook",
                  imageName: "facebook",
                  scheme: "fb://",
                  fallbackSchemes: ["fb://", "facebook://"]),

        AppTarget(targets: ["linkedin"],
                  bundleId: "com.linkedin.LinkedIn",
                  displayName: "LinkedIn",
                  imageName: "linkedin",
                  scheme: "linkedin://",
                  fallbackSchemes: ["linkedin://"]),

        AppTarget(targets: ["x", "twitter"],
                  bundleId: "com.atebits.Tweetie2",
                  displayName: "X",
                  imageName: "x",
                  scheme: "twitter://",
                  fallbackSchemes: ["twitter://", "x://"]),

        AppTarget(targets: ["reddit"],
                  bundleId: "com.reddit.Reddit",
                  displayName: "Reddit",
                  imageName: "reddit",
                  scheme: "reddit://",
                  fallbackSchemes: ["reddit://"]),

        AppTarget(targets: ["pinterest"],
                  bundleId: "com.pinterest",
                  displayName: "Pinterest",
                  imageName: "pinterest",
                  scheme: "pinterest://",
                  fallbackSchemes: ["pinterest://"])
    ]

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

    private static let bundleToEntry: [String: AppTarget] = {
        var map: [String: AppTarget] = [:]
        for entry in registry { map[entry.bundleId] = entry }
        return map
    }()

    // MARK: - Public API (unchanged)

    static func bundleId(from target: String?) -> String? {
        guard let target else { return nil }
        if target.contains(".") { return target }
        return targetToBundleId[target.lowercased()] ?? target
    }

    static func displayName(for bundleId: String) -> String {
        bundleToEntry[bundleId]?.displayName ?? bundleId
    }

    static func imageName(for bundleId: String) -> String? {
        bundleToEntry[bundleId]?.imageName
    }

    static func urlScheme(for target: String) -> String? {
        targetToScheme[target.lowercased()]
    }

    static func urlScheme(forBundleId bundleId: String) -> String? {
        bundleToEntry[bundleId]?.scheme
    }

    static func primaryAndFallbackSchemes(for bundleId: String) -> [String] {
        if let entry = bundleToEntry[bundleId] {
            return entry.fallbackSchemes
        }
        return []
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
