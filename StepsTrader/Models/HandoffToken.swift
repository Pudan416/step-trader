import Foundation

struct HandoffToken: Codable {
    let targetBundleId: String
    let targetAppName: String
    let createdAt: Date
    let tokenId: String
    
    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > AppConstants.Timing.handoffTokenExpiry
    }
}
