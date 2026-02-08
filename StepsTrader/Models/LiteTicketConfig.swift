import Foundation
#if canImport(FamilyControls)
import FamilyControls
#endif

// MARK: - Lite config for DeviceActivityMonitor extension
// Minimal payload: id, name, selection (base64), active. Avoids passing full
// TicketGroup/AppUnlockSettings to reduce memory and decode cost in the extension.

struct LiteTicketConfig: Encodable {
    static let storageKey = "liteTicketConfig_v1"
    let groups: [LiteTicketGroup]
}

struct LiteTicketGroup: Encodable {
    let id: String
    let name: String
    /// FamilyActivitySelection encoded as JSON then base64
    let selectionDataBase64: String
    /// true if minute tariff or family controls mode is enabled (used by extension for minute-mode block)
    let active: Bool
}
