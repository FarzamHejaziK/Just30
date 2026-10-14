import Foundation

// An unsigned/ad-hoc-signed client must be denied even read-only access.
// Run only after OneWay's normal UI has successfully connected to the helper.
@main enum ConnectionProbe {
    static func main() {
        let connection = NSXPCConnection(machServiceName: OneWayConfig.serviceID, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: OneWayServiceProtocol.self)
        connection.resume()
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            print("PASS: unsigned client rejected by the running helper.")
            exit(0)
        } as! OneWayServiceProtocol
        proxy.snapshot { data, error in
            fputs("FAIL: unsigned client reached the exported service.\n", stderr)
            exit(1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            fputs("INCONCLUSIVE: helper did not reply or reject within five seconds.\n", stderr)
            exit(2)
        }
        withExtendedLifetime(connection) { RunLoop.main.run() }
    }
}
