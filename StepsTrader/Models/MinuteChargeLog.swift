import Foundation

struct MinuteChargeLog: Codable, Identifiable {
    var id: UUID { UUID() }
    let bundleId: String
    let timestamp: Date
    let cost: Int
    let balanceAfter: Int
}
