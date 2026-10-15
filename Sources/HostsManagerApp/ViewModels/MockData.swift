import Shared

/// Phase 1 stand-in for `/etc/hosts` — same content as `MOCK_LINES` in `.prototype/javascripts/shared.js`.
/// Starts with the header macOS ships with.
enum MockData {
    static let lines: [HostsLine] = [
        .comment("#"),
        .comment(" Host Database"),
        .comment(""),
        .comment(" localhost is used to configure the loopback interface"),
        .comment(" when the system is booting.  Do not change this entry."),
        .comment("#"),
        .entry(HostEntry(ip: "127.0.0.1", hostnames: ["localhost"])),
        .entry(HostEntry(ip: "255.255.255.255", hostnames: ["broadcasthost"])),
        .entry(HostEntry(ip: "::1", hostnames: ["localhost"])),
        .blank,
        .comment(" Local dev"),
        .entry(HostEntry(ip: "127.0.0.1", hostnames: ["api.test", "web.test"], comment: "docker compose")),
        .entry(HostEntry(ip: "127.0.0.1", hostnames: ["admin.test"], isEnabled: false)),
        .blank,
        .comment(" Staging"),
        .entry(HostEntry(ip: "10.0.0.5", hostnames: ["staging.example.com"], comment: "VPN only", isEnabled: false)),
        .entry(HostEntry(ip: "fd00::5", hostnames: ["staging6.example.com"], isEnabled: false)),
        .blank,
        .comment(" Blocked"),
        .entry(HostEntry(ip: "0.0.0.0", hostnames: ["ads.example.net", "tracker.example.net"]))
    ]
}
