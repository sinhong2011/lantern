import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkMonitor {
    private(set) var lanIPv4: String?
    private(set) var interfaceName: String?
    private(set) var isSatisfied: Bool = false
    private(set) var statusLabel: String = "Looking for network…"

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.lantern.network")

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.apply(path: path)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }

    private func apply(path: NWPath) {
        isSatisfied = path.status == .satisfied
        guard path.status == .satisfied else {
            lanIPv4 = nil
            interfaceName = nil
            statusLabel = "No network"
            return
        }

        // Prefer Wi‑Fi / Ethernet, skip virtual bridges (OrbStack bridge100, utun, etc.)
        let preferred = path.availableInterfaces.first { iface in
            switch iface.type {
            case .wifi, .wiredEthernet: return true
            default: return false
            }
        } ?? path.availableInterfaces.first

        interfaceName = preferred?.name
        lanIPv4 = Self.ipv4Address(for: preferred?.name)
        if let ip = lanIPv4, let name = interfaceName {
            statusLabel = "\(name) · \(ip)"
        } else if let ip = lanIPv4 {
            statusLabel = ip
        } else {
            statusLabel = "Connected · no IPv4"
        }
    }

    private static func ipv4Address(for interfaceName: String?) -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var candidate: String?
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let addr = pointer {
            defer { pointer = addr.pointee.ifa_next }
            let name = String(cString: addr.pointee.ifa_name)
            guard let interfaceName else {
                // fallback: first non-loopback IPv4 not on bridge/utun
                if shouldSkip(interface: name) { continue }
                if let ip = ipv4(from: addr) { return ip }
                continue
            }
            if name == interfaceName, let ip = ipv4(from: addr) {
                return ip
            }
            // Soft fallback if exact name missing
            if candidate == nil, !shouldSkip(interface: name), let ip = ipv4(from: addr) {
                candidate = ip
            }
        }
        return candidate
    }

    private static func shouldSkip(interface: String) -> Bool {
        interface == "lo0"
            || interface.hasPrefix("bridge")
            || interface.hasPrefix("utun")
            || interface.hasPrefix("awdl")
            || interface.hasPrefix("llw")
            || interface.hasPrefix("anpi")
            || interface.hasPrefix("ap")
            || interface.hasPrefix("gif")
            || interface.hasPrefix("stf")
            || interface.hasPrefix("VCM")
            || interface.hasPrefix("orb")
    }

    private static func ipv4(from ifa: UnsafeMutablePointer<ifaddrs>) -> String? {
        guard ifa.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { return nil }
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            ifa.pointee.ifa_addr,
            socklen_t(ifa.pointee.ifa_addr.pointee.sa_len),
            &hostname,
            socklen_t(hostname.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard result == 0 else { return nil }
        let ip = String(cString: hostname)
        if ip.hasPrefix("127.") { return nil }
        return ip
    }
}
