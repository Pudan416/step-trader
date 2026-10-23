import Foundation

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { fatalError(message) }
}

final class FailingFileManager: FileManager, @unchecked Sendable {
    var failNextRemoval = false
    override func removeItem(at URL: URL) throws {
        if failNextRemoval {
            failNextRemoval = false
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.removeItem(at: URL)
    }
}

@main
struct AccountHistoryVaultHarness {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "AccountHistoryVaultTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let working = root.appendingPathComponent("working")
        let archive = root.appendingPathComponent("archive")
        let canvas = working.appendingPathComponent("canvas/day.json")
        let historyBytes = Data("{\"id\":\"78080F10-36BB-4770-937C-39FE67D5EA9C\"}".utf8)
        try FileManager.default.createDirectory(at: canvas.deletingLastPathComponent(), withIntermediateDirectories: true)
        try historyBytes.write(to: canvas)
        defaults.set(historyBytes, forKey: "history")
        defaults.set("device-preference", forKey: "device")
        let fileManager = FailingFileManager()
        func makeVault() throws -> AccountHistoryVault {
            try AccountHistoryVault(root: archive,
                domains: [.init(defaults: defaults, keys: ["history", "restoreCompleted", "queue"], keyPrefixes: ["group_"])],
                locations: [.init(name: "canvases", url: canvas.deletingLastPathComponent(), isDirectory: true)], fileManager: fileManager)
        }
        let vault = try makeVault()
        let mode = CommandLine.arguments[1]
        if mode == "preparedLegacyRollback" {
            let receipt = try vault.prepareActivation(owner: "account-B")!
            try expect(defaults.data(forKey: "history") == nil, "B preparation must isolate legacy bytes")
            // The auth generation changed while asynchronous model reload ran.
            // Reject its commit and undo only this actual prepared transaction.
            try vault.rollbackActivation(receipt)
            try expect(vault.activeOwner == AccountHistoryVault.legacyOwner, "rejected initial commit must restore unattributed ownership")
            try expect(defaults.data(forKey: "history") == historyBytes && Data(contentsOf: canvas) == historyBytes, "rejected initial commit must preserve exact original IDs and bytes")
            do { try vault.commitActivation(receipt); fatalError("rolled back receipt must not be reusable") } catch {}
            let retry = try vault.prepareActivation(owner: "account-B")!
            try vault.commitActivation(retry)
            try expect(vault.activeOwner == "account-B" && defaults.data(forKey: "history") == nil, "retry must publish only clean B working set")
            try expect(vault.legacyArchive()?.fileData(at: "canvases/day.json") == historyBytes, "retry must retain local legacy access")
        } else if mode == "preparedRestart" {
            _ = try vault.prepareActivation(owner: "account-B")
            let recovered = try makeVault()
            try expect(recovered.activeOwner == AccountHistoryVault.legacyOwner, "restart before auth commit must recover outgoing ownership")
            try expect(defaults.data(forKey: "history") == historyBytes && Data(contentsOf: canvas) == historyBytes, "restart must recover original legacy bytes")
        } else if mode == "legacy" {
            try vault.activate(owner: "account-A")
            try expect(vault.containsArchive(owner: AccountHistoryVault.legacyOwner), "legacy history must be preserved without assigning it to A")
            try expect(defaults.data(forKey: "history") == nil, "A must not inherit legacy IDs")
            try expect(!FileManager.default.fileExists(atPath: canvas.path), "legacy canvas must not appear under A")
            try expect(defaults.string(forKey: "device") == "device-preference", "device preference must survive")
            let legacy = try vault.legacyArchive()!
            try expect(legacy.defaults[0]["history"] as? Data == historyBytes, "quarantined defaults must remain readable locally")
            try expect(legacy.fileData(at: "canvases/day.json") == historyBytes, "quarantined Canvas bytes must remain readable locally")
            try expect(legacy.fileData(at: "canvases/../outside") == nil, "read-only archive must restrict reads to validated files")
            try expect(vault.activeOwner == "account-A", "reading legacy history must not change the active owner")
            try expect(FileManager.default.fileExists(atPath: canvas.deletingLastPathComponent().path), "empty storage directory must remain usable")
        } else if mode == "roundtrip" {
            try vault.activate(owner: "account-A")
            defaults.set(historyBytes, forKey: "history")
            defaults.set(9, forKey: "group_A")
            defaults.set(true, forKey: "restoreCompleted")
            defaults.set(Data("A queued write".utf8), forKey: "queue")
            try historyBytes.write(to: canvas)
            try vault.activate(owner: "account-B")
            try expect(defaults.data(forKey: "history") == nil && !defaults.bool(forKey: "restoreCompleted"), "B must start without A history or restore flag")
            try expect(defaults.data(forKey: "queue") == nil, "A's queued writes must not be visible to B")
            try expect(defaults.object(forKey: "group_A") == nil, "A's dynamic group keys must not be visible to B")
            defaults.set(17, forKey: "group_B")
            let b = Data("account-B history".utf8)
            defaults.set(b, forKey: "history")
            try b.write(to: canvas)
            try vault.activate(owner: "account-A")
            try expect(defaults.data(forKey: "history") == historyBytes, "A UUID bytes must survive a switch")
            try expect(Data(contentsOf: canvas) == historyBytes, "A canvas must be restored byte for byte")
            try expect(defaults.bool(forKey: "restoreCompleted"), "restore completion must belong to A")
            try expect(defaults.integer(forKey: "group_A") == 9 && defaults.object(forKey: "group_B") == nil, "dynamic keys created after initialization must follow their account")
            try expect(defaults.data(forKey: "queue") == Data("A queued write".utf8), "A must retain its pending writes")
            try vault.activate(owner: "account-B")
            try expect(defaults.data(forKey: "history") == b && Data(contentsOf: canvas) == b, "returning to B must restore B only")
        } else if mode == "corruption" {
            try vault.activate(owner: "account-A")
            defaults.set(historyBytes, forKey: "history")
            try historyBytes.write(to: canvas)
            try vault.activate(owner: "account-B")
            let b = Data("B".utf8)
            defaults.set(b, forKey: "history")
            let aName = "account-A".utf8.map { String(format: "%02x", $0) }.joined() + ".plist"
            try Data("broken archive".utf8).write(to: archive.appendingPathComponent(aName))
            do { try vault.activate(owner: "account-A"); fatalError("corrupt archive must fail closed") } catch {}
            try expect(vault.activeOwner == "account-B", "failed restore must not publish A")
            try expect(defaults.data(forKey: "history") == b, "failed restore must preserve current B")
        } else if mode == "malformedPath" {
            try vault.activate(owner: "account-A")
            defaults.set(historyBytes, forKey: "history")
            try historyBytes.write(to: canvas)
            try vault.activate(owner: "account-B")
            defaults.set(Data("B".utf8), forKey: "history")
            let aName = "account-A".utf8.map { String(format: "%02x", $0) }.joined() + ".plist"
            let pointer = try PropertyListSerialization.propertyList(from: Data(contentsOf: archive.appendingPathComponent(aName)), format: nil) as! [String: Any]
            let contentsURL = archive.appendingPathComponent(pointer["directoryID"] as! String).appendingPathComponent("contents.plist")
            let original = try PropertyListSerialization.propertyList(from: Data(contentsOf: contentsURL), format: nil) as! [String: Any]
            for badPath in ["canvases", "canvases/../outside", "canvases//day.json", "/canvases/day.json", "unknown/day.json"] {
                var contents = original
                contents["files"] = [badPath]
                let bytes = try PropertyListSerialization.data(fromPropertyList: contents, format: .binary, options: 0)
                try bytes.write(to: contentsURL)
                do { try vault.activate(owner: "account-A"); fatalError("malformed path must fail before mutation") } catch {}
                try expect(vault.activeOwner == "account-B" && defaults.data(forKey: "history") == Data("B".utf8), "malformed archive must preserve B")
            }
        } else if mode == "symlinks" {
            let outside = root.appendingPathComponent("outside.json")
            try historyBytes.write(to: outside)
            let linked = canvas.deletingLastPathComponent().appendingPathComponent("link.json")
            try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)
            do { try vault.activate(owner: "account-A"); fatalError("symlink file must be rejected") } catch {}
            try expect(vault.activeOwner == AccountHistoryVault.legacyOwner, "failed capture must not change owner")
            try expect(Data(contentsOf: outside) == historyBytes, "symlink destination must remain untouched")
            try FileManager.default.removeItem(at: linked)
            let directoryLink = root.appendingPathComponent("directory-link")
            try FileManager.default.createSymbolicLink(at: directoryLink, withDestinationURL: canvas.deletingLastPathComponent())
            let symlinkVault = try AccountHistoryVault(root: archive, domains: [], locations: [.init(name: "linked", url: directoryLink, isDirectory: true)])
            do { try symlinkVault.activate(owner: "account-A"); fatalError("symlink working directory must be rejected") } catch {}
            for unsafeRoot in [working, canvas.deletingLastPathComponent().appendingPathComponent("nested-archive")] {
                do {
                    _ = try AccountHistoryVault(root: unsafeRoot, domains: [], locations: [.init(name: "canvas", url: canvas.deletingLastPathComponent(), isDirectory: true)])
                    fatalError("overlapping roots must be rejected")
                } catch {}
            }
        } else if mode == "archiveRootSymlink" {
            try vault.activate(owner: "account-A")
            defaults.set(historyBytes, forKey: "history")
            try historyBytes.write(to: canvas)
            try vault.activate(owner: "account-B")
            let b = Data("B current bytes".utf8)
            defaults.set(b, forKey: "history")
            try b.write(to: canvas)
            let aName = "account-A".utf8.map { String(format: "%02x", $0) }.joined() + ".plist"
            let pointer = try PropertyListSerialization.propertyList(from: Data(contentsOf: archive.appendingPathComponent(aName)), format: nil) as! [String: Any]
            let files = archive.appendingPathComponent(pointer["directoryID"] as! String).appendingPathComponent("files")
            let outside = root.appendingPathComponent("unrelated-account")
            try FileManager.default.createDirectory(at: outside.appendingPathComponent("canvases"), withIntermediateDirectories: true)
            let foreign = Data("OUTSIDE-ACCOUNT".utf8)
            try foreign.write(to: outside.appendingPathComponent("canvases/day.json"))
            try FileManager.default.removeItem(at: files)
            try FileManager.default.createSymbolicLink(at: files, withDestinationURL: outside)
            do { try vault.activate(owner: "account-A"); fatalError("a redirected archive files root must fail before mutation") } catch {}
            try expect(vault.activeOwner == "account-B", "redirected archive must not publish A")
            try expect(defaults.data(forKey: "history") == b && Data(contentsOf: canvas) == b, "foreign archive bytes must not replace B")
            // Apply the same corruption to the unowned archive. The local
            // reader must reject it too rather than displaying unrelated data.
            let legacyName = AccountHistoryVault.legacyOwner.utf8.map { String(format: "%02x", $0) }.joined() + ".plist"
            let legacyPointer = try PropertyListSerialization.propertyList(from: Data(contentsOf: archive.appendingPathComponent(legacyName)), format: nil) as! [String: Any]
            let legacyFiles = archive.appendingPathComponent(legacyPointer["directoryID"] as! String).appendingPathComponent("files")
            try FileManager.default.removeItem(at: legacyFiles)
            try FileManager.default.createSymbolicLink(at: legacyFiles, withDestinationURL: outside)
            do { _ = try vault.legacyArchive(); fatalError("legacy reader must reject redirected files root") } catch {}
        } else if mode == "writeFailure" {
            try vault.activate(owner: "account-A")
            defaults.set(historyBytes, forKey: "history")
            try historyBytes.write(to: canvas)
            try vault.activate(owner: "account-B")
            let b = Data("B working copy".utf8)
            defaults.set(b, forKey: "history")
            try b.write(to: canvas)
            fileManager.failNextRemoval = true
            do { try vault.activate(owner: "account-A"); fatalError("disk error must fail the switch") } catch {}
            try expect(vault.activeOwner == "account-B", "failed write must keep the outgoing owner")
            try expect(defaults.data(forKey: "history") == b && Data(contentsOf: canvas) == b, "failed write must roll back B completely")
            try vault.activate(owner: "account-A")
            try expect(defaults.data(forKey: "history") == historyBytes && Data(contentsOf: canvas) == historyBytes, "retry must still recover A's archive")
        } else if mode == "interrupted" {
            try vault.activate(owner: "account-A")
            defaults.set(historyBytes, forKey: "history")
            try historyBytes.write(to: canvas)
            try vault.activate(owner: "account-B") // durably archives A
            let journal: [String: Any] = ["owner": "account-A", "recoveringOwner": "account-A"]
            let bytes = try PropertyListSerialization.data(fromPropertyList: journal, format: .binary, options: 0)
            try bytes.write(to: archive.appendingPathComponent("manifest.plist"), options: .atomic)
            defaults.set(Data("partial target".utf8), forKey: "history")
            try Data("partial target".utf8).write(to: canvas)
            let recovered = try makeVault()
            try expect(recovered.activeOwner == "account-A", "interrupted switch must recover the outgoing owner")
            try expect(defaults.data(forKey: "history") == historyBytes && Data(contentsOf: canvas) == historyBytes, "restart must restore A's intact archive")
        } else { fatalError("unknown test mode") }
        print("PASS " + mode)
    }
}
