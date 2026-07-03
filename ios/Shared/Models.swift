import Foundation

/// Change this to your own App Group identifier (must match the entitlements
/// of BOTH the app and the widget extension).
enum AppGroup {
    static let identifier = "group.com.yourname.notchai"
    static var defaults: UserDefaults { UserDefaults(suiteName: identifier) ?? .standard }
}

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

    static let empty = StatusSnapshot(remoteMode: false, serverTime: 0, sessions: [], pending: [], rules: [])
}

struct AskJob: Codable, Identifiable {
    var id: String
    var prompt: String
    var state: String       // running | done | error
    var answer: String
    var error: String
    var createdAt: Double
}
