import Foundation
import OSLog

final class BlockService: NSObject, OneWayServiceProtocol, NSXPCListenerDelegate {
    private let queue = DispatchQueue(label: "OneWay.enforcement")
    private let logger = Logger(subsystem: OneWayConfig.serviceID, category: "service")
    private let stateURL = OneWayConfig.stateDirectory.appendingPathComponent("block-list.json")
    private let hosts = HostsEnforcer(hostsURL: URL(fileURLWithPath: "/private/etc/hosts"),
        backupURL: OneWayConfig.stateDirectory.appendingPathComponent("hosts-before-oneway"), flushDNS: true)
    private let apps = AppEnforcer()
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
                applyHosts()
            } catch { issue = error.localizedDescription }
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(500), leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self, self.loaded else { return }
            self.apps.enforce(self.list.applications)
            self.tick += 1
            if self.tick % 6 == 0 { self.applyHosts() }
        }
        self.timer = timer
        timer.resume()
    }

    private func applyHosts() {
        do { try hosts.apply(list.domains); issue = nil }
        catch {
            let description = error.localizedDescription
            if description != issue { logger.error("Website enforcement needs attention: \(description, privacy: .public)") }
            issue = description
        }
    }

    private func respond(_ reply: @escaping (Data?, String?) -> Void) {
        do {
            let snapshot = ServiceSnapshot(list: list, ready: loaded && issue == nil, issue: issue, version: "1.0")
            reply(try JSONEncoder().encode(snapshot), nil)
        } catch { reply(nil, error.localizedDescription) }
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
        applyHosts()
        apps.enforce(list.applications)
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
