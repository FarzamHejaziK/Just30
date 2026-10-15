import Foundation
import Darwin

final class HostsEnforcer {
    let hostsURL: URL
    let backupURL: URL
    private var lastBytes: Data?
    private var lastDomains: Set<String>?
    let flushDNS: Bool
    init(hostsURL: URL, backupURL: URL, flushDNS: Bool) {
        self.hostsURL = hostsURL
        self.backupURL = backupURL
        self.flushDNS = flushDNS
    }

    func apply(_ domains: Set<String>) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: hostsURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw MacFailure.message("The hosts file is not a regular file. No network settings were changed.")
        }
        let bytes = try Data(contentsOf: hostsURL)
        if bytes == lastBytes && domains == lastDomains { return }
        guard let original = String(data: bytes, encoding: .utf8) else {
            throw MacFailure.message("The hosts file could not be read as text.")
        }
        let updated = try HostsRules.merging(original, domains: domains)
        guard updated != original else { lastBytes = bytes; lastDomains = domains; return }
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            try bytes.write(to: backupURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        }
        // Detect edits by other tools before replacing our section.
        guard try Data(contentsOf: hostsURL) == bytes else {
            throw MacFailure.message("Another tool changed the hosts file. OneWay will retry shortly.")
        }
        try AtomicFile.write(Data(updated.utf8), to: hostsURL, attributes: [
            .posixPermissions: attributes[.posixPermissions] ?? 0o644,
            .ownerAccountID: attributes[.ownerAccountID] ?? getuid(),
            .groupOwnerAccountID: attributes[.groupOwnerAccountID] ?? getgid()
        ])
        lastBytes = Data(updated.utf8)
        lastDomains = domains
        if flushDNS {
            for (command, arguments) in [("/usr/bin/dscacheutil", ["-flushcache"]), ("/usr/bin/killall", ["-HUP", "mDNSResponder"])] {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = arguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                if (try? process.run()) != nil { process.waitUntilExit() }
            }
        }
    }
}

struct ProcessIdentity: Equatable {
    let pid: Int32
    let startSeconds: UInt64
    let startMicros: UInt64
    let path: String
}

final class AppEnforcer {
    private var signaled: [Int32: (ProcessIdentity, Date)] = [:]
    private var bundleIDs: [String: Set<String>] = [:]

    static func identity(_ pid: Int32) -> ProcessIdentity? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_uid >= 501 else { return nil }
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return ProcessIdentity(pid: pid, startSeconds: info.pbi_start_tvsec,
                               startMicros: info.pbi_start_tvusec, path: String(cString: buffer))
    }

    func enforce(_ applications: [BlockedApplication]) {
        guard !applications.isEmpty else { return }
        let ids = Set(applications.map(\.bundleID))
        let paths = Set(applications.map(\.path))
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return }
        var pids = [Int32](repeating: 0, count: Int(estimate) + 128)
        let byteCount = Int32(pids.count * MemoryLayout<Int32>.stride)
        let actual = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, byteCount) }
        guard actual > 0 else { return }
        var active: Set<Int32> = []
        for pid in pids.prefix(min(Int(actual), pids.count)) where pid > 1 && pid != getpid() {
            guard let identity = Self.identity(pid), !identity.path.hasPrefix("/System/Library/") else { continue }
            let parents = AppInspector.bundlePaths(containing: identity.path)
            guard !parents.isEmpty else { continue }
            let knownIDs: Set<String>
            if let cached = bundleIDs[identity.path] { knownIDs = cached }
            else {
                knownIDs = Set(parents.compactMap { Bundle(path: $0)?.bundleIdentifier })
                bundleIDs[identity.path] = knownIDs
            }
            guard knownIDs.isDisjoint(with: AppInspector.protectedIDs),
                  !ids.isDisjoint(with: knownIDs) || !paths.isDisjoint(with: parents) else { continue }
            active.insert(pid)
            if let previous = signaled[pid], previous.0 == identity {
                if Date().timeIntervalSince(previous.1) > 1, Self.identity(pid) == identity { kill(pid, SIGKILL) }
            } else if Self.identity(pid) == identity {
                kill(pid, SIGTERM)
                signaled[pid] = (identity, Date())
            }
        }
        signaled = signaled.filter { active.contains($0.key) }
        if bundleIDs.count > 4_000 { bundleIDs.removeAll() }
    }
}
