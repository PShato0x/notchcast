import Foundation

// MARK: - Models (mirror of server/server.js /status payload)

struct SessionStatus: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var cwd: String
    var state: String       // working | waiting | attention | idle | ended
    var lastPrompt: String
    var currentTool: String
    var message: String
    var updatedAt: Double

    var stateLabel: String {
        switch state {
        case "working": return "Working"
        case "waiting": return "Waiting for approval"
        case "attention": return "Needs attention"
        case "idle": return "Idle"
        case "ended": return "Ended"
        default: return state.capitalized
        }
    }
}

struct PendingRequest: Codable, Identifiable, Hashable {
    var id: String
    var sessionId: String
    var project: String
    var cwd: String
    var tool: String
    var signature: String
    var summary: String     // e.g. "run `npm test`"
    var createdAt: Double
}

struct StatusSnapshot: Codable {
    var remoteMode: Bool
    var serverTime: Double
    var sessions: [SessionStatus]
    var pending: [PendingRequest]
    var rules: [String]
    var version: String?
    var latestVersion: String?
    var updateAvailable: Bool?

    static let empty = StatusSnapshot(remoteMode: false, serverTime: 0, sessions: [], pending: [], rules: [])

    /// Sessions still worth showing (active or recently finished).
    var liveSessions: [SessionStatus] {
        sessions.filter { $0.state != "ended" }
    }
}

// MARK: - Client

enum RelayError: LocalizedError {
    case notConfigured
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "No relay config — run install.sh first."
        case .http(let code): return "Relay returned HTTP \(code)."
        }
    }
}

/// Talks to the local relay (server/server.js). Reads the token and port from
/// ~/.notchcast/config.json — the same file install.sh creates, so the
/// island needs zero extra setup.
struct RelayClient {
    var baseURL: URL
    var token: String

    static func fromConfigFile() -> RelayClient? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".notchcast/config.json")
        guard
            let data = try? Data(contentsOf: path),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = json["token"] as? String, !token.isEmpty
        else { return nil }
        let port = (json["port"] as? Int) ?? 8787
        return RelayClient(baseURL: URL(string: "http://127.0.0.1:\(port)")!, token: token)
    }

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: 5)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RelayError.http(http.statusCode)
        }
        return data
    }

    func status() async throws -> StatusSnapshot {
        try JSONDecoder().decode(StatusSnapshot.self, from: try await request("status"))
    }

    /// decision: "always" | "once" | "deny"
    func respond(requestID: String, decision: String) async throws {
        _ = try await request("respond", method: "POST", body: ["id": requestID, "decision": decision])
    }

    func setRemoteMode(_ on: Bool) async throws {
        _ = try await request("mode", method: "POST", body: ["remoteMode": on])
    }

    // MARK: Quick Ask (headless `claude -p` runs on the relay)

    struct AskJob: Codable {
        var id: String
        var prompt: String
        var state: String   // running | done | error
        var answer: String
        var error: String
    }

    func startAsk(prompt: String, cwd: String?) async throws -> String {
        struct Started: Codable { var id: String }
        var body: [String: Any] = ["prompt": prompt]
        if let cwd, !cwd.isEmpty { body["cwd"] = cwd }
        let data = try await request("ask", method: "POST", body: body)
        return try JSONDecoder().decode(Started.self, from: data).id
    }

    func askResult(id: String) async throws -> AskJob {
        try JSONDecoder().decode(AskJob.self, from: try await request("ask/\(id)"))
    }

    // MARK: Session transcript peek

    struct TranscriptEntry: Codable, Hashable, Identifiable {
        var role: String    // "user" | "assistant"
        var text: String
        var id: Int { hashValue }
    }

    struct Transcript: Codable, Equatable {
        var title: String
        var entries: [TranscriptEntry]
    }

    func transcript(sessionID: String) async throws -> Transcript {
        try JSONDecoder().decode(Transcript.self, from: try await request("session/\(sessionID)/transcript"))
    }
}
