import Foundation

/// Local account archives. The caller must stop all working-set writers,
/// including extensions, before activation; this type does not suspend them.
/// Credentials are excluded. Unattributed history is never assigned to a user.
final class AccountHistoryVault {
    struct DefaultsDomain {
        let defaults: UserDefaults
        let keys: Set<String>
    }

    struct Location {
        let name: String
        let url: URL
        var isDirectory: Bool = false
    }

    enum VaultError: Error {
        case invalidArchive, invalidLocation, invalidOwner, defaultsWriteFailed
    }

    static let legacyOwner = "legacy-unattributed"
    private let root: URL
    private let domains: [DefaultsDomain]
    private let locations: [Location]
    private let fm: FileManager
    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()

    private struct Contents: Codable {
        let version: Int
        let defaults: [Data]
        let files: [String]
    }

    private struct Reference: Codable { let directoryID: String }

    private struct Snapshot {
        let contents: Contents
        let directory: URL
        var fileRoot: URL { directory.appendingPathComponent("files") }
    }

    private struct Manifest: Codable {
        var owner: String
        // A process interruption during replacement recovers the outgoing
        // archive before any reader or writer can resume using the working set.
        var recoveringOwner: String?
    }

    init(root: URL, domains: [DefaultsDomain], locations: [Location], fileManager: FileManager = .default) throws {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let paths = locations.map { $0.url.resolvingSymlinksInPath().standardizedFileURL.path }
        guard Set(locations.map(\.name)).count == locations.count,
              locations.allSatisfy({ !$0.name.isEmpty && !$0.name.contains("/") && $0.name != "." && $0.name != ".." }),
              paths.allSatisfy({ !Self.overlaps(rootPath, $0) }),
              paths.enumerated().allSatisfy({ index, path in
                  !paths.enumerated().contains(where: { other, candidate in
                      other != index && Self.overlaps(path, candidate)
                  })
              }) else { throw VaultError.invalidLocation }
        if (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw VaultError.invalidLocation }
        self.root = root
        self.domains = domains
        self.locations = locations
        self.fm = fileManager
        encoder.outputFormat = .binary
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try protectArchive(root)
        try recoverInterruptedSwitch()
    }

    var activeOwner: String {
        get throws { try manifest().owner }
    }

    /// Copies files individually: memory use does not grow with PNG history.
    /// The outgoing archive is durable before any working data is replaced.
    /// New users start empty; returning users retain their exact UUID/file bytes.
    func activate(owner: String) throws {
        guard !owner.isEmpty, owner != Self.legacyOwner else { throw VaultError.invalidOwner }
        try recoverInterruptedSwitch()
        let previous = try manifest().owner
        guard previous != owner else { return }
        let outgoing = try capture()
        try publish(outgoing, owner: previous)
        let saved = try read(owner: owner)
        let incoming = try saved ?? emptySnapshot()
        defer { if saved == nil { try? fm.removeItem(at: incoming.directory) } }
        try validate(incoming)
        try writeManifest(Manifest(owner: previous, recoveringOwner: previous))
        do {
            try apply(incoming)
            try writeManifest(Manifest(owner: owner, recoveringOwner: nil))
        } catch {
            // Leave the marker if rollback fails too: a later launch retries
            // from the outgoing archive rather than trusting partial files.
            try apply(outgoing)
            try writeManifest(Manifest(owner: previous, recoveringOwner: nil))
            throw error
        }
    }

    /// Archives include legacy-unattributed and remain entirely local.
    func containsArchive(owner: String) -> Bool {
        fm.fileExists(atPath: pointerURL(owner: owner).path)
    }

    private static func overlaps(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || lhs.hasPrefix(rhs + "/") || rhs.hasPrefix(lhs + "/")
    }

    private func manifest() throws -> Manifest {
        let url = root.appendingPathComponent("manifest.plist")
        guard fm.fileExists(atPath: url.path) else {
            return Manifest(owner: Self.legacyOwner, recoveringOwner: nil)
        }
        return try decoder.decode(Manifest.self, from: Data(contentsOf: url))
    }

    private func writeManifest(_ value: Manifest) throws {
        try writeArchiveData(encoder.encode(value), to: root.appendingPathComponent("manifest.plist"))
    }

    private func pointerURL(owner: String) -> URL {
        let component = owner.utf8.map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(component + ".plist")
    }

    private func read(owner: String) throws -> Snapshot? {
        let pointer = pointerURL(owner: owner)
        guard fm.fileExists(atPath: pointer.path) else { return nil }
        let id = try decoder.decode(Reference.self, from: Data(contentsOf: pointer)).directoryID
        guard UUID(uuidString: id) != nil else { throw VaultError.invalidArchive }
        let directory = root.appendingPathComponent(id)
        let contents = try decoder.decode(Contents.self, from: Data(contentsOf: directory.appendingPathComponent("contents.plist")))
        return Snapshot(contents: contents, directory: directory)
    }

    private func publish(_ snapshot: Snapshot, owner: String) throws {
        let old = try read(owner: owner)
        try writeArchiveData(encoder.encode(Reference(directoryID: snapshot.directory.lastPathComponent)), to: pointerURL(owner: owner))
        // An interrupted cleanup can leave an unreferenced archive, never a
        // pointer to an incomplete one. Keep the current snapshot untouched.
        if let old, old.directory != snapshot.directory { try? fm.removeItem(at: old.directory) }
    }

    private func createSnapshot(defaults: [Data], files: [String], directory: URL) throws -> Snapshot {
        let contents = Contents(version: 1, defaults: defaults, files: files)
        try writeArchiveData(encoder.encode(contents), to: directory.appendingPathComponent("contents.plist"))
        return Snapshot(contents: contents, directory: directory)
    }

    private func newDirectory() throws -> URL {
        let directory = root.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory.appendingPathComponent("files"), withIntermediateDirectories: true)
        try protectArchive(directory)
        return directory
    }

    private func emptySnapshot() throws -> Snapshot {
        let empty = try PropertyListSerialization.data(fromPropertyList: [String: Any](), format: .binary, options: 0)
        return try createSnapshot(defaults: domains.map { _ in empty }, files: [], directory: newDirectory())
    }

    private func capture() throws -> Snapshot {
        let values = try domains.map { domain in
            var selected: [String: Any] = [:]
            for key in domain.keys { selected[key] = domain.defaults.object(forKey: key) }
            return try PropertyListSerialization.data(fromPropertyList: selected, format: .binary, options: 0)
        }
        let directory = try newDirectory()
        do {
            var files: [String] = []
            for location in locations where fm.fileExists(atPath: location.url.path) {
                let kind = try location.url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard kind.isSymbolicLink != true, kind.isDirectory == location.isDirectory else { throw VaultError.invalidArchive }
                var sources: [URL] = []
                if location.isDirectory {
                    var enumerationError: Error?
                    guard let enumerator = fm.enumerator(at: location.url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], errorHandler: { _, error in
                        enumerationError = error
                        return false
                    }) else { throw VaultError.invalidArchive }
                    for case let url as URL in enumerator { sources.append(url) }
                    if let enumerationError { throw enumerationError }
                } else { sources = [location.url] }
                for url in sources {
                    let kind = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
                    guard kind.isSymbolicLink != true else { throw VaultError.invalidArchive }
                    if kind.isDirectory == true { continue }
                    guard kind.isRegularFile == true else { throw VaultError.invalidArchive }
                    let base = location.url.resolvingSymlinksInPath().path + "/"
                    let path = url.resolvingSymlinksInPath().path
                    guard !location.isDirectory || path.hasPrefix(base) else { throw VaultError.invalidArchive }
                    let relative = location.isDirectory ? location.name + "/" + String(path.dropFirst(base.count)) : location.name
                    let target = directory.appendingPathComponent("files").appendingPathComponent(relative)
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: url, to: target)
                    try protectArchive(target)
                    files.append(relative)
                }
            }
            return try createSnapshot(defaults: values, files: files, directory: directory)
        } catch {
            try? fm.removeItem(at: directory)
            throw error
        }
    }

    private func validate(_ snapshot: Snapshot) throws {
        let directoryKind = try snapshot.directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directoryKind.isDirectory == true, directoryKind.isSymbolicLink != true,
              snapshot.directory.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { throw VaultError.invalidArchive }
        let contents = snapshot.contents
        guard contents.version == 1, contents.defaults.count == domains.count,
              Set(contents.files).count == contents.files.count else { throw VaultError.invalidArchive }
        for (index, data) in contents.defaults.enumerated() {
            guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  Set(values.keys).isSubset(of: domains[index].keys) else { throw VaultError.invalidArchive }
        }
        for path in contents.files {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  let location = locations.first(where: { $0.name == parts.first.map(String.init) }),
                  location.isDirectory ? parts.count > 1 : parts.count == 1 else { throw VaultError.invalidArchive }
            let source = snapshot.fileRoot.appendingPathComponent(path)
            let kind = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard kind.isRegularFile == true, kind.isSymbolicLink != true,
                  source.resolvingSymlinksInPath().path.hasPrefix(snapshot.fileRoot.resolvingSymlinksInPath().path + "/") else { throw VaultError.invalidArchive }
        }
    }

    private func apply(_ snapshot: Snapshot) throws {
        try validate(snapshot)
        for location in locations {
            if fm.fileExists(atPath: location.url.path) { try fm.removeItem(at: location.url) }
            if location.isDirectory { try fm.createDirectory(at: location.url, withIntermediateDirectories: true) }
            for path in snapshot.contents.files where path == location.name || path.hasPrefix(location.name + "/") {
                let relative = String(path.dropFirst(location.name.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let destination = relative.isEmpty ? location.url : location.url.appendingPathComponent(relative)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: snapshot.fileRoot.appendingPathComponent(path), to: destination)
                // Working files serve background widgets/Screen Time. Do not
                // inherit the stricter, unlocked-only archive protection.
                #if os(iOS)
                try fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
                #endif
            }
        }
        for (index, domain) in domains.enumerated() {
            guard let values = try PropertyListSerialization.propertyList(from: snapshot.contents.defaults[index], format: nil) as? [String: Any] else { throw VaultError.invalidArchive }
            for key in domain.keys { domain.defaults.set(values[key], forKey: key) }
            guard domain.defaults.synchronize() else { throw VaultError.defaultsWriteFailed }
        }
    }

    private func writeArchiveData(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    private func protectArchive(_ url: URL) throws {
        #if os(iOS)
        try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        #endif
    }

    private func recoverInterruptedSwitch() throws {
        let state = try manifest()
        guard let owner = state.recoveringOwner else { return }
        guard let saved = try read(owner: owner) else { throw VaultError.invalidArchive }
        try apply(saved)
        try writeManifest(Manifest(owner: owner, recoveringOwner: nil))
    }
}
