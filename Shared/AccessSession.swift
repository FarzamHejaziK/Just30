import Foundation

/// Register the deadline without holding the persistence lock. Screen Time may
/// synchronously start our monitor extension, which reads the same stored state.
enum MonitoredSessionStart {
    static func run(read: () throws -> AccessSession,
                    arm: (Date) throws -> Void,
                    commit: (AccessSession, AccessSession) throws -> Void,
                    cancel: () -> Void,
                    now: () -> Date = Date.init) throws {
        let previous = try read()
        var proposed = previous
        try proposed.startRemaining(now: now())
        guard let deadline = proposed.endsAt else { throw AccessSessionError.unavailable }
        do {
            try arm(deadline)
            // A slow registration must never open an already expired session.
            guard proposed.isActive(at: now()) else { throw AccessSessionError.unavailable }
            try commit(previous, proposed)
        } catch {
            cancel()
            throw error
        }
    }
}

enum AccessSessionError: LocalizedError {
    case unavailable
    var errorDescription: String? { "A session is already running, or there isn't enough daily time left for that duration." }
}

struct AccessSession: Codable, Equatable {
    var budget = DailyAllowance()
    private(set) var accountingVersion: Int? = 2
    private(set) var endsAt: Date?
    private(set) var startedAt: Date?
    // Legacy Mac field retained for decoding older state and reader compatibility.
    // The Mac helper clears and ignores it; website rules do not close browsers.
    var pendingBrowserClose = false

    mutating func migratePausableAccounting(now: Date = Date()) {
        guard accountingVersion == nil else { return }
        // The short-lived fixed-reservation build discarded unused time on stop.
        // It did not retain enough history to recover that remainder. Give paused
        // legacy states a one-time fresh budget; never repeat this for v2 states.
        if endsAt == nil {
            budget = DailyAllowance(now: now, timeZone: TimeZone(identifier: budget.timeZoneID) ?? .current)
        }
        accountingVersion = 2
    }

    func isActive(at now: Date = Date()) -> Bool {
        guard let start = startedAt, let end = endsAt else { return false }
        return now >= start && now < end && budget.calendar.startOfDay(for: now) == budget.dayStart
    }
    mutating func start(minutes: Int, now: Date = Date()) throws {
        try start(seconds: Double(minutes) * 60, now: now)
    }
    mutating func startRemaining(now: Date = Date()) throws {
        budget.advance(to: now)
        try start(seconds: budget.remaining, now: now)
    }
    private mutating func start(seconds: TimeInterval, now: Date) throws {
        budget.advance(to: now)
        guard !isActive(at: now), seconds.isFinite, seconds >= 1,
              seconds <= budget.remaining else { throw AccessSessionError.unavailable }
        let midnight = budget.calendar.date(byAdding: .day, value: 1, to: budget.dayStart)!
        let end = min(now.addingTimeInterval(seconds), midnight)
        budget.charge(end.timeIntervalSince(now), now: now)
        startedAt = now
        endsAt = end
    }
    mutating func end(now: Date = Date()) {
        // Return only this session's unelapsed reservation, once. A pause after
        // midnight never transfers unused time into the new day's budget.
        if let start = startedAt, let end = endsAt, now >= start,
           budget.calendar.startOfDay(for: now) == budget.dayStart {
            budget.returnUnusedReservation(max(0, end.timeIntervalSince(now)))
        }
        endsAt = nil
        startedAt = nil
        budget.advance(to: now)
    }
    func available(at now: Date = Date()) -> TimeInterval {
        guard isActive(at: now), let end = endsAt else { return budget.remaining }
        return min(DailyAllowance.limit, budget.remaining + max(0, end.timeIntervalSince(now)))
    }
    static func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(ceil(seconds)))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
    func validate() throws {
        try budget.validate()
        guard (endsAt == nil) == (startedAt == nil) else { throw CocoaError(.fileReadCorruptFile) }
        if let start = startedAt, let end = endsAt {
            guard end >= start, end.timeIntervalSince(start) <= DailyAllowance.limit,
                  end.timeIntervalSince1970.isFinite, start.timeIntervalSince1970.isFinite else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
    }
}
