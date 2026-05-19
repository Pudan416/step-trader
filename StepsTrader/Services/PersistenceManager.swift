import Foundation

actor PersistenceManager {
    static let shared = PersistenceManager()
    
    private let fileManager = FileManager.default
    
    init() {
        Self.ensureStorageDirectoryExists()
    }
    
    private static var storageDirectory: URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "StepsTrader"
        return URL.applicationSupportDirectory.appending(path: bundleID, directoryHint: .isDirectory)
    }
    
    private var storageDirectory: URL {
        Self.storageDirectory
    }
    
    func save<T: Encodable>(_ object: T, to filename: String) async throws {
        let url = storageDirectory.appending(path: filename)
        do {
            let data = try JSONEncoder().encode(object)
            try data.write(to: url, options: .atomic)
        } catch {
            await ErrorManager.shared.handle(AppError.persistenceError(error))
            throw error
        }
    }
    
    func load<T: Decodable>(_ type: T.Type, from filename: String) async throws -> T {
        let url = storageDirectory.appending(path: filename)
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            // Don't report "file not found" as an error, just throw
            if (error as NSError).code != NSFileReadNoSuchFileError {
                await ErrorManager.shared.handle(AppError.persistenceError(error))
            }
            throw error
        }
    }
    
    func delete(_ filename: String) async {
        let url = storageDirectory.appending(path: filename)
        try? fileManager.removeItem(at: url)
    }
    
    func exists(_ filename: String) -> Bool {
        let url = storageDirectory.appending(path: filename)
        return fileManager.fileExists(atPath: url.path)
    }

    /// Ensure the storage directory exists (synchronous, safe to call repeatedly).
    private static func ensureStorageDirectoryExists() {
        let dir = storageDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// URL for payment transactions file (sync read/write from AppModel+PayGate). Same directory as other persisted data.
    static var paymentTransactionsFileURL: URL {
        ensureStorageDirectoryExists()
        return storageDirectory.appending(path: "paymentTransactions.json")
    }

    /// URL for past day snapshots file (sync read/write from AppModel+DailyEnergy). Same directory as other persisted data.
    static var pastDaySnapshotsFileURL: URL {
        ensureStorageDirectoryExists()
        return storageDirectory.appending(path: "pastDaySnapshots.json")
    }
}
