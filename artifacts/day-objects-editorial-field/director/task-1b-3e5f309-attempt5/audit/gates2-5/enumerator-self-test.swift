import Foundation

struct SelfTestFailure: Error, CustomStringConvertible {
    let description: String
}

func visibleRelativeFiles(_ root: URL) throws -> [String] {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
        options: []
    ) else {
        throw SelfTestFailure(description: "cannot enumerate fixture")
    }

    var result: [String] = []
    for case let url as URL in enumerator {
        let relative = String(url.path.dropFirst(root.path.count + 1))
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        if components.contains(where: { $0.hasPrefix(".") }) {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                enumerator.skipDescendants()
            }
            continue
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        if values.isRegularFile == true { result.append(relative) }
    }
    return result.sorted()
}

do {
    guard CommandLine.arguments.count == 2 else {
        throw SelfTestFailure(description: "usage: enumerator-self-test.swift <fixture-root>")
    }
    let root = URL(fileURLWithPath: CommandLine.arguments[1])
    let hidden = try root.resourceValues(forKeys: [.isHiddenKey]).isHidden == true
    guard hidden else {
        throw SelfTestFailure(description: "fixture root does not carry hidden state")
    }
    let actual = try visibleRelativeFiles(root)
    let expected = ["nested/second.txt", "visible.txt"]
    guard actual == expected else {
        throw SelfTestFailure(description: "inventory mismatch: \(actual)")
    }
    print("ENUMERATOR_SELF_TEST: PASS")
    print("root_hidden=true")
    print("visible_inventory=\(actual.joined(separator: ","))")
    print("visible_count=2")
    print("explicit_dot_entries_excluded=2")
} catch {
    fputs("ENUMERATOR_SELF_TEST: FAIL\n\(error)\n", stderr)
    exit(1)
}
