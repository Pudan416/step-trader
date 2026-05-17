import Foundation
#if canImport(FamilyControls)
import FamilyControls
import ManagedSettings
#endif

#if canImport(FamilyControls)
typealias FamilyActivitySelection = FamilyControls.FamilyActivitySelection
typealias ApplicationToken = ManagedSettings.ApplicationToken
typealias ActivityCategoryToken = ManagedSettings.ActivityCategoryToken
#else
struct FamilyActivitySelection {
    var applicationTokens: Set<ApplicationToken> = []
    var categoryTokens: Set<ActivityCategoryToken> = []
    
    init() {}
}

final class ApplicationToken: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    override init() { super.init() }
    required init?(coder: NSCoder) { super.init() }
    func encode(with coder: NSCoder) {}
}

final class ActivityCategoryToken: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    override init() { super.init() }
    required init?(coder: NSCoder) { super.init() }
    func encode(with coder: NSCoder) {}
}
#endif
