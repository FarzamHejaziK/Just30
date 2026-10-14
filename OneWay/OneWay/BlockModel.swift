import SwiftUI
import FamilyControls
import ManagedSettings

@MainActor
final class BlockModel: ObservableObject {
    typealias List = BlockList<ApplicationToken, ActivityCategoryToken, WebDomainToken>
    @Published private(set) var list = List()
    @Published private(set) var approved = false
    @Published private(set) var loaded = false
    @Published private(set) var busy = false
    @Published var error: String?
    private let center = AuthorizationCenter.shared
    private let settings = ManagedSettingsStore(named: .init("OneWay.Permanent"))
    private let file: BlockListFile<ApplicationToken, ActivityCategoryToken, WebDomainToken>

    init() {
        let root = URL.applicationSupportDirectory.appending(path: "OneWay", directoryHint: .isDirectory)
        file = .init(url: root.appending(path: "block-list.json"))
        do { list = try file.load(); loaded = true }
        catch { self.error = "Your saved list could not be read. Existing iOS restrictions have been left in place. Connect to your Mac to repair the saved data. \(error.localizedDescription)" }
        refresh()
    }

    func refresh() {
        approved = center.authorizationStatus == .approved
        if loaded && approved { apply() }
    }

    func authorize() async {
        busy = true
        defer { busy = false }
        do { try await center.requestAuthorization(for: .individual); refresh() }
        catch { self.error = "Screen Time access was not enabled: \(error.localizedDescription)" }
    }

    @discardableResult
    func add(selection: FamilyActivitySelection) -> Bool {
        commit { try list.adding(apps: selection.applicationTokens, categories: selection.categoryTokens, websites: selection.webDomainTokens) }
    }

    @discardableResult
    func add(domains: Set<String>) -> Bool {
        commit { try list.adding(domains: domains) }
    }

    private func commit(_ update: () throws -> List) -> Bool {
        refresh()
        guard loaded && approved else { error = "Screen Time access and a readable saved list are required before adding blocks."; return false }
        do {
            let next = try update()
            // Persist before enforcing or showing success. A failed write never drops old entries.
            try file.save(next)
            list = next
            apply()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    private func apply() {
        // Never clear a settings store. Empty values on a fresh install do not clear existing restrictions.
        if !list.apps.isEmpty { settings.shield.applications = list.apps }
        if !list.categories.isEmpty {
            settings.shield.applicationCategories = .specific(list.categories)
            settings.shield.webDomainCategories = .specific(list.categories)
        }
        if !list.websites.isEmpty { settings.shield.webDomains = list.websites }
        if !list.domains.isEmpty {
            settings.webContent.blockedByFilter = .specific(Set(list.domains.map { WebDomain(domain: $0) }))
        }
    }
}
