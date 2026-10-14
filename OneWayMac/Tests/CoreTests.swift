import Foundation
import Darwin

private var checks = 0
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw MacFailure.message("FAIL: " + message) }
    checks += 1
}
func rejects(_ message: String, _ body: () throws -> Void) throws {
    do { try body() } catch { checks += 1; return }
    throw MacFailure.message("FAIL: expected rejection: " + message)
}

@main enum CoreTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OneWay-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sample = BlockedApplication(bundleID: "com.example.test", name: "Test", path: "/Applications/Test.app")
        let first = try MacBlockList().adding(application: sample, domains: ["example.com"])
        let second = try first.adding(domains: ["another.example", "example.com"])
        try check(second.domains == ["example.com", "another.example"], "additions union with existing domains")
        try check(second.applications == [sample], "website additions preserve app blocks")
        try check(try second.adding() == second, "empty additions cannot remove anything")
        try check(try second.adding(application: sample) == second, "app additions are idempotent")
        let file = directory.appendingPathComponent("list.json")
        try StateFile.save(second, to: file)
        try check(try StateFile.load(file) == second, "list survives disk reload")
        try check((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600, "private state file mode")
        try rejects("save failure") { try StateFile.save(first, to: directory.appendingPathComponent("missing/list.json")) }
        try check(try StateFile.load(file) == second, "failed save leaves previous file intact")
        try Data("broken".utf8).write(to: file)
        try rejects("corrupt state must not become an empty list") { _ = try StateFile.load(file) }
        try rejects("unsupported schema") {
            var wrong = first; wrong.version = 3; try wrong.validate()
        }

        try check(try MacDomain.validated("https://EXAMPLE.com/path?q=hello") == "example.com", "URL normalization")
        for invalid in ["localhost", "127.0.0.1", "printer.local", "example.com\n127.0.0.1 victim.com", "https://user:secret@example.com", "example.com:443"] {
            try rejects(invalid) { _ = try MacDomain.validated(invalid) }
        }
        try check(WebsiteCatalog.matches("you").contains { $0.domain == "youtube.com" }, "local name autocomplete")
        try check(WebsiteCatalog.matches("https://reddit.com/r/swift").contains { $0.domain == "reddit.com" }, "URL suggestions")
        let reddit = WebsiteCatalog.candidate("reddit.com")!
        try check(MacDomain.expanded(reddit).isSuperset(of: ["reddit.com", "www.reddit.com", "old.reddit.com", "redd.it"]), "aliases are expanded explicitly")
        try check(WebsiteCatalog.candidate("reddit.com.evil.example")?.domain == "reddit.com.evil.example", "suffix lookalikes remain separate")

        let original = "# User rules\n127.0.0.1 localhost\n0.0.0.0 existing.example\n# user comment\n"
        try check(try HostsRules.merging(original, domains: []) == original, "empty list never changes existing hosts")
        let withRules = try HostsRules.merging(original, domains: first.domains)
        try check(withRules.hasPrefix(original), "existing hosts content preserved exactly")
        try check(withRules.contains("0.0.0.0\texample.com") && withRules.contains("::1\texample.com"), "IPv4 and IPv6 covered")
        let withExternalSuffix = withRules + "0.0.0.0 external-change.example\n"
        let updated = try HostsRules.merging(withExternalSuffix, domains: second.domains)
        try check(updated.hasPrefix(original) && updated.hasSuffix("0.0.0.0 external-change.example\n"), "later unrelated edits preserved")
        try check(try HostsRules.merging(updated, domains: second.domains) == updated, "host enforcement is idempotent")
        try rejects("malformed markers") { _ = try HostsRules.merging(original + HostsRules.start, domains: first.domains) }
        try rejects("reversed markers") { _ = try HostsRules.merging(HostsRules.end + "\n" + HostsRules.start, domains: first.domains) }

        let hostsURL = directory.appendingPathComponent("hosts")
        let backupURL = directory.appendingPathComponent("backup")
        try Data(original.utf8).write(to: hostsURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: hostsURL.path)
        let enforcer = HostsEnforcer(hostsURL: hostsURL, backupURL: backupURL, flushDNS: false)
        try enforcer.apply(first.domains)
        try check(try String(contentsOf: backupURL, encoding: .utf8) == original, "first-write backup")
        try enforcer.apply(second.domains)
        try check(try String(contentsOf: backupURL, encoding: .utf8) == original, "backup never overwritten")
        try check((try FileManager.default.attributesOfItem(atPath: hostsURL.path)[.posixPermissions] as? NSNumber)?.intValue == 0o644, "host permissions preserved")
        let bad = original + HostsRules.start
        try Data(bad.utf8).write(to: hostsURL)
        try rejects("bad hosts never overwritten") { try enforcer.apply(first.domains) }
        try check(try String(contentsOf: hostsURL, encoding: .utf8) == bad, "corrupt managed section preserved for repair")
        let link = directory.appendingPathComponent("hosts-symlink")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: hostsURL)
        try rejects("symlink hosts target") { try HostsEnforcer(hostsURL: link, backupURL: backupURL, flushDNS: false).apply(first.domains) }

        try rejects("protected system app") { _ = try AppInspector.inspect("/System/Applications/Utilities/Terminal.app") }
        try check(AppInspector.bundlePaths(containing: "/Applications/Outer.app/Contents/Frameworks/Inner.app/Contents/MacOS/Inner") == ["/Applications/Outer.app/Contents/Frameworks/Inner.app", "/Applications/Outer.app"], "nested helper belongs to outer app")

        // The only process terminated by this test is our own disposable fixture.
        if CommandLine.arguments.count == 2 {
            let fixture = try AppInspector.inspect(CommandLine.arguments[1])
            let executable = Bundle(path: fixture.path)!.executableURL!
            let unrelated = Process()
            unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep")
            unrelated.arguments = ["20"]
            try unrelated.run()
            defer { if unrelated.isRunning { unrelated.terminate() } }
            let watcher = AppEnforcer()
            for _ in 0..<2 {
                let process = Process()
                process.executableURL = executable
                try process.run()
                defer { if process.isRunning { process.terminate() } }
                Thread.sleep(forTimeInterval: 0.1)
                try check(AppEnforcer.identity(process.processIdentifier) != nil, "fixture process detected")
                let deadline = Date().addingTimeInterval(3)
                repeat {
                    watcher.enforce([fixture])
                    Thread.sleep(forTimeInterval: 0.1)
                } while process.isRunning && Date() < deadline
                try check(!process.isRunning, "blocked app closes, including on relaunch")
            }
            try check(unrelated.isRunning, "unrelated processes remain running")
        }
        print("PASS: \(checks) checks. Tests used temporary files and a disposable app only.")
    }
}
