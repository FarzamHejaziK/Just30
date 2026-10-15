import Foundation

/// A single budget for a whole device, never one budget per application.
/// Keep the original time zone so changing time zones cannot grant a second day.
struct DailyAllowance: Codable, Equatable {
    static let limit: TimeInterval = 30 * 60
    private(set) var dayStart: Date
    let timeZoneID: String
    private(set) var used: TimeInterval = 0

    init(now: Date = Date(), timeZone: TimeZone = .current) {
        timeZoneID = timeZone.identifier
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        dayStart = calendar.startOfDay(for: now)
    }
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    var remaining: TimeInterval { max(0, Self.limit - used) }
    mutating func advance(to now: Date) {
        let start = calendar.startOfDay(for: now)
        // Clock rollback cannot replenish the budget.
        if start > dayStart { dayStart = start; used = 0 }
    }
    mutating func charge(_ seconds: TimeInterval, now: Date) {
        advance(to: now)
        if seconds.isFinite && seconds > 0 { used = min(Self.limit, used + seconds) }
    }
    mutating func recordAtLeast(_ seconds: TimeInterval, now: Date) {
        advance(to: now)
        if seconds.isFinite { used = min(Self.limit, max(used, seconds)) }
    }
    mutating func returnUnusedReservation(_ seconds: TimeInterval) {
        if seconds.isFinite && seconds > 0 { used = max(0, used - seconds) }
    }
    func validate() throws {
        guard used.isFinite, (0...Self.limit).contains(used), dayStart.timeIntervalSince1970.isFinite,
              TimeZone(identifier: timeZoneID) != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}
