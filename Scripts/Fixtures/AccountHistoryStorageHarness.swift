import Foundation
import CoreFoundation

@main
struct AccountHistoryStorageHarness {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "AccountHistoryScope." + UUID().uuidString
        let shared = UserDefaults(suiteName: suite)!
        let standard = UserDefaults(suiteName: suite + ".standard")!
        defer {
            shared.removePersistentDomain(forName: suite)
            standard.removePersistentDomain(forName: suite + ".standard")
            try? FileManager.default.removeItem(at: root)
        }
        let domains = AccountHistoryStorage.domains(shared: shared, standard: standard,
            sharedDomainName: suite, standardDomainName: suite + ".standard")
        precondition(domains.map(\.persistentDomainName) == [suite, suite + ".standard"], "fixture flush must use its own namespaces")
        let vault = try AccountHistoryVault(root: root, domains: domains, locations: [])
        try vault.activate(owner: "A")
        // Use the real pass encoder/decoder and production domains for both
        // App Group and app defaults. Matching IDs exercise owner isolation.
        let groupID = UUID().uuidString
        let now = Date()
        let passesA = domains.indices.map { index in
            UsageBudgetSession(minutes: 30 + index, startedAt: now,
                expiresAt: now.addingTimeInterval(Double(30 + index) * 60))
        }
        let passesB = domains.indices.map { index in
            UsageBudgetSession(minutes: 60 + index, startedAt: now,
                expiresAt: now.addingTimeInterval(Double(60 + index) * 60))
        }
        for (index, domain) in domains.enumerated() {
            passesA[index].save(to: domain.defaults, groupId: groupID)
        }
        let payloadsA = domains.map { $0.defaults.data(forKey: UsageBudgetSession.key(groupID))! }
        let markers = ["supabaseHistoryLastFullSync_v1", "supabaseHistoryLastDayKey_v1"]
        let fence = ["accountHistoryBudgetEpoch_v1", "accountHistoryBudgetSuspended_v1"]
        for domain in domains {
            for key in fence { precondition(!domain.includes(key), "Device fence must not rotate with an account") }
            domain.defaults.set("A-full", forKey: markers[0])
            domain.defaults.set("A-day", forKey: markers[1])
            domain.defaults.set("A-epoch", forKey: fence[0])
        }
        try vault.activate(owner: "B")
        for (index, domain) in domains.enumerated() {
            precondition(UsageBudgetSession.load(from: domain.defaults, groupId: groupID) == nil,
                "Incoming B must not inherit A's paid pass in either namespace")
            precondition(domain.defaults.object(forKey: SharedKeys.usageBudgetExpiryKey(groupID)) == nil,
                "Incoming B must not inherit A's compatibility deadline")
            passesB[index].save(to: domain.defaults, groupId: groupID)
            precondition(domain.defaults.string(forKey: markers[0]) == nil)
            precondition(domain.defaults.string(forKey: markers[1]) == nil)
            domain.defaults.set("B-full", forKey: markers[0])
            domain.defaults.set("B-day", forKey: markers[1])
            domain.defaults.set("B-current-epoch", forKey: fence[0])
            domain.defaults.set(true, forKey: fence[1])
        }
        let payloadsB = domains.map { $0.defaults.data(forKey: UsageBudgetSession.key(groupID))! }
        try vault.activate(owner: "A")
        for (index, domain) in domains.enumerated() {
            precondition(UsageBudgetSession.load(from: domain.defaults, groupId: groupID) == passesA[index],
                "Returning A must restore its pass, including generation and original deadline")
            precondition(domain.defaults.data(forKey: UsageBudgetSession.key(groupID)) == payloadsA[index],
                "The encoded paid record must restore byte for byte")
            precondition(domain.defaults.object(forKey: SharedKeys.usageBudgetExpiryKey(groupID)) as? Date == passesA[index].expiresAt)
            precondition(domain.defaults.string(forKey: markers[0]) == "A-full")
            precondition(domain.defaults.string(forKey: markers[1]) == "A-day")
            precondition(domain.defaults.string(forKey: fence[0]) == "B-current-epoch")
            precondition(domain.defaults.bool(forKey: fence[1]))
        }
        for (index, name) in [suite, suite + ".standard"].enumerated() {
            let restored = CFPreferencesCopyValue(markers[0] as CFString, name as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? String
            precondition(restored == "A-full", "domain \(index) must durably flush its own restored marker")
        }
        try vault.activate(owner: "B")
        for (index, domain) in domains.enumerated() {
            precondition(UsageBudgetSession.load(from: domain.defaults, groupId: groupID) == passesB[index],
                "Returning B must restore B's own paid pass")
            precondition(domain.defaults.data(forKey: UsageBudgetSession.key(groupID)) == payloadsB[index])
            precondition(domain.defaults.object(forKey: SharedKeys.usageBudgetExpiryKey(groupID)) as? Date == passesB[index].expiresAt)
        }
        print("PASS paid passes preserve owner, payload and deadline in both defaults namespaces")
        print("PASS account history freshness is scoped; device budget fence does not rotate")
    }
}
