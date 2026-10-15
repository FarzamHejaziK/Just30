import AppKit
import Combine
import ServiceManagement

private final class ReplyOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: ((Result<Data, Error>) -> Void)?
    init(_ completion: @escaping (Result<Data, Error>) -> Void) { self.completion = completion }
    func finish(_ result: Result<Data, Error>) {
        lock.lock()
        let callback = completion
        completion = nil
        lock.unlock()
        callback?(result)
    }
}

enum ServiceClient {
    static func call(_ operation: @escaping (OneWayServiceProtocol, @escaping (Data?, String?) -> Void) -> Void) async throws -> ServiceSnapshot {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            let connection = NSXPCConnection(machServiceName: OneWayConfig.serviceID, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: OneWayServiceProtocol.self)
            connection.setCodeSigningRequirement(OneWayConfig.requirement(for: OneWayConfig.serviceID))
            let reply = ReplyOnce { result in
                continuation.resume(with: result)
                connection.invalidate()
            }
            connection.invalidationHandler = {
                reply.finish(.failure(MacFailure.message("The background service is unavailable. Check its permission in System Settings.")))
            }
            connection.resume()
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in reply.finish(.failure(error)) }
            guard let service = proxy as? OneWayServiceProtocol else {
                reply.finish(.failure(MacFailure.message("Could not connect to the background service.")))
                return
            }
            operation(service) { data, error in
                if let error { reply.finish(.failure(MacFailure.message(error))) }
                else if let data { reply.finish(.success(data)) }
                else { reply.finish(.failure(MacFailure.message("The background service returned no saved list."))) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
                reply.finish(.failure(MacFailure.message("The background service did not respond. Your saved blocks have not been removed.")))
            }
        }
        return try JSONDecoder().decode(ServiceSnapshot.self, from: data)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var list = MacBlockList()
    @Published private(set) var session: AccessSession?
    @Published private(set) var connected = false
    @Published private(set) var healthy = false
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var busy = false
    @Published private(set) var serviceIssue: String?
    @Published var error: String?
    @Published var success: String?
    @Published private(set) var installedApps: [BlockedApplication] = []
    @Published private(set) var loadingApps = false
    private let service = SMAppService.daemon(plistName: OneWayConfig.daemonPlist)
    private var refreshing = false
    private var attemptedServiceUpdate = false
    private let cacheKey = "lastKnownBlockList"

    init() {
        status = service.status
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(MacBlockList.self, from: data),
           (try? cached.validate()) != nil { list = cached }
        reloadApps()
    }
    var canAdd: Bool { connected && !busy && healthy }
    var statusTitle: String {
        if connected && healthy && session?.isActive() == true { return "Timed access is on" }
        if connected { return healthy ? (list.isEmpty ? "Ready for your first block" : "Background blocking is on") : "Blocking needs attention" }
        switch status {
        case .requiresApproval: return "Approve JustThirty in System Settings"
        case .enabled: return "Connecting to the background service"
        default: return "Set up background blocking"
        }
    }

    func setUp() async {
        busy = true
        defer { busy = false }
        attemptedServiceUpdate = false
        do {
            if service.status == .notRegistered || service.status == .notFound { try service.register() }
            status = service.status
            if status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            status = service.status
            if status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            else { self.error = error.localizedDescription }
        }
        await refresh(force: true)
    }
    func openPermissions() { SMAppService.openSystemSettingsLoginItems() }

    func refresh(force: Bool = false) async {
        guard !refreshing, !busy || force else { return }
        status = service.status
        guard status == .enabled else { connected = false; healthy = false; return }
        refreshing = true
        defer { refreshing = false }
        do {
            let snapshot = try await ServiceClient.call { $0.snapshot(reply: $1) }
            let expectedBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            if snapshot.version != "1.3" || snapshot.build != expectedBuild {
                connected = false
                healthy = false
                serviceIssue = "The background service needs an update. Choose Set up to finish updating it. Your saved list is preserved."
                if !attemptedServiceUpdate {
                    attemptedServiceUpdate = true
                    // The installed daemon keeps its old executable until re-registered.
                    // Its root-owned list and hosts rules are preserved throughout.
                    try await service.unregister()
                    try await registerUpdatedService()
                    status = service.status
                    serviceIssue = "The updated background service is starting."
                    if status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
                }
                return
            }
            accept(snapshot)
        }
        catch { connected = false; healthy = false; serviceIssue = error.localizedDescription }
    }
    private func registerUpdatedService() async throws {
        // macOS can finish unregistering after the async call returns. Retry
        // registration briefly, without changing its administrator approval.
        for attempt in 0..<3 {
            do { try service.register(); return }
            catch {
                guard attempt < 2, service.status == .notRegistered else { throw error }
                try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 500_000_000)
            }
        }
    }
    private func accept(_ snapshot: ServiceSnapshot) {
        if list != snapshot.list {
            list = snapshot.list
            if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: cacheKey) }
        }
        if session != snapshot.session { session = snapshot.session }
        connected = true
        healthy = snapshot.ready
        serviceIssue = snapshot.issue
    }
    func resumeAccess() async {
        guard canAdd else { return }
        busy = true
        defer { busy = false }
        do { accept(try await ServiceClient.call { $0.resumeSession(reply: $1) }) }
        catch { self.error = error.localizedDescription }
    }
    func endSession() async {
        busy = true
        defer { busy = false }
        do { accept(try await ServiceClient.call { $0.endSession(reply: $1) }) }
        catch { self.error = error.localizedDescription }
    }
    func addWebsite(_ site: WebsiteSuggestion) async -> Bool {
        guard canAdd else { return false }
        busy = true
        defer { busy = false }
        do {
            let domains = Array(MacDomain.expanded(site))
            accept(try await ServiceClient.call { $0.addDomains(domains, reply: $1) })
            success = "\(site.name) added to your block list."
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func addApp(_ app: BlockedApplication) async -> Bool {
        guard canAdd else { return false }
        busy = true
        defer { busy = false }
        do {
            accept(try await ServiceClient.call { $0.addApplication(app.path, reply: $1) })
            success = "\(app.name) added to your block list."
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func isBlocked(_ app: BlockedApplication) -> Bool { list.applications.contains { $0.bundleID == app.bundleID } }
    func isBlocked(_ site: WebsiteSuggestion) -> Bool { MacDomain.expanded(site).isSubset(of: list.domains) }

    func reloadApps() {
        guard !loadingApps else { return }
        loadingApps = true
        Task {
            let apps = await Task.detached(priority: .utility) { Self.scanInstalledApps() }.value
            installedApps = apps
            loadingApps = false
        }
    }
    private nonisolated static func scanInstalledApps() -> [BlockedApplication] {
        let locations = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        var found: [String: BlockedApplication] = [:]
        for location in locations {
            guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: location),
                includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                if url.pathExtension == "app", let app = try? AppInspector.inspect(url.path) { found[app.bundleID] = app }
            }
        }
        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func chooseApp() -> BlockedApplication? {
        let panel = NSOpenPanel()
        panel.title = "Choose an app to block"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do { return try AppInspector.inspect(url.path) }
        catch { self.error = error.localizedDescription; return nil }
    }
}
