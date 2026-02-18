import Foundation

enum TargetResolver {
    private static let targetToBundleId: [String: String] = [
        "instagram": "com.burbn.instagram",
        "tiktok": "com.zhiliaoapp.musically",
        "youtube": "com.google.ios.youtube",
        "telegram": "ph.telegra.Telegraph",
        "whatsapp": "net.whatsapp.WhatsApp",
        "snapchat": "com.toyopagroup.picaboo",
        "facebook": "com.facebook.Facebook",
        "linkedin": "com.linkedin.LinkedIn",
        "x": "com.atebits.Tweetie2",
        "twitter": "com.atebits.Tweetie2",
        "reddit": "com.reddit.Reddit",
        "pinterest": "com.pinterest"
    ]
    
    private static let targetToScheme: [String: String] = [
        "instagram": "instagram://",
        "tiktok": "tiktok://",
        "youtube": "youtube://",
        "telegram": "tg://",
        "whatsapp": "whatsapp://",
        "snapchat": "snapchat://",
        "facebook": "fb://",
        "linkedin": "linkedin://",
        "x": "twitter://",
        "twitter": "twitter://",
        "reddit": "reddit://",
        "pinterest": "pinterest://"
    ]

    private static let bundleToScheme: [String: String] = {
        var result: [String: String] = [:]
        for (target, bundle) in targetToBundleId {
            if let scheme = targetToScheme[target] {
                result[bundle] = scheme
            }
        }
        return result
    }()
    
    private static let bundleToDisplayName: [String: String] = [
        "com.burbn.instagram": "Instagram",
        "com.zhiliaoapp.musically": "TikTok",
        "com.google.ios.youtube": "YouTube",
        "ph.telegra.Telegraph": "Telegram",
        "net.whatsapp.WhatsApp": "WhatsApp",
        "com.toyopagroup.picaboo": "Snapchat",
        "com.facebook.Facebook": "Facebook",
        "com.linkedin.LinkedIn": "LinkedIn",
        "com.atebits.Tweetie2": "X",
        "com.reddit.Reddit": "Reddit",
        "com.pinterest": "Pinterest"
    ]

    /// Asset name in Assets.xcassets for shield/template icon. Use with UIImage(named:).
    /// Add matching .imageset (e.g. "instagram.imageset") so the icon appears on shields.
    private static let bundleToImageName: [String: String] = [
        "com.burbn.instagram": "instagram",
        "com.zhiliaoapp.musically": "tiktok",
        "com.google.ios.youtube": "youtube",
        "com.toyopagroup.picaboo": "snapchat",
        "com.reddit.Reddit": "reddit",
        "com.atebits.Tweetie2": "x",
        "com.facebook.Facebook": "facebook",
        "com.linkedin.LinkedIn": "linkedin",
        "com.pinterest": "pinterest",
        "ph.telegra.Telegraph": "telegram",
        "net.whatsapp.WhatsApp": "whatsapp"
    ]
    
    static func bundleId(from target: String?) -> String? {
        guard let target else { return nil }
        if target.contains(".") { return target }
        return targetToBundleId[target.lowercased()] ?? target
    }
    
    static func displayName(for bundleId: String) -> String {
        bundleToDisplayName[bundleId] ?? bundleId
    }

    /// Image asset name for shield icon. Name must match an imageset in Assets (e.g. instagram.imageset → "instagram").
    static func imageName(for bundleId: String) -> String? {
        bundleToImageName[bundleId]
    }
    
    static func urlScheme(for target: String) -> String? {
        targetToScheme[target.lowercased()]
    }

    static func urlScheme(forBundleId bundleId: String) -> String? {
        bundleToScheme[bundleId]
    }

    /// Primary and fallback URL schemes to try when opening an app by bundle id (e.g. redirect from block screen).
    static func primaryAndFallbackSchemes(for bundleId: String) -> [String] {
        switch bundleId {
        case "com.burbn.instagram":
            return ["instagram://app", "instagram://", "instagram://feed", "instagram://camera"]
        case "com.zhiliaoapp.musically":
            return ["tiktok://"]
        case "com.google.ios.youtube":
            return ["youtube://"]
        case "ph.telegra.Telegraph":
            return ["tg://", "telegram://"]
        case "net.whatsapp.WhatsApp":
            return ["whatsapp://"]
        case "com.toyopagroup.picaboo":
            return ["snapchat://"]
        case "com.facebook.Facebook":
            return ["fb://", "facebook://"]
        case "com.linkedin.LinkedIn":
            return ["linkedin://"]
        case "com.atebits.Tweetie2":
            return ["twitter://", "x://"]
        case "com.reddit.Reddit":
            return ["reddit://"]
        case "com.pinterest":
            return ["pinterest://"]
        default:
            if let scheme = bundleToScheme[bundleId] {
                return [scheme]
            }
            return []
        }
    }
}
