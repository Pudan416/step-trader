import Foundation
#if canImport(ManagedSettings)
import ManagedSettings
#endif
#if canImport(FamilyControls)
import FamilyControls
#endif

// MARK: - Ticket / Block Management
extension AppModel {
    // MARK: - Block Management Functions
    func timeAccessSelection(for bundleId: String) -> FamilyActivitySelection {
        blockingStore.timeAccessSelection(for: bundleId)
    }

    func saveTimeAccessSelection(_ selection: FamilyActivitySelection, for bundleId: String) {
        blockingStore.saveTimeAccessSelection(selection, for: bundleId)
    }

    func applyFamilyControlsSelection(for bundleId: String) {
        // No-op: selection is now managed via ticket groups or direct FamilyActivitySelection updates
    }

    func disableFamilyControlsShield() {
        blockingStore.rebuildFamilyControlsShield()
    }

    func rebuildFamilyControlsShield() {
        blockingStore.rebuildFamilyControlsShield()
    }

    func isTimeAccessEnabled(for bundleId: String) -> Bool {
        let selection = timeAccessSelection(for: bundleId)
        return !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
    }

    // MARK: - Cleanup Expired Unlocks
    func cleanupExpiredUnlocks() {
        blockingStore.cleanupExpiredUnlocks()
    }

    func scheduleSupabaseTicketUpsert(bundleId: String) {
        // TODO: Implement Supabase ticket sync
    }

    // MARK: - Tracking
    // Tracking logic is in AppModel+BudgetTracking.swift
}
