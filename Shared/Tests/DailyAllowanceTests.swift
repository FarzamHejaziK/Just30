import Foundation

@main enum AllowanceTests {
    static func main() throws {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let now = ISO8601DateFormatter().date(from: "2026-10-14T20:00:00Z")!
        var budget = DailyAllowance(now: now, timeZone: zone)
        precondition(budget.remaining == 1800)
        budget.charge(600, now: now)
        budget.charge(300, now: now.addingTimeInterval(300))
        precondition(budget.remaining == 900, "Different apps use one budget")
        budget = try JSONDecoder().decode(DailyAllowance.self, from: JSONEncoder().encode(budget))
        precondition(budget.remaining == 900, "Relaunch preserves consumption")
        budget.advance(to: now.addingTimeInterval(-86400))
        precondition(budget.remaining == 900, "Clock rollback cannot reset usage")
        budget.charge(9999, now: now)
        precondition(budget.remaining == 0, "Budget saturates at 30 minutes")
        budget.advance(to: now.addingTimeInterval(86400))
        precondition(budget.remaining == 1800, "The next calendar day renews the allowance")
        budget.charge(-1, now: now.addingTimeInterval(86400))
        budget.charge(.nan, now: now.addingTimeInterval(86400))
        precondition(budget.remaining == 1800, "Invalid debit cannot add allowance")
        var checkpoint = DailyAllowance(now: now, timeZone: zone)
        checkpoint.recordAtLeast(900, now: now)
        checkpoint.recordAtLeast(300, now: now)
        precondition(checkpoint.used == 900, "Out-of-order callbacks cannot reduce usage")
        checkpoint.recordAtLeast(1800, now: now)
        checkpoint.advance(to: now.addingTimeInterval(1))
        precondition(checkpoint.remaining == 0, "Same-day restart cannot replenish exhausted budget")
        let spring = ISO8601DateFormatter().date(from: "2026-03-08T08:00:00Z")!
        var dst = DailyAllowance(now: spring, timeZone: zone)
        dst.charge(1800, now: spring)
        dst.advance(to: spring.addingTimeInterval(23 * 3600))
        precondition(dst.remaining == 1800, "DST resets at calendar midnight, not after 24 hours")
        var access = AccessSession()
        access.budget = DailyAllowance(now: now, timeZone: zone)
        try access.startRemaining(now: now)
        precondition(access.isActive(at: now.addingTimeInterval(1799)))
        precondition(!access.isActive(at: now.addingTimeInterval(1800)), "Access expires at the exact deadline")
        precondition(access.budget.remaining == 0, "Time is reserved before unlocking")
        do { try access.startRemaining(now: now); fatalError("Overlapping session accepted") } catch {}
        access = try JSONDecoder().decode(AccessSession.self, from: JSONEncoder().encode(access))
        precondition(access.isActive(at: now.addingTimeInterval(10)), "Session survives restart")
        access.end(now: now.addingTimeInterval(13 * 60))
        precondition(access.budget.remaining == 17 * 60, "13 minutes played leaves 17 minutes after pausing")
        access.end(now: now.addingTimeInterval(14 * 60))
        precondition(access.budget.remaining == 17 * 60, "Repeated pause cannot refund twice")
        access = try JSONDecoder().decode(AccessSession.self, from: JSONEncoder().encode(access))
        try access.startRemaining(now: now.addingTimeInterval(3600))
        precondition(access.endsAt == now.addingTimeInterval(3600 + 17 * 60), "Resume uses only the saved 17 minutes")
        access.end(now: now.addingTimeInterval(3600 + 17 * 60))
        precondition(access.budget.remaining == 0, "Total resumed usage is capped at 30 minutes")
        do { try access.startRemaining(now: now.addingTimeInterval(7200)); fatalError("Exceeded cap") } catch {}
        try access.startRemaining(now: now.addingTimeInterval(86400))
        precondition(access.available(at: now.addingTimeInterval(86400)) == 1800, "Next day grants exactly one new budget")
        precondition(!access.isActive(at: now), "Clock rollback closes current access")
        access.end(now: now)
        precondition(access.budget.remaining == 0, "Rollback cannot increase a reservation refund")
        let nearMidnight = ISO8601DateFormatter().date(from: "2026-10-15T06:58:00Z")!
        var late = AccessSession()
        late.budget = DailyAllowance(now: nearMidnight, timeZone: zone)
        try late.startRemaining(now: nearMidnight)
        precondition(late.endsAt == nearMidnight.addingTimeInterval(120), "Sessions cannot cross midnight")
        precondition(!late.isActive(at: nearMidnight.addingTimeInterval(121)))
        late.end(now: nearMidnight.addingTimeInterval(121))
        precondition(late.budget.remaining == 1800, "Midnight gives exactly 30 minutes without carryover")
        try late.validate()
        var fractional = AccessSession()
        fractional.budget = DailyAllowance(now: now, timeZone: zone)
        try fractional.startRemaining(now: now)
        fractional.end(now: now.addingTimeInterval(13.25))
        precondition(fractional.budget.remaining == 1786.75, "Rapid pause/resume retains subsecond accuracy")
        try fractional.startRemaining(now: now.addingTimeInterval(20))
        precondition(fractional.endsAt == now.addingTimeInterval(1806.75))
        var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(access)) as! [String: Any]
        legacyJSON.removeValue(forKey: "accountingVersion")
        var legacy = try JSONDecoder().decode(AccessSession.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
        legacy.migratePausableAccounting(now: now)
        precondition(legacy.budget.remaining == 1800, "Old discarded-time accounting migrates once")
        try legacy.startRemaining(now: now)
        legacy.end(now: now.addingTimeInterval(780))
        legacy.migratePausableAccounting(now: now.addingTimeInterval(800))
        precondition(legacy.budget.remaining == 1020, "Migration cannot replenish v2 usage")
        // Reproduce Screen Time synchronously invoking a monitor callback during
        // registration. That callback must be able to acquire the storage lock.
        let storageLock = NSLock()
        var stored = AccessSession()
        stored.budget = DailyAllowance(now: now, timeZone: zone)
        var cancelled = false
        var testNow = now
        let read = { () -> AccessSession in
            storageLock.lock(); defer { storageLock.unlock() }
            return stored
        }
        let commit = { (previous: AccessSession, proposed: AccessSession) throws in
            storageLock.lock(); defer { storageLock.unlock() }
            guard stored == previous else { throw AccessSessionError.unavailable }
            stored = proposed
        }
        for _ in 0..<3 {
            try MonitoredSessionStart.run(read: read, arm: { _ in
                let callbackFinished = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    storageLock.lock()
                    storageLock.unlock()
                    callbackFinished.signal()
                }
                precondition(callbackFinished.wait(timeout: .now() + 1) == .success,
                    "Monitor registration must not hold the callback's storage lock")
                precondition(!read().isActive(at: testNow), "Restrictions stay applied until registration succeeds")
            }, commit: commit, cancel: { cancelled = true }, now: { testNow })
            precondition(stored.isActive(at: testNow))
            stored.end(now: testNow.addingTimeInterval(10))
            testNow.addTimeInterval(20)
        }
        precondition(stored.budget.remaining == 1770 && !cancelled,
            "Repeated Start/Pause/Resume preserves the exact combined allowance")
        let beforeFailure = stored
        do {
            try MonitoredSessionStart.run(read: read, arm: { _ in throw AccessSessionError.unavailable },
                commit: commit, cancel: { cancelled = true }, now: { testNow })
            fatalError("Failed registration unlocked access")
        } catch {}
        precondition(stored == beforeFailure && cancelled, "Failed registration neither unlocks nor spends time")
        cancelled = false
        do {
            try MonitoredSessionStart.run(read: read, arm: { _ in stored.budget.charge(1, now: testNow) },
                commit: commit, cancel: { cancelled = true }, now: { testNow })
            fatalError("A stale reservation overwrote newer state")
        } catch {}
        precondition(!stored.isActive(at: testNow) && cancelled && stored.budget.remaining == 1769,
            "Concurrent state changes cancel the newly armed monitor without overwriting usage")
        cancelled = false
        let beforeSlowRegistration = stored
        do {
            try MonitoredSessionStart.run(read: read, arm: { _ in testNow.addTimeInterval(1800) },
                commit: commit, cancel: { cancelled = true }, now: { testNow })
            fatalError("Slow registration opened expired access")
        } catch {}
        precondition(stored == beforeSlowRegistration && cancelled, "Expired registration leaves restrictions intact")
        try checkpoint.validate()
        print("Daily allowance tests passed: aggregation, persistence, pause/resume, 13+17 minutes, exhaustion, rollback, day rollover, DST, monitor callback locking and registration failures")
    }
}
