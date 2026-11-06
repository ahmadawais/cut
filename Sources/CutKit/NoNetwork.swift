import CNoNetwork
import Foundation

/// Kernel-enforced "no network". The App Sandbox would block the Accessibility API Cut needs
/// (`mach-lookup com.apple.axserver`), so Cut sandboxes itself instead with a profile that allows
/// everything except networking. Applied once at launch, before any other code runs; it can't be
/// lifted afterwards, by Cut or by anything loaded into it.
public enum NoNetwork {
    /// Seatbelt profile: allow by default; deny IP sockets, DNS, and the background download daemon.
    static let profile = """
    (version 1)
    (allow default)
    (deny network-outbound (remote ip))
    (deny network-inbound (local ip))
    (deny network-bind (local ip))
    (deny network-outbound (literal "/private/var/run/mDNSResponder"))
    (deny mach-lookup (global-name "com.apple.nsurlsessiond") (global-name "com.apple.dnssd.service"))
    """

    public private(set) static var active = false

    public static func apply() {
        var err: UnsafeMutablePointer<CChar>?
        if cut_sandbox_apply(profile, &err) == 0 {
            active = true
            log.info("Network blocked by kernel sandbox")
        } else {
            log.fault("Could not block network: \(err.map { String(cString: $0) } ?? "unknown", privacy: .public)")
            if let err { cut_sandbox_free_error(err) }
        }
    }
}
