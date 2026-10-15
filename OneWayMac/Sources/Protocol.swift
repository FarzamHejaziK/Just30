import Foundation

// Lists are add-only. Access sessions have a fixed, persisted daily cap.
@objc protocol OneWayServiceProtocol {
    func resumeSession(reply: @escaping (Data?, String?) -> Void)
    func endSession(reply: @escaping (Data?, String?) -> Void)
    func snapshot(reply: @escaping (Data?, String?) -> Void)
    func addDomains(_ domains: [String], reply: @escaping (Data?, String?) -> Void)
    func addApplication(_ path: String, reply: @escaping (Data?, String?) -> Void)
}
