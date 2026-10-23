import Foundation
import Combine
import DeviceActivity

/// Serializes the existing stores' account boundary. No account identity is
/// published until its local working set is ready and its vault commit succeeds.
@MainActor
final class AccountHistoryCoordinator: ObservableObject {
    static let shared = AccountHistoryCoordinator()
    static let signedOutOwner = "local-signed-out"
    @Published private(set) var revision = UUID()
    @Published private(set) var isSwitching = false
    @Published private(set) var error: String?
    private var vault: AccountHistoryVault?
    private var tail: Task<Void, Never>?
    private var pendingCount = 0
    private var hydrationTask: Task<Bool, Never>?

    init(vault: AccountHistoryVault? = nil) { self.vault = vault }

    func transition(
        to owner: String, model: AppModel,
        currentOwner: @escaping @MainActor () -> String?,
        validateIdentity: @escaping @MainActor () throws -> Void,
        publishIdentity: @escaping @MainActor () -> Void
    ) async throws {
        // This must precede every producer drain, including a producer awaiting
        // an uncanceled Canvas upload child that is still waiting for auth init.
        SupabaseSyncService.shared.beginAccountSwitch()
        hydrationTask?.cancel()
        let previous = tail
        pendingCount += 1
        isSwitching = true
        defer { pendingCount -= 1; isSwitching = pendingCount > 0 }
        let operation = Task { @MainActor in
            await previous?.value
            try await self.performTransition(to: owner, model: model,
                currentOwner: currentOwner, validateIdentity: validateIdentity,
                publishIdentity: publishIdentity)
        }
        tail = Task { _ = try? await operation.value }
        try await operation.value
    }

    private func performTransition(
        to owner: String, model: AppModel,
        currentOwner: @MainActor () -> String?,
        validateIdentity: @MainActor () throws -> Void,
        publishIdentity: @MainActor () -> Void
    ) async throws {
        SupabaseSyncService.shared.beginAccountSwitch()
        var prepared: AccountHistoryVault.PreparedActivation?
        do {
            let vault = try self.vault ?? AccountHistoryStorage.makeVault()
            self.vault = vault
            await model.suspendHistoryWork()
            await SupabaseSyncService.shared.pauseForAccountSwitch()
            if let hydrationTask { _ = await hydrationTask.value }
            self.hydrationTask = nil
            try await model.blockingStore.suspendPersistence()
            try await model.userEconomyStore.suspendPersistence()
            await CanvasStorageService.shared.invalidatePendingWritesForAccountSwitch()
            await MePosterCanvasLoadCoordinator.shared.suspendForAccountSwitch()
            try await MePosterSnapshotCache.shared.suspendForAccountSwitch()
            try await HistoryThumbnailCache.shared.suspendForAccountSwitch()
            model.healthStore.stopObservingSteps()

            let defaults = UserDefaults.nowhere()
            let outgoingNames = try ShieldRebuildHelper.withAccountHistoryTransitionLock {
                UsageBudgetAccountBoundary.suspend(defaults: defaults)
            }
            stopMonitoring(outgoingNames)
            let incomingNames = try ShieldRebuildHelper.withAccountHistoryTransitionLock {
                prepared = try vault.prepareActivation(owner: owner)
                return UsageBudgetAccountBoundary.suspend(defaults: defaults)
            }
            stopMonitoring(incomingNames)
            await model.reloadAccountHistory()

            // MainActor cannot change the auth generation between this check,
            // the durable vault commit and synchronous credential publication.
            try validateIdentity()
            try ShieldRebuildHelper.withAccountHistoryTransitionLock {
                if let prepared { try vault.commitActivation(prepared) }
                UsageBudgetAccountBoundary.resume(defaults: defaults)
            }
            prepared = nil
            publishIdentity()
            await SupabaseSyncService.shared.resumeAfterAccountSwitch()
            resumeLocalWriters(model)
            revision = UUID()
            error = nil
        } catch {
            let failure = error
            do {
                guard let vault = self.vault else { throw failure }
                if let prepared {
                    try ShieldRebuildHelper.withAccountHistoryTransitionLock {
                        try vault.rollbackActivation(prepared)
                    }
                    await model.reloadAccountHistory()
                }
                // Resume an unchanged authenticated outgoing account only.
                // Otherwise keep admission closed and expose a retryable error.
                let owner = try vault.activeOwner
                if currentOwner() == owner {
                    try ShieldRebuildHelper.withAccountHistoryTransitionLock {
                        UsageBudgetAccountBoundary.resume(defaults: .nowhere())
                    }
                    await SupabaseSyncService.shared.resumeAfterAccountSwitch()
                    resumeLocalWriters(model)
                    revision = UUID()
                    if UserDefaults.nowhere().bool(forKey: SharedKeys.hasCompletedInitialRestore) {
                        _ = await SupabaseSyncService.shared.allowUploadsAfterRestore(for: owner)
                    }
                }
            } catch {
                // The vault's recovery journal remains durable; leave writers shut.
            }
            self.error = failure.localizedDescription
            throw failure
        }
    }

    private func stopMonitoring(_ names: [String]) {
        if !names.isEmpty { DeviceActivityCenter().stopMonitoring(names.map { DeviceActivityName($0) }) }
    }

    private func resumeLocalWriters(_ model: AppModel) {
        CanvasStorageService.shared.resumeWritesAfterAccountSwitch()
        MePosterCanvasLoadCoordinator.shared.resumeAfterAccountSwitch()
        MePosterSnapshotCache.shared.resumeAfterAccountSwitch()
        HistoryThumbnailCache.shared.resumeAfterAccountSwitch()
        model.userEconomyStore.resumePersistence()
        model.blockingStore.resumePersistence()
        model.restartAccountHistoryWork()
    }

    /// Initial auth restoration calls this only after `isInitialized` is true.
    /// A failed remote restore leaves local B editable and uploads closed.
    func hydrate(owner: String, model: AppModel) async -> Bool {
        guard !isSwitching, AuthenticationService.shared.currentUser?.id == owner else { return false }
        if let hydrationTask { return await hydrationTask.value }
        let generation = model.historyWorkGeneration
        let epoch = SupabaseSyncService.shared.captureSyncEpoch()
        let task = Task { @MainActor in
            await SupabaseSyncService.$historySyncEpoch.withValue(epoch) {
                let defaults = UserDefaults.nowhere()
                var restored = defaults.bool(forKey: SharedKeys.hasCompletedInitialRestore)
                if !restored { restored = await SupabaseSyncService.shared.restoreFromServer(model: model) }
                guard model.isHistoryWorkCurrent(generation),
                      AuthenticationService.shared.currentUser?.id == owner else { return false }
                guard restored else {
                    self.error = String(localized: "Couldn't load your history. Check your connection and try again.")
                    return false
                }
                defaults.set(true, forKey: SharedKeys.hasCompletedInitialRestore)
                guard await SupabaseSyncService.shared.allowUploadsAfterRestore(for: owner) else { return false }
                self.error = nil
                await SupabaseSyncService.shared.performFullSync(model: model)
                return model.isHistoryWorkCurrent(generation)
            }
        }
        hydrationTask = task
        let result = await task.value
        if model.isHistoryWorkCurrent(generation) { hydrationTask = nil }
        return result
    }
}
