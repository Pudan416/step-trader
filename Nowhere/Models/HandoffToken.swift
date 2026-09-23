import Foundation

struct HandoffToken: Codable {
    let targetBundleId: String
    let targetAppName: String
    let createdAt: Date
    let tokenId: String
    
    var isExpired: Bool {
        Date.now.timeIntervalSince(createdAt) > AppConstants.Timing.handoffTokenExpiry
    }
}
