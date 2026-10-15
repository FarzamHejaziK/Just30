import SwiftUI
import FamilyControls
import ManagedSettings
import DeviceActivity

@MainActor
final class BlockModel: ObservableObject {
    typealias List = BlockList<ApplicationToken, ActivityCategoryToken, WebDomainToken>
    @Published private(set) var list = List()
    @Published private(set) var session = AccessSession()
    @Published private(set) var approved = false
    @Published private(set) var loaded = false
    @Published private(set) var busy = false
    @Published var error: String?
    private var lastRefresh = Date.distantPast
    private let center = AuthorizationCenter.shared
    private let monitor = DeviceActivityCenter()
    private var isScreenshotPreview: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--screenshot-mode")
        #else
        return false
        #endif
    }

    init() {
        #if DEBUG && targetEnvironment(simulator)
        if isScreenshotPreview {
            list = try! list.adding(domains: ["example.com"])
            loaded = true
            approved = true
            return
        }
        #endif
        do {
            let oldURL = URL.applicationSupportDirectory.appending(path: "OneWay/block-list.json")
            let old = try BlockListFile<ApplicationToken, ActivityCategoryToken, WebDomainToken>(url: oldURL).load()
            // Union the old private list into the shared container; never remove it.
            let state = try AllowanceStore.transaction { state in
                state.list = try state.list.adding(apps: old.apps, categories: old.categories,
                    websites: old.websites, domains: old.domains)
                state.session.migratePausableAccounting()
                state.session.budget.advance(to: Date())
                return state
            }
            accept(state)
            loaded = true
        } catch { self.error = "Your saved list or daily allowance could not be read. Existing restrictions have been left in place. \(error.localizedDescription)" }
        refresh()
    }
    private func accept(_ state: AllowanceState) {
        if list != state.list { list = state.list }
        if session != state.session { session = state.session }
    }
    func refreshIfNeeded(now: Date = Date()) {
        let expired = session.endsAt.map { now >= $0 } ?? false
        let newDay = session.budget.calendar.startOfDay(for: now) > session.budget.dayStart
        if expired || newDay || now.timeIntervalSince(lastRefresh) >= 30 { refresh() }
    }
    func refresh() {
        guard !isScreenshotPreview else { return }
        lastRefresh = Date()
        let currentApproval = center.authorizationStatus == .approved
        if approved != currentApproval { approved = currentApproval }
        guard loaded && approved else { return }
        do {
            accept(try AllowanceStore.transaction { state in
                state.session.budget.advance(to: Date())
                if !state.session.isActive() { state.session.end() }
                else if !monitor.activities.contains(AllowanceStore.activity) {
                    // Missing monitor is never grounds to leave an unbounded unlock.
                    state.session.end()
                }
                return state
            })
        } catch { loaded = false; self.error = error.localizedDescription }
    }
    func authorize() async {
        busy = true
        defer { busy = false }
        do { try await center.requestAuthorization(for: .individual); refresh() }
        catch { self.error = "Screen Time access was not enabled: \(error.localizedDescription)" }
    }
    func resumeAccess() {
        guard loaded && approved && !list.isEmpty else { return }
        #if DEBUG && targetEnvironment(simulator)
        if isScreenshotPreview { try? session.startRemaining(); return }
        #endif
        do {
            accept(try AllowanceStore.transaction { state in
                try state.session.startRemaining()
                guard let end = state.session.endsAt else { throw CocoaError(.fileReadUnknown) }
                // Arm background re-blocking before persisting and lifting shields.
                try monitor.startMonitoring(AllowanceStore.activity, during: AllowanceStore.schedule(ending: end))
                return state
            })
        } catch { self.error = "Could not start access. Your daily limit may be used up, or background monitoring could not start. \(error.localizedDescription)" }
    }
    func endSession() {
        #if DEBUG && targetEnvironment(simulator)
        if isScreenshotPreview { session.end(); return }
        #endif
        do {
            accept(try AllowanceStore.transaction { state in state.session.end(); return state })
            monitor.stopMonitoring([AllowanceStore.activity])
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult
    func add(selection: FamilyActivitySelection) -> Bool {
        commit { try $0.adding(apps: selection.applicationTokens, categories: selection.categoryTokens, websites: selection.webDomainTokens) }
    }
    @discardableResult
    func add(domains: Set<String>) -> Bool { commit { try $0.adding(domains: domains) } }
    private func commit(_ update: (List) throws -> List) -> Bool {
        guard loaded && approved else { return false }
        do {
            accept(try AllowanceStore.transaction { state in state.list = try update(state.list); return state })
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
