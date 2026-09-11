import Foundation

enum LanternPaths {
    static var supportDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Lantern", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var stateFile: URL {
        supportDirectory.appendingPathComponent("state.json")
    }

    static var logFile: URL {
        supportDirectory.appendingPathComponent("logs.jsonl")
    }

    static var tokenFile: URL {
        supportDirectory.appendingPathComponent("control-token")
    }
}

enum ControlToken {
    static let headerName = "X-Lantern-Token"
    private static let lock = NSLock()

    static func current() -> String {
        lock.lock()
        defer { lock.unlock() }
        let url = LanternPaths.tokenFile
        if let existing = try? String(contentsOf: url, encoding: .utf8) {
            let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        try? token.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return token
    }
}

struct ControlResponse {
    var status: Int
    var payload: [String: Any]

    static func ok(_ payload: [String: Any] = ["ok": true]) -> ControlResponse {
        ControlResponse(status: 200, payload: payload)
    }

    static func error(_ status: Int, _ message: String) -> ControlResponse {
        ControlResponse(status: status, payload: ["ok": false, "error": message])
    }

    var reason: String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 409: return "Conflict"
        default: return "Error"
        }
    }
}

enum LanternLinks {
    static let repo = URL(string: "https://github.com/sinhong2011/lantern")!
    static let author = URL(string: "https://github.com/sinhong2011")!
    static let authorName = "sinhong"
    static let authorHandle = "sinhong2011"
    static let repoLabel = "github.com/sinhong2011/lantern"
}
