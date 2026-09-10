import Foundation

struct ListeningPort: Identifiable, Hashable, Sendable {
    var id: Int { port }
    let port: Int
    let processName: String
    let address: String

    var label: String {
        "\(port) · \(processName)"
    }

    var suggestedAliasName: String {
        ServiceAlias.sanitizedName(processName)
    }
}

enum PortDiscovery {
    /// Discover TCP listen ports on this Mac via `lsof`.
    static func scanListeningPorts() async -> [ListeningPort] {
        await Task.detached(priority: .userInitiated) {
            Self.runLsof()
        }.value
    }

    private static func runLsof() -> [ListeningPort] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return parse(text)
    }

    private static func parse(_ text: String) -> [ListeningPort] {
        var best: [Int: ListeningPort] = [:]

        for line in text.split(separator: "\n").dropFirst() {
            // COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            // node 123 user 23u IPv4 … TCP *:8080 (LISTEN)
            // node 123 user 23u IPv4 … TCP 127.0.0.1:8080 (LISTEN)
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 9 else { continue }

            let command = parts[0]
                .replacingOccurrences(of: #"\x20"#, with: " ")
                .replacingOccurrences(of: #"\\ "#, with: " ")
            let nameField = parts.last { $0.contains(":") } ?? parts[parts.count - 2]
            guard let port = extractPort(from: nameField) else { continue }

            // Skip Lantern's own control listener and privileged system noise under 50 is rare for apps;
            // still allow common web ports.
            if shouldSkip(process: command, port: port) { continue }

            let address = nameField
                .replacingOccurrences(of: "(LISTEN)", with: "")
                .trimmingCharacters(in: .whitespaces)

            let displayName = friendlyProcessName(command)
            let candidate = ListeningPort(port: port, processName: displayName, address: address)

            // Prefer non-loopback bindings when both exist for the same port.
            if let existing = best[port] {
                let candidateIsWider = !address.contains("127.0.0.1") && !address.lowercased().contains("[::1]")
                let existingIsLoopback = existing.address.contains("127.0.0.1") || existing.address.lowercased().contains("[::1]")
                if candidateIsWider && existingIsLoopback {
                    best[port] = candidate
                }
            } else {
                best[port] = candidate
            }
        }

        return best.values.sorted { lhs, rhs in
            if lhs.port != rhs.port { return lhs.port < rhs.port }
            return lhs.processName < rhs.processName
        }
    }

    private static func extractPort(from token: String) -> Int? {
        // *:8080 / 127.0.0.1:8080 / [::1]:8080
        guard let colon = token.lastIndex(of: ":") else { return nil }
        var portPart = String(token[token.index(after: colon)...])
        if let space = portPart.firstIndex(where: { $0 == " " || $0 == "(" }) {
            portPart = String(portPart[..<space])
        }
        return Int(portPart)
    }

    private static func shouldSkip(process: String, port: Int) -> Bool {
        let lowered = process.lowercased()
        if lowered.hasPrefix("lantern") { return true }
        if port == 19_247 { return true }
        // Very high ephemeral listeners that are usually internal IPC
        if port >= 49_000 && (lowered.contains("rapportd") || lowered.contains("cursorsan")) {
            return true
        }
        return false
    }

    private static func friendlyProcessName(_ raw: String) -> String {
        var name = raw
        if name.hasSuffix("\\x20") {
            name = String(name.dropLast(4))
        }
        name = name.replacingOccurrences(of: #"\x20"#, with: " ")
        // Drop path-like suffixes / truncate helper names
        if let slash = name.lastIndex(of: "/") {
            name = String(name[name.index(after: slash)...])
        }
        return name.isEmpty ? "Unknown" : name
    }
}
