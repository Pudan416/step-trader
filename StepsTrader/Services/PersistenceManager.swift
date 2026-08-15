import Foundation

actor PersistenceManager {
    static let shared = PersistenceManager()
    
    private let fileManager = FileManager.default
    
    init() {
        Self.ensureStorageDirectoryExists()
    }
    
    /// Test-only redirection of the persisted-data directory. `nil` in production,
    /// where the directory is derived from the bundle id.
    ///
    /// Tests run inside the app's own process, so without this they read and
    /// write the container of whatever data the simulator happens to be carrying
    /// — and `AppModel.loadPastDaySnapshots()` goes further: when the snapshot
    /// file is missing it migrates the App Group key and then *deletes* it, so a
    /// test could destroy real history. Point this at a temporary directory in
    /// `setUp` and clear it in `tearDown`.
    nonisolated(unsafe) static var storageDirectoryOverride: URL?

    private static var storageDirectory: URL {
        if let storageDirectoryOverride { return storageDirectoryOverride }
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
