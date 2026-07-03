import Foundation

/// Server connection settings shared between the app and the widget via the
/// App Group. (v1 stores the token in shared UserDefaults; moving it to a
/// shared Keychain item is on the roadmap.)
struct ServerConfig: Equatable {
    var baseURL: URL
    var token: String

    static func load() -> ServerConfig? {
        let defaults = AppGroup.defaults
        guard
            let raw = defaults.string(forKey: "serverURL"),
            let url = URL(string: raw),
            let token = defaults.string(forKey: "serverToken"),
            !token.isEmpty
        else { return nil }
        return ServerConfig(baseURL: url, token: token)
    }

    func save() {
        let defaults = AppGroup.defaults
        defaults.set(baseURL.absoluteString, forKey: "serverURL")
        defaults.set(token, forKey: "serverToken")
    }
}

enum APIError: LocalizedError {
    case notConfigured
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Set the server URL and token in the app first."
        case .http(let code): return "Server returned HTTP \(code)."
        }
    }
}

struct APIClient {
    var config: ServerConfig

    static func fromSharedDefaults() throws -> APIClient {
        guard let config = ServerConfig.load() else { throw APIError.notConfigured }
        return APIClient(config: config)
    }

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        var req = URLRequest(url: config.baseURL.appendingPathComponent(path), timeoutInterval: 10)
        req.httpMethod = method
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode)
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

    func clearRules() async throws {
        _ = try await request("rules/clear", method: "POST", body: [:])
    }

    func startAsk(prompt: String) async throws -> String {
        struct Started: Codable { var id: String }
        let data = try await request("ask", method: "POST", body: ["prompt": prompt])
        return try JSONDecoder().decode(Started.self, from: data).id
    }

    func askResult(id: String) async throws -> AskJob {
        try JSONDecoder().decode(AskJob.self, from: try await request("ask/\(id)"))
    }
}
