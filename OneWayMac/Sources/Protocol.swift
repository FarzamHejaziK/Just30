import Foundation

// No remove/reset/pause operation is exposed, including to the user interface.
@objc protocol OneWayServiceProtocol {
    func snapshot(reply: @escaping (Data?, String?) -> Void)
    func addDomains(_ domains: [String], reply: @escaping (Data?, String?) -> Void)
    func addApplication(_ path: String, reply: @escaping (Data?, String?) -> Void)
}
