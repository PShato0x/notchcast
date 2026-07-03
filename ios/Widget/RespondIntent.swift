import AppIntents
import WidgetKit

enum PermissionDecision: String, AppEnum {
    case always, once, deny

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Decision")
    static let caseDisplayRepresentations: [PermissionDecision: DisplayRepresentation] = [
        .always: "Always allow",
        .once: "Allow once",
        .deny: "Don't allow",
    ]
}

/// Fired by the interactive widget buttons. Answers a pending permission
/// request on the relay, then reloads the widget timeline.
struct RespondIntent: AppIntent {
    static let title: LocalizedStringResource = "Respond to Claude"
    static let description = IntentDescription("Approve or deny a pending Claude Code permission request.")

    @Parameter(title: "Request ID")
    var requestID: String

    @Parameter(title: "Decision")
    var decision: PermissionDecision

    init() {}

    init(requestID: String, decision: PermissionDecision) {
        self.requestID = requestID
        self.decision = decision
    }

    func perform() async throws -> some IntentResult {
        let client = try APIClient.fromSharedDefaults()
        try await client.respond(requestID: requestID, decision: decision.rawValue)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Toggle remote approvals from the widget without opening the app.
struct ToggleRemoteModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Remote Approvals"

    @Parameter(title: "Enabled")
    var enabled: Bool

    init() {}
    init(enabled: Bool) { self.enabled = enabled }

    func perform() async throws -> some IntentResult {
        let client = try APIClient.fromSharedDefaults()
        try await client.setRemoteMode(enabled)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
