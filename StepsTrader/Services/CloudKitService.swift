import Foundation

// CloudKitService has been superseded by SupabaseSyncService.
// Stub retained only for CloudTicketSettings type compatibility.

struct CloudTicketSettings: Codable {
    let entryCostSteps: Int
    let dayPassCostSteps: Int
    let familyControlsModeEnabled: Bool
    let allowedWindowsRaw: [String]
}
