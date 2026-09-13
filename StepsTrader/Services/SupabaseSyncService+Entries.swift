import Foundation
import os.log

enum OptionEntryCanonicalIdentity {
    static func key(for id: String) -> String {
        UUID(uuidString: id)?.uuidString ?? id
    }
}

enum OptionEntryRetrySupersession {
    static func deleteIDsToReplay(
        failedDeleteIDs: [String],
        desiredEntries: [OptionEntry]
    ) -> [String] {
        let desiredIDs = Set(desiredEntries.map { OptionEntryCanonicalIdentity.key(for: $0.id) })
        return failedDeleteIDs.filter {
            !desiredIDs.contains(OptionEntryCanonicalIdentity.key(for: $0))
        }
    }

    static func persistedDesiredEntries() -> [OptionEntry] {
        guard let data = UserDefaults.stepsTrader().data(forKey: SharedKeys.todayAdditions),
              let entries = try? JSONDecoder().decode([OptionEntry].self, from: data)
        else { return [] }
        return entries
    }

    static func recoveryEntry(
        afterReplayingDeleteID id: String,
        latestDesiredEntries: [OptionEntry]
    ) -> OptionEntry? {
        let canonicalID = OptionEntryCanonicalIdentity.key(for: id)
        return latestDesiredEntries.first {
            OptionEntryCanonicalIdentity.key(for: $0.id) == canonicalID
        }
    }
}

enum OptionEntryIntentOperation: Codable, Equatable {
    case upsert(OptionEntry)
    case delete(id: String)

    var id: String {
        switch self { case .upsert(let entry): return entry.id; case .delete(let id): return id }
    }

    /// Capture current-day edits before an asynchronous callback can reorder them.
    /// After rollover, absence from today's list says nothing about yesterday.
    static func upsertIntent(_ entry: OptionEntry, desiredEntries: [OptionEntry], currentDayKey: String) -> Self {
        if let latest = desiredEntries.first(where: {
            OptionEntryCanonicalIdentity.key(for: $0.id) == OptionEntryCanonicalIdentity.key(for: entry.id)
        }) { return .upsert(latest) }
        return entry.dayKey == currentDayKey ? .delete(id: entry.id) : .upsert(entry)
    }
}

struct PendingOptionEntryIntent: Codable, Equatable {
    let canonicalID: String
    let requestedID: String
    let version: UInt64
    // Optional only for decoding the old identity-only queue. Missing operation
    // must never be interpreted as deletion after a day rollover.
    let savedOperation: OptionEntryIntentOperation?
    let ownerUserID: String?
}

struct OptionEntryIntentPersistence {
    let defaults: UserDefaults
    let key: String

    func load() -> [String: PendingOptionEntryIntent] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: PendingOptionEntryIntent].self, from: data)
        else { return [:] }
        return decoded
    }

    func pending(canonicalID: String) -> PendingOptionEntryIntent? {
        load()[canonicalID]
    }

    @discardableResult
    func mark(_ operation: OptionEntryIntentOperation, ownerUserID: String? = nil) -> PendingOptionEntryIntent {
        let id = operation.id
        var intents = load()
        let canonicalID = OptionEntryCanonicalIdentity.key(for: id)
        if let existing = intents[canonicalID], let existingOwner = existing.ownerUserID,
           existingOwner != ownerUserID {
            // Local day data survives sign-out. A new account must not adopt or
            // remove a previous account's still-pending operation.
            return existing
        }
        let version = (intents[canonicalID]?.version ?? 0) &+ 1
        let intent = PendingOptionEntryIntent(
            canonicalID: canonicalID,
            requestedID: id,
            version: version,
            savedOperation: operation,
            ownerUserID: ownerUserID
        )
        intents[canonicalID] = intent
        save(intents)
        return intent
    }

    func recordUpsert(_ entry: OptionEntry, desiredEntries: [OptionEntry], currentDayKey: String, ownerUserID: String?) -> PendingOptionEntryIntent {
        let canonicalID = OptionEntryCanonicalIdentity.key(for: entry.id)
        let isStillPresent = desiredEntries.contains { OptionEntryCanonicalIdentity.key(for: $0.id) == canonicalID }
        if !isStillPresent, let existing = pending(canonicalID: canonicalID),
           existing.ownerUserID == ownerUserID, case .delete = existing.savedOperation {
            // A stale full-sync snapshot must not resurrect a later removal,
            // including after midnight while an earlier batch request was in flight.
            return existing
        }
        return mark(.upsertIntent(entry, desiredEntries: desiredEntries, currentDayKey: currentDayKey), ownerUserID: ownerUserID)
    }

    func operation(
        for intent: PendingOptionEntryIntent,
        desiredEntries: [OptionEntry]
    ) -> OptionEntryIntentOperation? {
        if let saved = intent.savedOperation { return saved }
        if let desired = desiredEntries.first(where: {
            OptionEntryCanonicalIdentity.key(for: $0.id) == intent.canonicalID
        }) {
            return .upsert(desired)
        }
        return nil // Ambiguous legacy marker: do not delete historical data.
    }

    /// A network response acknowledges an intent only when it succeeded and
    /// both its persisted version and its current desired operation are still
    /// the same after the suspension. Otherwise the marker remains durable.
    @discardableResult
    func finishAttempt(
        _ intent: PendingOptionEntryIntent,
        operation attemptedOperation: OptionEntryIntentOperation,
        succeeded: Bool,
        latestDesiredEntries: [OptionEntry]
    ) -> Bool {
        guard succeeded else { return false }
        var intents = load()
        guard intents[intent.canonicalID] == intent,
              operation(for: intent, desiredEntries: latestDesiredEntries) == attemptedOperation
        else { return false }
        intents.removeValue(forKey: intent.canonicalID)
        save(intents)
        return true
    }

    /// Upgrade old raw requests without discarding the only recoverable payload.
    /// An identity-only marker is not a newer durable operation.
    func migrateLegacyRequests(_ requests: [SupabasePendingSyncRequest]) -> Set<String> {
        let durableIDs = Set(load().filter { $0.value.savedOperation != nil }.map(\.key))
        var migratedIDs = Set<String>()
        for request in requests {
            guard let mutations = request.optionEntryMutations else { continue }
            for mutation in mutations where !durableIDs.contains(OptionEntryCanonicalIdentity.key(for: mutation.operation.id)) {
                mark(mutation.operation, ownerUserID: mutation.ownerUserID)
            }
            migratedIDs.insert(request.queueID)
        }
        return migratedIDs
    }

    private func save(_ intents: [String: PendingOptionEntryIntent]) {
        guard let data = try? JSONEncoder().encode(intents) else { return }
        defaults.set(data, forKey: key)
    }
}

enum OptionEntryIntentAttemptCompletion: Equatable {
    case acknowledge
    case retryLatest
    case leavePending
}

struct OptionEntryIntentAttemptToken: Hashable {
    let id: UUID
    let canonicalID: String
    let version: UInt64
}

actor OptionEntryIntentAttemptCoordinator {
    private var inFlight: [String: Set<UUID>] = [:]

    func begin(canonicalID: String, version: UInt64) -> OptionEntryIntentAttemptToken {
        let token = OptionEntryIntentAttemptToken(
            id: UUID(),
            canonicalID: canonicalID,
            version: version
        )
        inFlight[canonicalID, default: []].insert(token.id)
        return token
    }

    func finish(
        _ token: OptionEntryIntentAttemptToken,
        succeeded: Bool,
        currentVersion: UInt64?,
        operationStillCurrent: Bool
    ) -> OptionEntryIntentAttemptCompletion {
        inFlight[token.canonicalID]?.remove(token.id)
        if inFlight[token.canonicalID]?.isEmpty == true {
            inFlight.removeValue(forKey: token.canonicalID)
        }
        guard succeeded else { return .leavePending }
        guard currentVersion == token.version,
              operationStillCurrent,
              inFlight[token.canonicalID]?.isEmpty != false
        else { return .retryLatest }
        return .acknowledge
    }
}

// MARK: - Option Entry Sync
extension SupabaseSyncService {
    
    func syncOptionEntries(_ entries: [OptionEntry]) async {
        let owner = await optionEntryOwnerID()
        migrateLegacyOptionEntryIntents()
        let payload = entries.sorted(by: { $0.timestamp < $1.timestamp })
        let canonicalIDs = payload.map {
            recordOptionEntryUpsert($0, ownerUserID: owner).canonicalID
        }
        
        entriesSyncTask?.cancel()
        entriesSyncTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            for canonicalID in canonicalIDs {
                await reconcileOptionEntryIntent(canonicalID: canonicalID)
            }
        }
    }

    private func sendOptionEntryUpsert(_ entry: OptionEntry, ownerUserID: String?) async -> Bool {
        guard let auth = await authenticatedContext(),
              ownerUserID == nil || ownerUserID == auth.userId else { return false }
        let token = auth.token
        let userId = auth.userId
        
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_happening_additions")
            guard var urlComps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return false }
            urlComps.queryItems = [URLQueryItem(name: "on_conflict", value: "id")]
            guard let url = urlComps.url else { return false }
            
            let rows = [OptionEntryUpsertRow(
                entry: entry,
                userID: userId,
                createdAt: iso8601String(entry.timestamp)
            )]
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "prefer")
            request.httpBody = try JSONEncoder().encode(rows)
            
            let (data, response) = try await network.data(for: request)
            if response.statusCode < 400 {
                AppLogger.network.debug("📡 Option entry synced")
                return true
            } else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                AppLogger.network.error("📡 Option entries sync failed: HTTP \(response.statusCode) - \(body)")
                return false
            }
        } catch {
            AppLogger.network.error("📡 Option entries sync error: \(error.localizedDescription)")
            return false
        }
    }

    func performEntriesSyncForFullSync(_ entries: [OptionEntry]) async {
        let owner = await optionEntryOwnerID()
        migrateLegacyOptionEntryIntents()
        let identities = entries.map { recordOptionEntryUpsert($0, ownerUserID: owner).canonicalID }
        for identity in identities {
            await reconcileOptionEntryIntent(canonicalID: identity)
        }
    }

    /// Syncs one client-identified addition. Upserting by `id` makes retries
    /// idempotent while still allowing the same happening multiple times.
    func syncOptionEntry(_ entry: OptionEntry) async {
        let owner = await optionEntryOwnerID()
        migrateLegacyOptionEntryIntents()
        let intent = recordOptionEntryUpsert(entry, ownerUserID: owner)
        supersedeQueuedOptionEntryDelete(id: entry.id)
        await reconcileOptionEntryIntent(canonicalID: intent.canonicalID)
    }

    func deleteOptionEntry(id: String) async {
        let owner = await optionEntryOwnerID()
        migrateLegacyOptionEntryIntents()
        let desired = OptionEntryRetrySupersession.recoveryEntry(
            afterReplayingDeleteID: id,
            latestDesiredEntries: OptionEntryRetrySupersession.persistedDesiredEntries()
        )
        let operation: OptionEntryIntentOperation = desired.map { .upsert($0) } ?? .delete(id: id)
        let intent = optionEntryIntentStore.mark(operation, ownerUserID: owner)
        supersedeQueuedOptionEntryDelete(id: id)
        await reconcileOptionEntryIntent(canonicalID: intent.canonicalID)
    }

    private func sendOptionEntryDelete(id: String, ownerUserID: String?) async -> Bool {
        guard let auth = await authenticatedContext(),
              ownerUserID == nil || ownerUserID == auth.userId else { return false }
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_happening_additions")
            guard var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return false }
            comps.queryItems = [
                URLQueryItem(name: "id", value: "eq.\(id)"),
                URLQueryItem(name: "user_id", value: "eq.\(auth.userId)")
            ]
            guard let url = comps.url else { return false }
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "authorization")
            let (data, response) = try await network.data(for: request)
            guard response.statusCode < 400 else {
                AppLogger.network.error("📡 Option entry delete failed: HTTP \(response.statusCode)")
                return false
            }
            AppLogger.network.debug("📡 Option entry deleted: \(id, privacy: .public)")
            _ = data
            return true
        } catch {
            AppLogger.network.error("📡 Option entry delete error: \(error.localizedDescription)")
            return false
        }
    }

    func drainPendingOptionEntryIntents() async {
        for canonicalID in optionEntryIntentStore.load().keys.sorted() {
            await reconcileOptionEntryIntent(canonicalID: canonicalID)
        }
    }

    private func optionEntryOwnerID() async -> String? {
        await AuthenticationService.shared.waitForInitialization()
        return await AuthenticationService.shared.currentUser?.id
    }

    private func recordOptionEntryUpsert(_ entry: OptionEntry, ownerUserID: String?) -> PendingOptionEntryIntent {
        let dayKey = AppModel.dayKey(for: .now)
        return optionEntryIntentStore.recordUpsert(entry,
            desiredEntries: OptionEntryRetrySupersession.persistedDesiredEntries(),
            currentDayKey: dayKey, ownerUserID: ownerUserID)
    }

    /// Replay a durable operation/payload, independent of the current day list.
    /// Versions and the attempt coordinator still settle stale in-flight requests.
    private func reconcileOptionEntryIntent(canonicalID: String) async {
        for _ in 0..<8 {
            guard let intent = optionEntryIntentStore.pending(canonicalID: canonicalID) else { return }
            let desiredEntries = OptionEntryRetrySupersession.persistedDesiredEntries()
            guard let operation = optionEntryIntentStore.operation(
                for: intent,
                desiredEntries: desiredEntries
            ) else { return }
            let token = await optionEntryAttemptCoordinator.begin(
                canonicalID: canonicalID,
                version: intent.version
            )
            let succeeded: Bool
            switch operation {
            case let .upsert(entry):
                succeeded = await sendOptionEntryUpsert(entry, ownerUserID: intent.ownerUserID)
            case let .delete(id):
                succeeded = await sendOptionEntryDelete(id: id, ownerUserID: intent.ownerUserID)
            }

            let latestIntent = optionEntryIntentStore.pending(canonicalID: canonicalID)
            let latestDesiredEntries = OptionEntryRetrySupersession.persistedDesiredEntries()
            let operationStillCurrent = latestIntent == intent
                && optionEntryIntentStore.operation(
                    for: intent,
                    desiredEntries: latestDesiredEntries
                ) == operation
            let completion = await optionEntryAttemptCoordinator.finish(
                token,
                succeeded: succeeded,
                currentVersion: latestIntent?.version,
                operationStillCurrent: operationStillCurrent
            )
            switch completion {
            case .acknowledge:
                _ = optionEntryIntentStore.finishAttempt(
                    intent,
                    operation: operation,
                    succeeded: true,
                    latestDesiredEntries: latestDesiredEntries
                )
                return
            case .leavePending:
                return
            case .retryLatest:
                continue
            }
        }
    }
    
    func loadOptionEntriesFromServer(dayKey: String) async -> [OptionEntry]? {
        guard let auth = await authenticatedContext() else { return nil }
        let token = auth.token
        let userId = auth.userId
        
        do {
            let cfg = try SupabaseConfig.load()
            let url = cfg.baseURL.appendingPathComponent("rest/v1/user_happening_additions")
            guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            comps.queryItems = [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "day_key", value: "eq.\(dayKey)"),
                URLQueryItem(name: "select", value: "*")
            ]
            guard let finalURL = comps.url else { return nil }
            
            var request = URLRequest(url: finalURL)
            request.httpMethod = "GET"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "accept")
            
            let (data, response) = try await network.data(for: request)
            guard response.statusCode < 400 else { return nil }
            
            let rows = try JSONDecoder().decode([OptionEntryRow].self, from: data)
            let formatter = ISO8601DateFormatter()
            return rows.map { row in
                OptionEntry(
                    id: row.id,
                    dayKey: row.dayKey,
                    optionId: row.optionId,
                    colorHex: row.colorHex,
                    timestamp: formatter.date(from: row.createdAt) ?? Date.now,
                    assetVariant: row.assetVariant
                )
            }
        } catch {
            AppLogger.network.error("📡 Failed to load option entries: \(error.localizedDescription)")
            return nil
        }
    }
}

struct OptionEntryUpsertRow: Encodable {
    let id: String
    let userID: String
    let dayKey: String
    let optionID: String
    let colorHex: String
    let assetVariant: Int?
    let createdAt: String

    init(entry: OptionEntry, userID: String, createdAt: String) {
        id = entry.id
        self.userID = userID
        dayKey = entry.dayKey
        optionID = entry.optionId
        colorHex = entry.colorHex
        assetVariant = entry.assetVariant
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case dayKey = "day_key"
        case optionID = "option_id"
        case colorHex = "color_hex"
        case assetVariant = "asset_variant"
        case createdAt = "created_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(dayKey, forKey: .dayKey)
        try container.encode(optionID, forKey: .optionID)
        try container.encode(colorHex, forKey: .colorHex)
        if let assetVariant {
            try container.encode(assetVariant, forKey: .assetVariant)
        } else {
            try container.encodeNil(forKey: .assetVariant)
        }
        try container.encode(createdAt, forKey: .createdAt)
    }
}

struct OptionEntryRow: Codable {
    let id: String
    let dayKey: String
    let optionId: String
    let colorHex: String
    let assetVariant: Int?
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case dayKey = "day_key"
        case optionId = "option_id"
        case colorHex = "color_hex"
        case assetVariant = "asset_variant"
        case createdAt = "created_at"
    }
}
