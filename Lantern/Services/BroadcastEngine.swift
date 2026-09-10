import Foundation
import dnssd
import Darwin

/// Registers `name.local` on the physical LAN via DNS-SD (Bonjour).
/// Uses `dns-sd -P` semantics: custom host + explicit IPv4, not OrbStack's bridge.
actor BroadcastEngine {
    enum EngineError: LocalizedError {
        case missingIP
        case registerFailed(Int32)
        case invalidName

        var errorDescription: String? {
            switch self {
            case .missingIP: return "No LAN IPv4 address available."
            case .registerFailed(let code): return "DNS-SD register failed (\(code))."
            case .invalidName: return "Service name is invalid."
            }
        }
    }

    private struct Registration {
        var serviceRef: DNSServiceRef?
        var alias: ServiceAlias
        var advertisedPort: UInt16
        var ip: String
    }

    private var registrations: [UUID: Registration] = [:]
    private var processFallback: [UUID: Process] = [:]

    func sync(
        aliases: [ServiceAlias],
        lanIP: String?,
        masterEnabled: Bool,
        proxyEnabled: Bool,
        proxyPort: Int
    ) async {
        let desired: [ServiceAlias] = masterEnabled
            ? aliases.filter(\.enabled)
            : []

        let desiredIDs = Set(desired.map(\.id))
        for id in registrations.keys where !desiredIDs.contains(id) {
            await unregister(id: id)
        }
        for id in processFallback.keys where !desiredIDs.contains(id) {
            stopProcess(id: id)
        }

        guard let lanIP, !lanIP.isEmpty else {
            for id in Array(registrations.keys) { await unregister(id: id) }
            for id in Array(processFallback.keys) { stopProcess(id: id) }
            return
        }

        for alias in desired {
            let port = UInt16(proxyEnabled ? proxyPort : alias.localPort)
            if let existing = registrations[alias.id],
               existing.alias.name == alias.name,
               existing.advertisedPort == port,
               existing.ip == lanIP {
                continue
            }
            await unregister(id: alias.id)
            stopProcess(id: alias.id)
            do {
                try await register(alias: alias, ip: lanIP, port: port)
            } catch {
                // Fallback: detach dns-sd -P (reliable on all macOS builds)
                startProcessFallback(alias: alias, ip: lanIP, port: port)
            }
        }
    }

    func stopAll() async {
        for id in Array(registrations.keys) { await unregister(id: id) }
        for id in Array(processFallback.keys) { stopProcess(id: id) }
    }

    // MARK: - Native DNSSD

    private func register(alias: ServiceAlias, ip: String, port: UInt16) async throws {
        let name = ServiceAlias.sanitizedName(alias.name)
        guard !name.isEmpty else { throw EngineError.invalidName }

        let host = "\(name).local"
        var serviceRef: DNSServiceRef?
        let interfaceIndex: UInt32 = 0 // all applicable; A record uses LAN IP explicitly

        let error = DNSServiceRegister(
            &serviceRef,
            DNSServiceFlags(kDNSServiceFlagsNoAutoRename),
            interfaceIndex,
            name,
            "_http._tcp",
            "local",
            host,
            CFSwapInt16HostToBig(port),
            0,
            nil,
            nil,
            nil
        )

        guard error == kDNSServiceErr_NoError, let serviceRef else {
            throw EngineError.registerFailed(error)
        }

        // Keep the socket serviced so mDNSResponder retains the registration.
        DNSServiceSetDispatchQueue(serviceRef, DispatchQueue.main)

        // Add A record for name.local → LAN IP (proxy/publish target).
        if let packed = Self.ipv4Bytes(ip) {
            var record: DNSRecordRef?
            var bytes = packed
            _ = bytes.withUnsafeMutableBytes { raw in
                DNSServiceAddRecord(
                    serviceRef,
                    &record,
                    0,
                    UInt16(kDNSServiceType_A),
                    UInt16(raw.count),
                    raw.baseAddress,
                    120
                )
            }
        }

        registrations[alias.id] = Registration(
            serviceRef: serviceRef,
            alias: alias,
            advertisedPort: port,
            ip: ip
        )
    }

    private func unregister(id: UUID) async {
        guard let reg = registrations.removeValue(forKey: id) else { return }
        if let ref = reg.serviceRef {
            DNSServiceRefDeallocate(ref)
        }
    }

    // MARK: - Process fallback (dns-sd -P)

    private func startProcessFallback(alias: ServiceAlias, ip: String, port: UInt16) {
        let name = ServiceAlias.sanitizedName(alias.name)
        guard !name.isEmpty else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
        // dns-sd -P Name Type Domain Port Host IP
        process.arguments = [
            "-P", name, "_http._tcp", "local.", "\(port)", "\(name).local", ip,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            processFallback[alias.id] = process
        } catch {
            // ignore — UI will show offline
        }
    }

    private func stopProcess(id: UUID) {
        guard let process = processFallback.removeValue(forKey: id) else { return }
        if process.isRunning {
            process.terminate()
        }
    }

    private static func ipv4Bytes(_ ip: String) -> [UInt8]? {
        var addr = in_addr()
        guard inet_pton(AF_INET, ip, &addr) == 1 else { return nil }
        let value = addr.s_addr // network byte order
        return [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ]
    }
}
