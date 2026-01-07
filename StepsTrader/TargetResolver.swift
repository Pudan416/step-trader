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
        "pinterest": "com.pinterest",
        "duolingo": "com.duolingo.DuolingoMobile"
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
        "pinterest": "pinterest://",
        "duolingo": "duolingo://"
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
        "com.pinterest": "Pinterest",
        "com.duolingo.DuolingoMobile": "Duolingo"
    ]
    
    static func bundleId(from target: String?) -> String? {
        guard let target else { return nil }
        if target.contains(".") { return target }
        return targetToBundleId[target.lowercased()] ?? target
    }
    
    static func displayName(for bundleId: String) -> String {
        bundleToDisplayName[bundleId] ?? bundleId
    }
    
    static func urlScheme(for target: String) -> String? {
        targetToScheme[target.lowercased()]
    }

    static func urlScheme(forBundleId bundleId: String) -> String? {
        bundleToScheme[bundleId]
    }
}
