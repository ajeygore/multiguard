import Foundation

/// XPC protocol used between the main app and the privileged helper tool.
@objc(MultiGuardHelperProtocol)
protocol MultiGuardHelperProtocol {
    /// Echo request used to verify the helper is alive and reachable.
    func ping(withReply reply: @escaping (Bool) -> Void)

    /// Bring up a WireGuard tunnel using the config at `configPath`.
    /// Returns the assigned interface name (e.g. "utun3") on success.
    func connect(withConfigPath configPath: String, reply: @escaping (String?, Error?) -> Void)

    /// Tear down a WireGuard tunnel using the config at `configPath`.
    func disconnect(withConfigPath configPath: String, reply: @escaping (Error?) -> Void)
}
