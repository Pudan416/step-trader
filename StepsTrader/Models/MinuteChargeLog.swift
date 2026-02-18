import Foundation

struct MinuteChargeLog: Codable, Identifiable {
    let id: UUID
    let bundleId: String
    let timestamp: Date
    let cost: Int
    let balanceAfter: Int

    init(bundleId: String, timestamp: Date, cost: Int, balanceAfter: Int) {
        self.id = UUID()
        self.bundleId = bundleId
        self.timestamp = timestamp
        self.cost = cost
        self.balanceAfter = balanceAfter
    }
}
