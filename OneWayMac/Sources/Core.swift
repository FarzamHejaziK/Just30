import Foundation
import Darwin

enum MacFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum OneWayConfig {
    #if ONEWAY_CONFIGURED_BUILD
    static let appID = OneWayBuildIdentity.appID
    static let teamID = OneWayBuildIdentity.teamID
    #else
    // Test targets cannot authenticate as an installed, signed OneWay client.
    static let appID = "dev.oneway.mac"
    static let teamID = "UNCONFIGURED"
    #endif
    static let serviceID = appID + ".helper"
    static let daemonPlist = serviceID + ".plist"
    static let stateDirectory = URL(fileURLWithPath: "/Library/Application Support/OneWayMac", isDirectory: true)
    static func requirement(for identifier: String) -> String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and identifier \"\(identifier)\""
    }
}

struct BlockedApplication: Codable, Hashable, Identifiable {
    let bundleID: String
    let name: String
    let path: String
    var id: String { bundleID }
}

struct MacBlockList: Codable, Equatable {
    var version = 1
    private(set) var applications: [BlockedApplication] = []
    private(set) var domains: Set<String> = []
    var isEmpty: Bool { applications.isEmpty && domains.isEmpty }

    func adding(application: BlockedApplication? = nil, domains additions: Set<String> = []) throws -> Self {
        var next = self
        if let application, !next.applications.contains(where: { $0.bundleID == application.bundleID }) {
            next.applications.append(application)
            next.applications.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        for domain in additions { _ = try MacDomain.validated(domain) }
        next.domains.formUnion(additions)
        try next.validate()
        return next
    }

    func validate() throws {
        guard version == 1, applications.count <= 500, domains.count <= 10_000 else {
            throw MacFailure.message("The saved list has an unsupported version or is too large. Existing blocks were left in place.")
        }
        guard Set(applications.map(\.bundleID)).count == applications.count else {
            throw MacFailure.message("The saved app list contains duplicate identities.")
        }
        for app in applications {
            guard !app.bundleID.isEmpty, !app.name.isEmpty, app.path.hasPrefix("/"),
                  !AppInspector.protectedIDs.contains(app.bundleID) else {
                throw MacFailure.message("The saved app list contains an invalid or protected app.")
            }
        }
        for domain in domains where try MacDomain.validated(domain) != domain {
            throw MacFailure.message("The saved list contains an invalid website.")
        }
    }
}

enum MacDomain {
    static func validated(_ value: String) throws -> String {
        let domain = try DomainParser.normalize(value)
        guard !domain.hasSuffix(".local"), !domain.hasSuffix(".localhost"),
              domain.split(separator: ".").last?.contains(where: { $0.isLetter }) == true else {
            throw MacFailure.message("Enter a public website domain, such as example.com.")
        }
        return domain
    }

    static func expanded(_ site: WebsiteSuggestion) -> Set<String> {
        var domains = site.domains
        // Hosts rules match exact names. These extra names are shown before saving.
        let common: [String: Set<String>] = [
            "youtube.com": ["m.youtube.com", "music.youtube.com"],
            "reddit.com": ["old.reddit.com", "new.reddit.com", "m.reddit.com"],
            "facebook.com": ["m.facebook.com", "web.facebook.com"],
            "x.com": ["mobile.twitter.com"],
            "discord.com": ["canary.discord.com", "ptb.discord.com"],
            "tiktok.com": ["m.tiktok.com"]
        ]
        domains.formUnion(common[site.domain] ?? [])
        for domain in site.domains where !domain.hasPrefix("www.") { domains.insert("www." + domain) }
        return domains
    }
}

enum AppInspector {
    // Keep system recovery and the tools used to maintain OneWay available.
    static let protectedIDs: Set<String> = [OneWayConfig.appID, "com.apple.finder", "com.apple.systempreferences",
        "com.apple.loginwindow", "com.apple.dock", "com.apple.SystemUIServer", "com.apple.Terminal",
        "com.apple.dt.Xcode", "com.openai.codex", "com.openai.chat", "com.googlecode.iterm2"]

    static func inspect(_ path: String) throws -> BlockedApplication {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard url.pathExtension == "app", let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier, !identifier.isEmpty,
              let executable = bundle.executableURL, FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw MacFailure.message("Choose an installed Mac application (.app).")
        }
        guard !protectedIDs.contains(identifier), !url.path.hasPrefix("/System/Library/"),
              !url.path.hasPrefix("/Library/Apple/"), !url.path.hasPrefix("/System/Applications/Utilities/") else {
            throw MacFailure.message("This app is kept available for system access and maintaining OneWay.")
        }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return BlockedApplication(bundleID: identifier, name: name, path: url.path)
    }

    static func bundlePaths(containing executablePath: String) -> [String] {
        var result: [String] = []
        var cursor = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
        while cursor.path != "/" {
            if cursor.pathExtension == "app" { result.append(cursor.path) }
            cursor.deleteLastPathComponent()
        }
        return result
    }
}

enum HostsRules {
    static let start = "# BEGIN ONEWAY MAC — managed block list"
    static let end = "# END ONEWAY MAC"

    static func merging(_ original: String, domains: Set<String>) throws -> String {
        for domain in domains where try MacDomain.validated(domain) != domain {
            throw MacFailure.message("A domain was not normalized. No hosts rules were changed.")
        }
        let starts = original.components(separatedBy: start).count - 1
        let ends = original.components(separatedBy: end).count - 1
        guard (starts == 0 && ends == 0) || (starts == 1 && ends == 1) else {
            throw MacFailure.message("OneWay's hosts section is damaged. Other network settings were left untouched.")
        }
        let block = ([start] + domains.sorted().flatMap { ["0.0.0.0\t\($0)", "::1\t\($0)"] } + [end]).joined(separator: "\n")
        if let first = original.range(of: start), let last = original.range(of: end) {
            guard first.lowerBound < last.lowerBound else {
                throw MacFailure.message("OneWay's hosts section is out of order.")
            }
            // Only our marked section is replaced; every other byte is preserved.
            return String(original[..<first.lowerBound]) + block + String(original[last.upperBound...])
        }
        guard !domains.isEmpty else { return original }
        return original + (original.hasSuffix("\n") ? "\n" : "\n\n") + block + "\n"
    }
}

struct ServiceSnapshot: Codable {
    let list: MacBlockList
    let ready: Bool
    let issue: String?
    let version: String
    var session: AccessSession? = nil
    var build: String? = nil
}

enum StateFile {
    static func load(_ url: URL) throws -> MacBlockList {
        guard FileManager.default.fileExists(atPath: url.path) else { return MacBlockList() }
        let list = try JSONDecoder().decode(MacBlockList.self, from: Data(contentsOf: url))
        try list.validate()
        return list
    }
    static func save(_ list: MacBlockList, to url: URL) throws {
        try list.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AtomicFile.write(encoder.encode(list), to: url, attributes: [.posixPermissions: 0o600])
    }
}

enum AtomicFile {
    static func write(_ data: Data, to url: URL, attributes: [FileAttributeKey: Any]) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".oneway-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        try FileManager.default.setAttributes(attributes, ofItemAtPath: temporary.path)
        let handle = try FileHandle(forWritingTo: temporary)
        do { try handle.synchronize(); try handle.close() }
        catch { try? handle.close(); throw error }
        guard rename(temporary.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
