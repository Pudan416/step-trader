import Foundation
import CloudKit
import Combine

// MARK: - CloudKit Record Types
enum CloudKitRecordType: String {
    case shieldSettings = "ShieldSettings"
    case stepsSpent = "StepsSpent"
    case dayPass = "DayPass"
}

// MARK: - CloudKit Service
@MainActor
final class CloudKitService: ObservableObject {
    static let shared = CloudKitService()
    
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let containerIdentifier = "iCloud.personal-project.StepsTrader"
    
    @Published var isSyncing: Bool = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var isCloudKitAvailable: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        container = CKContainer(identifier: containerIdentifier)
        privateDatabase = container.privateCloudDatabase
        
        Task { await checkAccountStatus() }
    }
    
    // MARK: - Account Status
    func checkAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            isCloudKitAvailable = (status == .available)
            
            if !isCloudKitAvailable {
                syncError = mapAccountStatus(status)
            }
        } catch {
            isCloudKitAvailable = false
            syncError = error.localizedDescription
        }
    }
    
    private func mapAccountStatus(_ status: CKAccountStatus) -> String? {
        switch status {
        case .available: return nil
        case .noAccount: return "No iCloud account"
        case .restricted: return "iCloud restricted"
        case .couldNotDetermine: return "Could not determine iCloud status"
        case .temporarilyUnavailable: return "iCloud temporarily unavailable"
        @unknown default: return "Unknown iCloud status"
        }
    }
    
    // MARK: - Shield Settings Sync
    func saveShieldSettings(_ settings: [String: CloudShieldSettings]) async throws {
        guard isCloudKitAvailable else { return }
        
        isSyncing = true
        defer { isSyncing = false }
        
        // Delete existing records first
        let query = CKQuery(recordType: CloudKitRecordType.shieldSettings.rawValue, predicate: NSPredicate(value: true))
        let existingRecords = try await privateDatabase.records(matching: query)
        
        for (recordID, _) in existingRecords.matchResults {
            _ = try? await privateDatabase.deleteRecord(withID: recordID)
        }
        
        // Save new records
        for (bundleId, setting) in settings {
            let record = CKRecord(recordType: CloudKitRecordType.shieldSettings.rawValue)
            record["bundleId"] = bundleId
            record["entryCostSteps"] = setting.entryCostSteps
            record["dayPassCostSteps"] = setting.dayPassCostSteps
            record["minuteTariffEnabled"] = setting.minuteTariffEnabled
            record["familyControlsModeEnabled"] = setting.familyControlsModeEnabled
            record["allowedWindows"] = setting.allowedWindowsRaw
            record["updatedAt"] = Date()
            
            try await privateDatabase.save(record)
        }
        
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: "cloudkit_lastSync")
    }
    
    func fetchShieldSettings() async throws -> [String: CloudShieldSettings] {
        guard isCloudKitAvailable else { return [:] }
        
        isSyncing = true
        defer { isSyncing = false }
        
        let query = CKQuery(recordType: CloudKitRecordType.shieldSettings.rawValue, predicate: NSPredicate(value: true))
        let results = try await privateDatabase.records(matching: query)
        
        var settings: [String: CloudShieldSettings] = [:]
        
        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let bundleId = record["bundleId"] as? String {
                settings[bundleId] = CloudShieldSettings(
                    entryCostSteps: record["entryCostSteps"] as? Int ?? 0,
                    dayPassCostSteps: record["dayPassCostSteps"] as? Int ?? 0,
                    minuteTariffEnabled: record["minuteTariffEnabled"] as? Bool ?? false,
                    familyControlsModeEnabled: record["familyControlsModeEnabled"] as? Bool ?? false,
                    allowedWindowsRaw: record["allowedWindows"] as? [String] ?? []
                )
            }
        }
        
        lastSyncDate = Date()
        return settings
    }
    
    // MARK: - Steps Spent Sync
    func saveStepsSpent(_ stepsData: [String: [String: Int]]) async throws {
        guard isCloudKitAvailable else { return }
        
        isSyncing = true
        defer { isSyncing = false }
        
        // Delete existing records
        let query = CKQuery(recordType: CloudKitRecordType.stepsSpent.rawValue, predicate: NSPredicate(value: true))
        let existingRecords = try await privateDatabase.records(matching: query)
        
        for (recordID, _) in existingRecords.matchResults {
            _ = try? await privateDatabase.deleteRecord(withID: recordID)
        }
        
        // Save new records - one per day
        for (dayKey, appSteps) in stepsData {
            let record = CKRecord(recordType: CloudKitRecordType.stepsSpent.rawValue)
            record["dayKey"] = dayKey
            
            // Encode app steps as JSON
            if let jsonData = try? JSONEncoder().encode(appSteps),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                record["appStepsJson"] = jsonString
            }
            record["updatedAt"] = Date()
            
            try await privateDatabase.save(record)
        }
        
        lastSyncDate = Date()
    }
    
    func fetchStepsSpent() async throws -> [String: [String: Int]] {
        guard isCloudKitAvailable else { return [:] }
        
        isSyncing = true
        defer { isSyncing = false }
        
        let query = CKQuery(recordType: CloudKitRecordType.stepsSpent.rawValue, predicate: NSPredicate(value: true))
        let results = try await privateDatabase.records(matching: query)
        
        var stepsData: [String: [String: Int]] = [:]
        
        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let dayKey = record["dayKey"] as? String,
               let jsonString = record["appStepsJson"] as? String,
               let jsonData = jsonString.data(using: .utf8),
               let appSteps = try? JSONDecoder().decode([String: Int].self, from: jsonData) {
                stepsData[dayKey] = appSteps
            }
        }
        
        return stepsData
    }
    
    // MARK: - Day Pass Sync
    func saveDayPasses(_ dayPasses: [String: Date]) async throws {
        guard isCloudKitAvailable else { return }
        
        isSyncing = true
        defer { isSyncing = false }
        
        // Delete existing records
        let query = CKQuery(recordType: CloudKitRecordType.dayPass.rawValue, predicate: NSPredicate(value: true))
        let existingRecords = try await privateDatabase.records(matching: query)
        
        for (recordID, _) in existingRecords.matchResults {
            _ = try? await privateDatabase.deleteRecord(withID: recordID)
        }
        
        // Save new records
        for (bundleId, grantDate) in dayPasses {
            let record = CKRecord(recordType: CloudKitRecordType.dayPass.rawValue)
            record["bundleId"] = bundleId
            record["grantDate"] = grantDate
            record["updatedAt"] = Date()
            
            try await privateDatabase.save(record)
        }
        
        lastSyncDate = Date()
    }
    
    func fetchDayPasses() async throws -> [String: Date] {
        guard isCloudKitAvailable else { return [:] }
        
        isSyncing = true
        defer { isSyncing = false }
        
        let query = CKQuery(recordType: CloudKitRecordType.dayPass.rawValue, predicate: NSPredicate(value: true))
        let results = try await privateDatabase.records(matching: query)
        
        var dayPasses: [String: Date] = [:]
        
        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let bundleId = record["bundleId"] as? String,
               let grantDate = record["grantDate"] as? Date {
                dayPasses[bundleId] = grantDate
            }
        }
        
        return dayPasses
    }
    
    // MARK: - Full Sync
    func syncAll(model: AppModel) async {
        guard isCloudKitAvailable else {
            syncError = "iCloud not available"
            return
        }
        
        isSyncing = true
        syncError = nil
        
        do {
            // Upload local data to cloud
            let shieldSettings = model.getAllShieldSettingsForCloud()
            try await saveShieldSettings(shieldSettings)
            
            let stepsSpent = model.getStepsSpentByDayForCloud()
            try await saveStepsSpent(stepsSpent)
            
            let dayPasses = model.getDayPassesForCloud()
            try await saveDayPasses(dayPasses)
            
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: "cloudkit_lastSync")
            
        } catch {
            syncError = error.localizedDescription
        }
        
        isSyncing = false
    }
    
    func restoreFromCloud(model: AppModel) async {
        guard isCloudKitAvailable else {
            syncError = "iCloud not available"
            return
        }
        
        isSyncing = true
        syncError = nil
        
        do {
            // Fetch and restore shield settings
            let cloudSettings = try await fetchShieldSettings()
            if !cloudSettings.isEmpty {
                await model.restoreShieldSettingsFromCloud(cloudSettings)
            }
            
            // Fetch and restore steps spent
            let cloudSteps = try await fetchStepsSpent()
            if !cloudSteps.isEmpty {
                await model.restoreStepsSpentFromCloud(cloudSteps)
            }
            
            // Fetch and restore day passes
            let cloudDayPasses = try await fetchDayPasses()
            if !cloudDayPasses.isEmpty {
                await model.restoreDayPassesFromCloud(cloudDayPasses)
            }
            
            lastSyncDate = Date()
            
        } catch {
            syncError = error.localizedDescription
        }
        
        isSyncing = false
    }
}

// MARK: - Cloud Data Models
struct CloudShieldSettings: Codable {
    let entryCostSteps: Int
    let dayPassCostSteps: Int
    let minuteTariffEnabled: Bool
    let familyControlsModeEnabled: Bool
    let allowedWindowsRaw: [String]
}

