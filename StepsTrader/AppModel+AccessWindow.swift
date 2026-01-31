import Foundation

// MARK: - Access Window Management
extension AppModel {
    // MARK: - Access Window Application
    func applyAccessWindow(_ window: AccessWindow, for bundleId: String) {
        let g = UserDefaults.stepsTrader()
        guard let until = accessWindowExpiration(window, now: Date()) else {
            g.removeObject(forKey: accessBlockKey(for: bundleId))
            return
        }
        g.set(until, forKey: accessBlockKey(for: bundleId))
        let remaining = Int(until.timeIntervalSince(Date()))
        print("⏱️ Access window set for \(bundleId) until \(until) (\(remaining) seconds)")
        // Push notifications on payment/activation removed per request
    }

    func isAccessBlocked(for bundleId: String) -> Bool {
        let g = UserDefaults.stepsTrader()
        guard let until = g.object(forKey: accessBlockKey(for: bundleId)) as? Date else {
            return false
        }
        if Date() >= until {
            g.removeObject(forKey: accessBlockKey(for: bundleId))
            return false
        }
        let remaining = Int(until.timeIntervalSince(Date()))
        print("⏱️ Access window active for \(bundleId), remaining \(remaining) seconds")
        return true
    }

    func remainingAccessSeconds(for bundleId: String) -> Int? {
        let g = UserDefaults.stepsTrader()
        guard let until = g.object(forKey: accessBlockKey(for: bundleId)) as? Date else { return nil }
        let remaining = Int(until.timeIntervalSince(Date()))
        if remaining <= 0 {
            g.removeObject(forKey: accessBlockKey(for: bundleId))
            return nil
        }
        return remaining
    }

    func accessBlockKey(for bundleId: String) -> String {
        "blockUntil_\(bundleId)"
    }
    
    // MARK: - Group Access Window Helpers
    func isGroupUnlocked(_ groupId: String) -> Bool {
        let defaults = UserDefaults.stepsTrader()
        let unlockKey = "groupUnlock_\(groupId)"
        if let unlockUntil = defaults.object(forKey: unlockKey) as? Date {
            return Date() < unlockUntil
        }
        return false
    }
    
    func remainingUnlockTime(for groupId: String) -> TimeInterval? {
        let defaults = UserDefaults.stepsTrader()
        let unlockKey = "groupUnlock_\(groupId)"
        guard let unlockUntil = defaults.object(forKey: unlockKey) as? Date else {
            return nil
        }
        let remaining = unlockUntil.timeIntervalSince(Date())
        return remaining > 0 ? remaining : nil
    }

    func purgeExpiredAccessWindows() {
        let g = UserDefaults.stepsTrader()
        let now = Date()
        
        // Purge expired blockUntil_* keys
        let blockKeys = g.dictionaryRepresentation().keys.filter { $0.hasPrefix("blockUntil_") }
        for key in blockKeys {
            if let until = g.object(forKey: key) as? Date {
                if now >= until {
                    g.removeObject(forKey: key)
                    print("🧹 Purged expired access window: \(key)")
                }
            } else {
                g.removeObject(forKey: key)
            }
        }
        
        // Purge expired groupUnlock_* keys
        let unlockKeys = g.dictionaryRepresentation().keys.filter { $0.hasPrefix("groupUnlock_") }
        for key in unlockKeys {
            if let until = g.object(forKey: key) as? Date {
                if now >= until {
                    g.removeObject(forKey: key)
                    let groupId = String(key.dropFirst("groupUnlock_".count))
                    print("🧹 Purged expired group unlock: \(groupId)")
                }
            } else {
                g.removeObject(forKey: key)
            }
        }
    }
}
