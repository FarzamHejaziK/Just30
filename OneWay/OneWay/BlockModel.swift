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
    @Published private(set) var busy = true
    @Published var error: String?
    private var lastRefresh = Date.distantPast
    private let center = AuthorizationCenter.shared
    private let worker = DispatchQueue(label: "JustThirty.ScreenTime", qos: .userInitiated)
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
            busy = false
            return
        }
        #endif
        Task { await load() }
    }
    // Device Activity and Managed Settings make synchronous system calls. Keep
    // them and disk locking on one worker, never on the UI's main actor.
    private func perform<T>(_ operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            worker.async { continuation.resume(with: Result(catching: operation)) }
        }
    }
    private func load() async {
        do {
            let state = try await perform {
                let oldURL = URL.applicationSupportDirectory.appending(path: "OneWay/block-list.json")
                let old = try BlockListFile<ApplicationToken, ActivityCategoryToken, WebDomainToken>(url: oldURL).load()
                return try AllowanceStore.transaction { state in
                    state.list = try state.list.adding(apps: old.apps, categories: old.categories,
                        websites: old.websites, domains: old.domains)
                    state.session.migratePausableAccounting()
                    state.session.budget.advance(to: Date())
                    return state
                }
            }
            accept(state)
            loaded = true
        } catch { self.error = "Your saved list or daily allowance could not be read. Existing restrictions have been left in place. \(error.localizedDescription)" }
        busy = false
        await refresh()
    }
    private func accept(_ state: AllowanceState) {
        if list != state.list { list = state.list }
        if session != state.session { session = state.session }
    }
    func refreshIfNeeded(now: Date = Date()) async {
        let expired = session.endsAt.map { now >= $0 } ?? false
        let newDay = session.budget.calendar.startOfDay(for: now) > session.budget.dayStart
        if expired || newDay || now.timeIntervalSince(lastRefresh) >= 30 { await refresh() }
    }
    func refresh() async {
        guard !isScreenshotPreview, !busy else { return }
        lastRefresh = Date()
        let currentApproval = center.authorizationStatus == .approved
        if approved != currentApproval { approved = currentApproval }
        guard loaded && approved else { return }
        busy = true
        defer { busy = false }
        do {
            accept(try await perform {
                // Never call Device Activity while holding the shared file lock.
                let monitored = DeviceActivityCenter().activities.contains(AllowanceStore.activity)
                return try AllowanceStore.transaction { state in
                    state.session.budget.advance(to: Date())
                    if !state.session.isActive() || !monitored { state.session.end() }
                    return state
                }
            })
        } catch { loaded = false; self.error = error.localizedDescription }
    }
    func authorize() async {
        guard !busy else { return }
        busy = true
        do { try await center.requestAuthorization(for: .individual) }
        catch { self.error = "Screen Time access was not enabled: \(error.localizedDescription)" }
        busy = false
        await refresh()
    }
    func resumeAccess() async {
        guard loaded && approved && !list.isEmpty && !busy else { return }
        #if DEBUG && targetEnvironment(simulator)
        if isScreenshotPreview { try? session.startRemaining(); return }
        #endif
        busy = true
        error = nil
        defer { busy = false }
        do { accept(try await perform { try AllowanceStore.startAccess() }) }
        catch { self.error = "Could not start access. Your daily limit may be used up, or background monitoring could not start. \(error.localizedDescription)" }
    }
    func endSession() async {
        guard loaded && approved && !busy else { return }
        #if DEBUG && targetEnvironment(simulator)
        if isScreenshotPreview { session.end(); return }
        #endif
        busy = true
        error = nil
        defer { busy = false }
        do {
            accept(try await perform {
                let state = try AllowanceStore.transaction { state in state.session.end(); return state }
                DeviceActivityCenter().stopMonitoring([AllowanceStore.activity])
                return state
            })
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult
    func add(selection: FamilyActivitySelection) async -> Bool {
        await commit { try $0.adding(apps: selection.applicationTokens, categories: selection.categoryTokens, websites: selection.webDomainTokens) }
    }
    @discardableResult
    func add(domains: Set<String>) async -> Bool { await commit { try $0.adding(domains: domains) } }
    private func commit(_ update: @escaping (List) throws -> List) async -> Bool {
        guard loaded && approved && !busy else { return false }
        busy = true
        error = nil
        defer { busy = false }
        do {
            accept(try await perform {
                try AllowanceStore.transaction { state in state.list = try update(state.list); return state }
            })
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
