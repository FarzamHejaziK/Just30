import Foundation
import Darwin

private var checks = 0
private func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw MacFailure.message("FAIL: " + message) }
    checks += 1
}

private final class TestClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

private final class ApplicationProbe {
    let allowed: Set<BlockedApplication>
    let watcher = AppEnforcer()
    var calls: [[BlockedApplication]] = []
    var unexpectedTargets: [BlockedApplication] = []
    var terminateFixtures = false

    init(_ fixtures: [BlockedApplication]) { allowed = Set(fixtures) }

    func enforce(_ targets: [BlockedApplication]) {
        calls.append(targets)
        // Refuse all non-fixture targets before invoking any process-signaling
        // code, even if a future regression tries to inject a real browser ID.
        let unexpected = targets.filter { !allowed.contains($0) }
        guard unexpected.isEmpty else { unexpectedTargets += unexpected; return }
        if terminateFixtures { watcher.enforce(targets) }
    }
}

private final class FixtureService {
    let directory: URL
    let hostsURL: URL
    let sessionURL: URL
    let clock: TestClock
    let applications: ApplicationProbe
    let service: BlockService

    init(root: URL, list: MacBlockList, session: AccessSession, at date: Date,
         fixtures: [BlockedApplication]) throws {
        directory = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        hostsURL = directory.appendingPathComponent("hosts")
        sessionURL = directory.appendingPathComponent("daily-access.json")
        try Data("127.0.0.1 localhost\n# unrelated user entry\n0.0.0.0 other.example\n".utf8).write(to: hostsURL)
        try StateFile.save(list, to: directory.appendingPathComponent("block-list.json"))
        try JSONEncoder().encode(session).write(to: sessionURL)
        clock = TestClock(date)
        applications = ApplicationProbe(fixtures)
        let clock = self.clock
        let applications = self.applications
        service = BlockService(testStateDirectory: directory,
            hosts: HostsEnforcer(hostsURL: hostsURL,
                backupURL: directory.appendingPathComponent("hosts-backup"), flushDNS: false),
            enforceApplications: applications.enforce, now: { clock.date })
    }

    func savedSession() throws -> AccessSession {
        try JSONDecoder().decode(AccessSession.self, from: Data(contentsOf: sessionURL))
    }

    func hosts() throws -> String { try String(contentsOf: hostsURL, encoding: .utf8) }
}

private func response(_ operation: (@escaping (Data?, String?) -> Void) -> Void) throws -> ServiceSnapshot {
    let done = DispatchSemaphore(value: 0)
    var result: Result<ServiceSnapshot, Error>?
    operation { data, error in
        defer { done.signal() }
        if let error { result = .failure(MacFailure.message(error)) }
        else if let data { result = Result { try JSONDecoder().decode(ServiceSnapshot.self, from: data) } }
        else { result = .failure(MacFailure.message("No service response")) }
    }
    guard done.wait(timeout: .now() + 5) == .success, let result else {
        throw MacFailure.message("FAIL: service reply timed out")
    }
    return try result.get()
}

private func launch(_ app: BlockedApplication) throws -> Process {
    let process = Process()
    process.executableURL = Bundle(path: app.path)!.executableURL!
    try process.run()
    return process
}

@main enum ServiceTests {
    static func main() {
        do { try run() }
        catch {
            fputs(error.localizedDescription + "\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        guard CommandLine.arguments.count == 3 else {
            throw MacFailure.message("Supply only the two disposable fixture app paths")
        }
        let selected = try AppInspector.inspect(CommandLine.arguments[1])
        let browser = try AppInspector.inspect(CommandLine.arguments[2])
        guard selected.bundleID == "com.example.OneWayTestFixture",
              browser.bundleID == "com.example.OneWayBrowserFixture" else {
            throw MacFailure.message("Refusing to test with non-fixture applications")
        }
        let fixtures = [selected, browser]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OneWay-service-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let selectedProcess = try launch(selected)
        defer { if selectedProcess.isRunning { selectedProcess.terminate() } }
        let browserProcess = try launch(browser)
        defer { if browserProcess.isRunning { browserProcess.terminate() } }
        Thread.sleep(forTimeInterval: 0.1)

        let start = Date(timeIntervalSince1970: 1_700_049_600) // Fixed UTC midday; no system-clock changes.
        var active = AccessSession()
        active.budget = DailyAllowance(now: start, timeZone: TimeZone(secondsFromGMT: 0)!)
        try active.startRemaining(now: start)
        active.pendingBrowserClose = true // An already-installed build can leave this flag on disk.
        let mixed = try MacBlockList().adding(application: selected, domains: ["blocked.example"])
        let expiry = try FixtureService(root: directory, list: mixed, session: active,
            at: start.addingTimeInterval(1), fixtures: fixtures)
        expiry.applications.terminateFixtures = true
        expiry.service.tickForTesting()
        try check(expiry.applications.calls.isEmpty, "active access does not terminate selected apps")
        try check(!(try expiry.hosts()).contains("blocked.example"), "active access leaves selected domains unlocked")
        try check(selectedProcess.isRunning && browserProcess.isRunning, "both fixture apps remain open during access")
        try check(!(try expiry.savedSession()).pendingBrowserClose, "upgrade retires a persisted browser-close flag")
        try check(try expiry.savedSession().endsAt == active.endsAt, "upgrade preserves the running deadline")

        expiry.clock.date = start.addingTimeInterval(DailyAllowance.limit + 1)
        let deadline = Date().addingTimeInterval(3)
        repeat {
            expiry.service.tickForTesting()
            Thread.sleep(forTimeInterval: 0.1)
        } while selectedProcess.isRunning && Date() < deadline
        try check(!selectedProcess.isRunning, "timer expiry still terminates the explicitly selected disposable app")
        try check(browserProcess.isRunning, "timer expiry preserves the unselected browser fixture")
        try check(expiry.applications.calls.allSatisfy { $0 == [selected] }, "expiry targets only the saved app list")
        try check(expiry.applications.unexpectedTargets.isEmpty, "no implicit browser identities are signaled")
        try check((try expiry.hosts()).contains("0.0.0.0\tblocked.example") && (try expiry.hosts()).contains("::1\tblocked.example"), "expiry restores both IPv4 and IPv6 website rules")
        try check((try expiry.hosts()).contains("0.0.0.0 other.example"), "expiry preserves unrelated host rules")
        try check(try expiry.savedSession().budget.remaining == 0, "expiry does not refund or reset the daily allowance")
        try check(try expiry.savedSession().endsAt == nil, "expiry persists the ended session")
        try check(try StateFile.load(expiry.directory.appendingPathComponent("block-list.json")) == mixed, "expiry preserves all saved apps and sites")

        // Resume/Pause exercises the same production service entry points as XPC,
        // without registering a daemon, touching real hosts, or consuming real time.
        let websites = try MacBlockList().adding(domains: ["blocked.example"])
        let pause = try FixtureService(root: directory, list: websites, session: active,
            at: start.addingTimeInterval(13 * 60), fixtures: fixtures)
        let paused = try response { pause.service.endSession(reply: $0) }
        try check(paused.session?.budget.remaining == 17 * 60, "Pause preserves the unused 17 minutes")
        try check((try pause.hosts()).contains("0.0.0.0\tblocked.example"), "Pause restores selected website rules")
        try check(pause.applications.calls.allSatisfy(\.isEmpty), "website-only Pause has no application targets")
        try check(browserProcess.isRunning, "website-only Pause preserves the browser fixture")
        let resumed = try response { pause.service.resumeSession(reply: $0) }
        try check(resumed.session?.isActive(at: pause.clock.date) == true, "Resume succeeds immediately after Pause")
        try check(resumed.session?.pendingBrowserClose == false, "Resume no longer arms browser termination")
        try check(!(try pause.hosts()).contains("blocked.example"), "Resume removes only managed website blocks")
        let added = try response { pause.service.addDomains(["added.example"], reply: $0) }
        try check(added.session?.pendingBrowserClose == false, "adding a site during access does not arm browser termination")
        pause.clock.date = resumed.session!.endsAt!.addingTimeInterval(1)
        pause.service.tickForTesting()
        try check((try pause.hosts()).contains("0.0.0.0\tadded.example"), "expiry also restores sites added during access")
        try check(pause.applications.calls.allSatisfy(\.isEmpty) && pause.applications.unexpectedTargets.isEmpty, "website-only expiry never adds browser targets")
        try check(browserProcess.isRunning, "browser fixture survives website-only resume and expiry")

        let restart = try FixtureService(root: directory, list: websites, session: active,
            at: start.addingTimeInterval(DailyAllowance.limit + 1), fixtures: fixtures)
        restart.service.tickForTesting()
        try check(restart.applications.calls.allSatisfy(\.isEmpty), "restart after expiry does not replay legacy browser shutdown")
        try check(try restart.savedSession().budget.remaining == 0, "restart after expiry preserves the exhausted allowance")
        try check(!(try restart.savedSession()).pendingBrowserClose, "restart clears the legacy flag on disk")
        try check((try restart.hosts()).contains("0.0.0.0\tblocked.example"), "restart restores saved website rules")

        let browserSelected = try MacBlockList().adding(application: browser)
        let explicit = try FixtureService(root: directory, list: browserSelected, session: active,
            at: start.addingTimeInterval(DailyAllowance.limit + 1), fixtures: fixtures)
        explicit.applications.terminateFixtures = true
        let browserDeadline = Date().addingTimeInterval(3)
        repeat {
            explicit.service.tickForTesting()
            Thread.sleep(forTimeInterval: 0.1)
        } while browserProcess.isRunning && Date() < browserDeadline
        try check(!browserProcess.isRunning, "a browser explicitly saved as a blocked app is still enforced")
        try check(explicit.applications.calls.allSatisfy { $0 == [browser] }, "explicit browser blocking does not select other browsers")
        try check(explicit.applications.unexpectedTargets.isEmpty, "explicit blocking never targets non-fixture apps")
        print("PASS: \(checks) helper regression checks. Temporary hosts/state, a fake clock, and two disposable apps only; no real browsers or system settings touched.")
    }
}
