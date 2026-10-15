import Foundation
import OSLog

final class BlockService: NSObject, OneWayServiceProtocol, NSXPCListenerDelegate {
    private let queue = DispatchQueue(label: "OneWay.enforcement")
    private let logger = Logger(subsystem: OneWayConfig.serviceID, category: "service")
    private let stateURL = OneWayConfig.stateDirectory.appendingPathComponent("block-list.json")
    private let hosts = HostsEnforcer(hostsURL: URL(fileURLWithPath: "/private/etc/hosts"),
        backupURL: OneWayConfig.stateDirectory.appendingPathComponent("hosts-before-oneway"), flushDNS: true)
    private let apps = AppEnforcer()
    private let sessionURL = OneWayConfig.stateDirectory.appendingPathComponent("daily-access.json")
    private var session = AccessSession()
    private var sessionLoaded = false
    private var browserCloseUntil: Date?
    private let browserEnforcer = AppEnforcer()
    // These browser processes must exit so existing connections do not survive re-blocking.
    private let browsers = ["com.apple.Safari", "com.google.Chrome", "com.google.Chrome.beta",
        "com.google.Chrome.canary", "org.chromium.Chromium", "org.mozilla.firefox", "org.mozilla.nightly",
        "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser", "com.duckduckgo.macos.browser", "app.zen-browser.zen"]
        .map { BlockedApplication(bundleID: $0, name: $0, path: "/__oneway_browser_id_only__/" + $0 + ".app") }
    private var list = MacBlockList()
    private var loaded = false
    private var issue: String?
    private var timer: DispatchSourceTimer?
    private var tick = 0

    override init() {
        super.init()
        queue.sync {
            do {
                let directory = OneWayConfig.stateDirectory
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
                guard attributes[.type] as? FileAttributeType == .typeDirectory,
                      (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == 0 else {
                    throw MacFailure.message("OneWay's service data directory must be owned by the system administrator.")
                }
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
                list = try StateFile.load(stateURL)
                loaded = true
                do {
                    if FileManager.default.fileExists(atPath: sessionURL.path) {
                        session = try JSONDecoder().decode(AccessSession.self, from: Data(contentsOf: sessionURL))
                        try session.validate()
                    }
                    session.migratePausableAccounting()
                    session.budget.advance(to: Date())
                    try saveSession(session)
                    sessionLoaded = true
                } catch { issue = "Daily access is unavailable: " + error.localizedDescription }
                applyHosts()
            } catch { issue = error.localizedDescription }
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(500), leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self, self.loaded else { return }
            self.enforceSession()
            self.tick += 1
            if self.tick % 6 == 0 { self.applyHosts() }
        }
        self.timer = timer
        timer.resume()
    }

    private var accessActive: Bool { sessionLoaded && session.isActive() }
    private func saveSession(_ next: AccessSession) throws {
        try next.validate()
        try AtomicFile.write(JSONEncoder().encode(next), to: sessionURL, attributes: [.posixPermissions: 0o600])
        session = next
    }
    private func enforceSession() {
        if !accessActive {
            if sessionLoaded && (session.endsAt != nil || session.budget.calendar.startOfDay(for: Date()) > session.budget.dayStart) {
                var next = session
                next.end()
                next.budget.advance(to: Date())
                do { try saveSession(next) } catch { sessionLoaded = false; issue = error.localizedDescription }
                applyHosts()
            }
            apps.enforce(list.applications)
            if session.pendingBrowserClose {
                // Keep the pending flag across helper restarts until the sweep is complete.
                if browserCloseUntil == nil { browserCloseUntil = Date().addingTimeInterval(3) }
                browserEnforcer.enforce(browsers)
                if Date() >= browserCloseUntil! {
                    var next = session; next.pendingBrowserClose = false
                    do { try saveSession(next); browserCloseUntil = nil }
                    catch { issue = error.localizedDescription }
                }
            }
        }
    }
    private func applyHosts() {
        do {
            try hosts.apply(accessActive ? [] : list.domains)
            if sessionLoaded { issue = nil }
        }
        catch {
            let description = error.localizedDescription
            if description != issue { logger.error("Website enforcement needs attention: \(description, privacy: .public)") }
            issue = description
        }
    }

    private func respond(_ reply: @escaping (Data?, String?) -> Void) {
        do {
            let snapshot = ServiceSnapshot(list: list, ready: loaded && issue == nil, issue: issue, version: "1.3",
                session: sessionLoaded ? session : nil, build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            reply(try JSONEncoder().encode(snapshot), nil)
        } catch { reply(nil, error.localizedDescription) }
    }

    func resumeSession(reply: @escaping (Data?, String?) -> Void) {
        queue.async {
            do {
                guard self.loaded && self.sessionLoaded && self.issue == nil && !self.list.isEmpty,
                      self.browserCloseUntil == nil else { throw MacFailure.message("Blocking must be healthy before starting access.") }
                var next = self.session
                try next.startRemaining()
                next.pendingBrowserClose = !self.list.domains.isEmpty
                try self.saveSession(next)
                self.applyHosts()
                if let issue = self.issue {
                    var closed = self.session; closed.end(); try self.saveSession(closed)
                    self.enforceSession()
                    throw MacFailure.message(issue)
                }
                self.respond(reply)
            } catch { reply(nil, error.localizedDescription) }
        }
    }
    func endSession(reply: @escaping (Data?, String?) -> Void) {
        queue.async {
            do {
                guard self.sessionLoaded else { throw MacFailure.message("Daily access state could not be read.") }
                var next = self.session; next.end()
                try self.saveSession(next)
                self.applyHosts()
                self.enforceSession()
                self.respond(reply)
            } catch { reply(nil, error.localizedDescription) }
        }
    }
    func snapshot(reply: @escaping (Data?, String?) -> Void) {
        queue.async { self.respond(reply) }
    }
    func addDomains(_ domains: [String], reply: @escaping (Data?, String?) -> Void) {
        queue.async {
            do {
                guard domains.count <= 500 else { throw MacFailure.message("Add at most 500 website names at a time.") }
                let normalized = try Set(domains.map { try MacDomain.validated($0) })
                try self.persist(self.list.adding(domains: normalized))
                self.respond(reply)
            } catch { reply(nil, error.localizedDescription) }
        }
    }
    func addApplication(_ path: String, reply: @escaping (Data?, String?) -> Void) {
        queue.async {
            do {
                let app = try AppInspector.inspect(path)
                try self.persist(self.list.adding(application: app))
                self.respond(reply)
            } catch { reply(nil, error.localizedDescription) }
        }
    }
    private func persist(_ next: MacBlockList) throws {
        guard loaded else { throw MacFailure.message(issue ?? "The saved list could not be loaded.") }
        // Commit before enforcement. A failed save never replaces the in-memory list.
        try StateFile.save(next, to: stateURL)
        list = next
        if accessActive && !list.domains.isEmpty && !session.pendingBrowserClose {
            var updated = session; updated.pendingBrowserClose = true
            do { try saveSession(updated) }
            catch { sessionLoaded = false; issue = error.localizedDescription }
        }
        applyHosts()
        enforceSession()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(OneWayConfig.requirement(for: OneWayConfig.appID))
        connection.exportedInterface = NSXPCInterface(with: OneWayServiceProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }
}

@main
enum HelperMain {
    static func main() {
        guard getuid() == 0 else {
            fputs("OneWay's helper is launched by macOS as a system service.\n", stderr)
            exit(1)
        }
        let service = BlockService()
        let listener = NSXPCListener(machServiceName: OneWayConfig.serviceID)
        listener.setConnectionCodeSigningRequirement(OneWayConfig.requirement(for: OneWayConfig.appID))
        listener.delegate = service
        listener.resume()
        withExtendedLifetime((service, listener)) { RunLoop.main.run() }
    }
}
