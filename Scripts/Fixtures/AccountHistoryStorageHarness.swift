import Foundation

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
        let domains = AccountHistoryStorage.domains(shared: shared, standard: standard)
        let vault = try AccountHistoryVault(root: root, domains: domains, locations: [])
        try vault.activate(owner: "A")
        let markers = ["supabaseHistoryLastFullSync_v1", "supabaseHistoryLastDayKey_v1"]
        let fence = ["accountHistoryBudgetEpoch_v1", "accountHistoryBudgetSuspended_v1"]
        for domain in domains {
            for key in fence { precondition(!domain.includes(key), "Device fence must not rotate with an account") }
            domain.defaults.set("A-full", forKey: markers[0])
            domain.defaults.set("A-day", forKey: markers[1])
            domain.defaults.set("A-epoch", forKey: fence[0])
        }
        try vault.activate(owner: "B")
        for domain in domains {
            precondition(domain.defaults.string(forKey: markers[0]) == nil)
            precondition(domain.defaults.string(forKey: markers[1]) == nil)
            domain.defaults.set("B-full", forKey: markers[0])
            domain.defaults.set("B-day", forKey: markers[1])
            domain.defaults.set("B-current-epoch", forKey: fence[0])
            domain.defaults.set(true, forKey: fence[1])
        }
        try vault.activate(owner: "A")
        for domain in domains {
            precondition(domain.defaults.string(forKey: markers[0]) == "A-full")
            precondition(domain.defaults.string(forKey: markers[1]) == "A-day")
            precondition(domain.defaults.string(forKey: fence[0]) == "B-current-epoch")
            precondition(domain.defaults.bool(forKey: fence[1]))
        }
        print("PASS account history freshness is scoped; device budget fence does not rotate")
    }
}
