import WidgetKit
import SwiftUI

// MARK: - Timeline

struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: StatusSnapshot
    let configured: Bool
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: .now, snapshot: .preview, configured: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        if context.isPreview {
            completion(StatusEntry(date: .now, snapshot: .preview, configured: true))
            return
        }
        Task { completion(await fetchEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        Task {
            let entry = await fetchEntry()
            // Poll faster while something is pending or running; WidgetKit
            // still throttles background refreshes, so treat this as best-effort.
            let active = !entry.snapshot.pending.isEmpty
                || entry.snapshot.sessions.contains { $0.state == "working" || $0.state == "waiting" }
            let next = Calendar.current.date(byAdding: .minute, value: active ? 2 : 15, to: .now)!
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func fetchEntry() async -> StatusEntry {
        guard let client = try? APIClient.fromSharedDefaults() else {
            return StatusEntry(date: .now, snapshot: .empty, configured: false)
        }
        let snapshot = (try? await client.status()) ?? .empty
        return StatusEntry(date: .now, snapshot: snapshot, configured: true)
    }
}

// MARK: - Views

struct ClaudeStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    var body: some View {
        Group {
            if !entry.configured {
                SetupNeededView()
            } else if let request = entry.snapshot.pending.first {
                switch family {
                case .systemSmall: SmallRequestView(request: request)
                default: RequestView(request: request, extraPending: entry.snapshot.pending.count - 1)
                }
            } else {
                StatusOverviewView(snapshot: entry.snapshot, compact: family == .systemSmall)
            }
        }
        .containerBackground(for: .widget) { Theme.cream }
        .widgetURL(URL(string: "claudewidget://open"))
    }
}

struct HeaderView: View {
    var trailing: String = "View Session"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "asterisk")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.terracotta)
            Rectangle().fill(Theme.inkSoft.opacity(0.3)).frame(width: 1, height: 16)
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 11, weight: .semibold))
            Text("Code")
                .font(.system(.footnote, design: .serif).weight(.semibold))
            Spacer()
            HStack(spacing: 2) {
                Text(trailing)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
            }
            .font(.system(.caption2, design: .serif))
            .foregroundStyle(Theme.inkSoft)
        }
        .foregroundStyle(Theme.ink)
    }
}

/// Medium / large: full three-button card, like the mockups.
struct RequestView: View {
    let request: PendingRequest
    var extraPending: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderView()
            VStack(alignment: .leading, spacing: 1) {
                Text("Running Session from your Mac")
                    .font(.system(.caption2, design: .serif))
                    .foregroundStyle(Theme.inkSoft)
                Text(request.project)
                    .font(.system(.caption, design: .serif).weight(.bold))
                    .foregroundStyle(Theme.ink)
            }
            Text("Claude requests to \(request.summary)")
                .font(.system(.subheadline, design: .serif).weight(.bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            HStack(spacing: 8) {
                Button(intent: RespondIntent(requestID: request.id, decision: .always)) {
                    Text("Always allow")
                }
                .buttonStyle(WidgetActionButtonStyle(background: Theme.terracotta, foreground: Theme.paper))
                Button(intent: RespondIntent(requestID: request.id, decision: .once)) {
                    Text("Allow once")
                }
                .buttonStyle(WidgetActionButtonStyle(background: Theme.ink, foreground: Theme.paper))
                Button(intent: RespondIntent(requestID: request.id, decision: .deny)) {
                    Text("Deny")
                }
                .buttonStyle(WidgetActionButtonStyle(background: Theme.stone, foreground: Theme.ink))
            }
            if extraPending > 0 {
                Text("+\(extraPending) more waiting")
                    .font(.system(.caption2, design: .serif))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }
}

/// Small family: compact card with a single "Allow once" action.
struct SmallRequestView: View {
    let request: PendingRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(request.project)
                    .font(.system(.caption2, design: .serif))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Text("Claude requests to \(request.summary)")
                .font(.system(.footnote, design: .serif).weight(.bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(3)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
            Button(intent: RespondIntent(requestID: request.id, decision: .once)) {
                HStack(spacing: 4) {
                    Text("Allow once")
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
            }
            .buttonStyle(WidgetActionButtonStyle(background: Theme.ink, foreground: Theme.paper))
        }
    }
}

/// No pending request: show what the sessions are doing.
struct StatusOverviewView: View {
    let snapshot: StatusSnapshot
    let compact: Bool

    private var sessions: [SessionStatus] { Array(snapshot.sessions.prefix(compact ? 1 : 3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            if !compact { HeaderView() }
            if sessions.isEmpty {
                Spacer()
                Text("No active sessions")
                    .font(.system(.subheadline, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                Text("Start Claude Code on your Mac")
                    .font(.system(.caption2, design: .serif))
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
            } else {
                ForEach(sessions) { session in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(color(for: session.state))
                                .frame(width: 7, height: 7)
                            Text(session.title)
                                .font(.system(.footnote, design: .serif).weight(.bold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Spacer()
                            Text(session.stateLabel)
                                .font(.system(.caption2, design: .serif))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        if !session.lastPrompt.isEmpty {
                            Text(session.lastPrompt)
                                .font(.system(.caption2, design: .serif))
                                .foregroundStyle(Theme.inkSoft)
                                .lineLimit(compact ? 3 : 1)
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: snapshot.remoteMode ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                        .font(.system(size: 9))
                    Text(snapshot.remoteMode ? "Remote approvals on" : "Remote approvals off")
                }
                .font(.system(.caption2, design: .serif))
                .foregroundStyle(snapshot.remoteMode ? Theme.terracotta : Theme.inkSoft)
            }
        }
    }

    private func color(for state: String) -> Color {
        switch state {
        case "working": return Theme.terracotta
        case "waiting", "attention": return .orange
        case "idle": return .green.opacity(0.7)
        default: return Theme.inkSoft
        }
    }
}

struct SetupNeededView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HeaderView(trailing: "Open App")
            Spacer()
            Text("Set up your relay")
                .font(.system(.subheadline, design: .serif).weight(.bold))
                .foregroundStyle(Theme.ink)
            Text("Add the server URL and token in the app.")
                .font(.system(.caption2, design: .serif))
                .foregroundStyle(Theme.inkSoft)
            Spacer()
        }
    }
}

// MARK: - Widget definition

struct ClaudeStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeStatusWidget", provider: StatusProvider()) { entry in
            ClaudeStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Code")
        .description("See what Claude is working on and approve requests from your home screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct ClaudeWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClaudeStatusWidget()
    }
}

// MARK: - Preview data

extension StatusSnapshot {
    static let preview = StatusSnapshot(
        remoteMode: true,
        serverTime: Date.now.timeIntervalSince1970 * 1000,
        sessions: [
            SessionStatus(
                id: "abc", title: "Coding Project V.1", cwd: "~/code/project",
                state: "waiting", lastPrompt: "Refactor the auth flow", currentTool: "Bash",
                message: "", updatedAt: Date.now.timeIntervalSince1970 * 1000
            )
        ],
        pending: [
            PendingRequest(
                id: "req1", sessionId: "abc", project: "Coding Project V.1", cwd: "~/code/project",
                tool: "Bash", signature: "Bash:npm", summary: "run `npm test`",
                createdAt: Date.now.timeIntervalSince1970 * 1000
            )
        ],
        rules: []
    )
}
