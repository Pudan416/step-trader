import Foundation

extension AppModel {
    struct PayGateSession: Identifiable {
        let id: String  // groupId
        let groupId: String
        let startedAt: Date
    }
}
