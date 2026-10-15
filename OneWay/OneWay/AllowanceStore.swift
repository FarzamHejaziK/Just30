import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity
import Darwin

struct AllowanceState: Codable, Equatable {
    var list = BlockList<ApplicationToken, ActivityCategoryToken, WebDomainToken>()
    var session = AccessSession()
}

/// App and monitor serialize reads, writes and shields with the same file lock.
enum AllowanceStore {
    static let activity = DeviceActivityName("OneWay.DailyApps")
    static let settings = ManagedSettingsStore(named: .init("OneWay.Permanent"))
    static func transaction<T>(_ body: (inout AllowanceState) throws -> T) throws -> T {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "OneWayAppGroup") as? String,
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw CocoaError(.fileReadNoPermission)
        }
        let fd = open(root.appendingPathComponent("allowance.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { flock(fd, LOCK_UN); close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw CocoaError(.fileReadUnknown) }
        let url = root.appendingPathComponent("allowance.json")
        var state = FileManager.default.fileExists(atPath: url.path)
            ? try JSONDecoder().decode(AllowanceState.self, from: Data(contentsOf: url)) : AllowanceState()
        try state.list.validate()
        try state.session.validate()
        let previous = state
        let result = try body(&state)
        try state.list.validate()
        try state.session.validate()
        if state != previous || !FileManager.default.fileExists(atPath: url.path) {
            try JSONEncoder().encode(state).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        apply(state)
        return result
    }

    static func apply(_ state: AllowanceState) {
        let locked = !state.session.isActive()
        settings.shield.applications = locked && !state.list.apps.isEmpty ? state.list.apps : nil
        settings.shield.applicationCategories = locked && !state.list.categories.isEmpty ? .specific(state.list.categories) : nil
        settings.shield.webDomainCategories = locked && !state.list.categories.isEmpty ? .specific(state.list.categories) : nil
        settings.shield.webDomains = locked && !state.list.websites.isEmpty ? state.list.websites : nil
        settings.webContent.blockedByFilter = locked && !state.list.domains.isEmpty
            ? .specific(Set(state.list.domains.map { WebDomain(domain: $0) })) : nil
    }

    static func startAccess() throws -> AllowanceState {
        let monitor = DeviceActivityCenter()
        var committed: AllowanceState?
        try MonitoredSessionStart.run(
            read: { try transaction { $0.session } },
            arm: { try monitor.startMonitoring(activity, during: schedule(ending: $0)) },
            commit: { previous, proposed in
                committed = try transaction { state in
                    // Preserve concurrent list additions. A changed session must
                    // be retried, never overwritten by an older reservation.
                    guard state.session == previous else { throw AccessSessionError.unavailable }
                    state.session = proposed
                    return state
                }
            },
            cancel: { monitor.stopMonitoring([activity]) })
        guard let committed else { throw AccessSessionError.unavailable }
        return committed
    }

    static func schedule(ending end: Date, now: Date = Date()) -> DeviceActivitySchedule {
        // Device Activity requires intervals of at least 15 minutes. Start in the
        // recent past so even a five-minute access session has a valid interval.
        let calendar = Calendar.current
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        return DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(fields, from: now.addingTimeInterval(-16 * 60)),
            intervalEnd: calendar.dateComponents(fields, from: end), repeats: false)
    }
}
