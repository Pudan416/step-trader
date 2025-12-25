import Foundation

enum AutomationStatus {
    case none
    case pending
    case configured
}

enum AutomationCategory {
    case popular
    case other
}

struct AutomationApp: Identifiable {
    var id: String { bundleId }
    let name: String
    let scheme: String
    let icon: String
    let imageName: String?
    let link: String?
    let bundleId: String
    let category: AutomationCategory
    
    init(
        name: String,
        scheme: String,
        icon: String,
        imageName: String?,
        link: String?,
        bundleId: String,
        category: AutomationCategory = .popular
    ) {
        self.name = name
        self.scheme = scheme
        self.icon = icon
        self.imageName = imageName
        self.link = link
        self.bundleId = bundleId
        self.category = category
    }
}

struct GuideItem: Identifiable {
    var id: String { bundleId }
    let name: String
    let icon: String
    let imageName: String?
    let scheme: String
    let link: String?
    let status: AutomationStatus
    let bundleId: String
}
