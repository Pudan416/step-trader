import CryptoKit
import Foundation

struct SealFailure: Error, CustomStringConvertible {
    let description: String
}

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func relativeFiles(_ root: URL) throws -> [String] {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
        options: []
    ) else { throw SealFailure(description: "cannot enumerate \(root.path)") }
    var files: [String] = []
    for case let url as URL in enumerator {
        let relative = String(url.path.dropFirst(root.path.count + 1))
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        if components.contains(where: { $0.hasPrefix(".") }) {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                enumerator.skipDescendants()
            }
            continue
        }
        if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            files.append(relative)
        }
    }
    return files.sorted()
}

func recursiveDigest(_ root: URL) throws -> (Int, String) {
    let files = try relativeFiles(root)
    var ledger = Data()
    for relative in files {
        let data = try Data(contentsOf: root.appendingPathComponent(relative))
        ledger.append(Data("\(sha256(data))  \(relative)\n".utf8))
    }
    return (files.count, sha256(ledger))
}

do {
    guard CommandLine.arguments.count == 6 else {
        throw SealFailure(description: "usage: seal-guard.swift <s1c> <s1r> <s3c> <s3r> <baseline>")
    }
    let labels = ["scale1-candidate", "scale1-rerender", "scale3-candidate", "scale3-rerender", "baseline-scale1"]
    let expected = [
        "35d5f7e2b640e010b9e0726237801bc26135b39aff1479a2dd06cd8bf29656c0",
        "35d5f7e2b640e010b9e0726237801bc26135b39aff1479a2dd06cd8bf29656c0",
        "fc20e175697d53e0ccdb113db3ebb778c5d3d8e25f047ccdffe34f453228fd4b",
        "fc20e175697d53e0ccdb113db3ebb778c5d3d8e25f047ccdffe34f453228fd4b",
    ]
    for index in 0..<5 {
        let root = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        let (count, digest) = try recursiveDigest(root)
        guard count == 261 else { throw SealFailure(description: "\(labels[index]) file count \(count)") }
        if index < 4 && digest != expected[index] {
            throw SealFailure(description: "\(labels[index]) accepted seal differs")
        }
        print("SEAL label=\(labels[index]) file_count=\(count) recursive_sha256=\(digest)")
    }
    print("SEAL_GUARD: PASS")
} catch {
    fputs("SEAL_GUARD: FAIL\n\(error)\n", stderr)
    exit(1)
}
