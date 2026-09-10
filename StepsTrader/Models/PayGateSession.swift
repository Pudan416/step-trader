import Foundation

struct PayGateSession: Identifiable {
    let id: String  // groupId
    let groupId: String
    let startedAt: Date
    let artwork: GateArtwork
}
