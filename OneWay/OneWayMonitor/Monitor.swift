import DeviceActivity
import Foundation
import OSLog

final class OneWayMonitor: DeviceActivityMonitor {
    private func enforce() {
        do { try AllowanceStore.transaction { _ in } }
        catch { Logger(subsystem: "OneWay", category: "allowance").error("Session enforcement failed: \(error.localizedDescription, privacy: .public)") }
    }
    override func intervalDidStart(for activity: DeviceActivityName) {
        guard activity == AllowanceStore.activity else { return }
        enforce()
    }
    override func intervalDidEnd(for activity: DeviceActivityName) {
        guard activity == AllowanceStore.activity else { return }
        do {
            try AllowanceStore.transaction { state in
                // A delayed callback from an older schedule cannot stop a new session.
                if let end = state.session.endsAt, end <= Date().addingTimeInterval(2) { state.session.end() }
            }
        } catch { enforce() }
    }
}
