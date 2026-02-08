import Foundation

actor PersistenceManager {
    static let shared = PersistenceManager()
    
    private let fileManager = FileManager.default
    
    init() {
        // Ensure directory exists
        let directory = Self.storageDirectory
        Task {
            let fileManager = FileManager.default
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                print("❌ PersistenceManager: Failed to create storage directory: \(error)")
            }
        }
    }
    
    private static var storageDirectory: URL {
        // Use Application Support directory for data that shouldn't be exposed to the user directly
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths.first!
        let bundleID = Bundle.main.bundleIdentifier ?? "StepsTrader"
        return appSupport.appendingPathComponent(bundleID, isDirectory: true)
    }
    
    private var storageDirectory: URL {
        Self.storageDirectory
    }
    
    func save<T: Encodable>(_ object: T, to filename: String) async throws {
        let url = storageDirectory.appendingPathComponent(filename)
        do {
            let data = try JSONEncoder().encode(object)
            try data.write(to: url, options: .atomic)
        } catch {
            await ErrorManager.shared.handle(AppError.persistenceError(error))
            throw error
        }
    }
    
    func load<T: Decodable>(_ type: T.Type, from filename: String) async throws -> T {
        let url = storageDirectory.appendingPathComponent(filename)
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
        let url = storageDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: url)
    }
    
    func exists(_ filename: String) -> Bool {
        let url = storageDirectory.appendingPathComponent(filename)
        return fileManager.fileExists(atPath: url.path)
    }
}
