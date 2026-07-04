import SwiftUI

/// Brand-neutral dark palette: near-black glass, zinc text, one violet accent.
/// (Semantic colors — orange for "needs you", green for idle — stay semantic.)
enum Island {
    static let black = Color(red: 0.043, green: 0.043, blue: 0.051)
    static let paper = Color(red: 0.957, green: 0.957, blue: 0.965)
    static let paperSoft = Color(red: 0.957, green: 0.957, blue: 0.965).opacity(0.55)
    static let accent = Color(red: 0.773, green: 0.443, blue: 0.310)  // #C5714F — the Claude orange
    static let slate = Color(red: 0.20, green: 0.20, blue: 0.23)   // "Allow once"
    static let stone = Color(red: 0.33, green: 0.33, blue: 0.37)   // "Deny"

    static let expandedWidth: CGFloat = 460
    static let expandedBodyHeight: CGFloat = 132
}

/// Custom switch that fits the dark island (the native macOS switch looks
/// foreign here and doesn't render offscreen).
struct IslandToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Capsule()
                .fill(isOn ? Island.accent : Island.stone.opacity(0.5))
                .frame(width: 30, height: 17)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(Island.paper).frame(width: 13, height: 13).padding(2)
                }
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.2), value: isOn)
    }
}

struct IslandButtonStyle: ButtonStyle {
    var background: Color
    var foreground: Color = Island.paper

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12).weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(background, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .foregroundStyle(foreground)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct IslandView: View {
    @ObservedObject var model: StatusModel

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        VStack(spacing: 0) {
            collapsedBar
            if model.expanded {
                expandedBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: model.expanded ? Island.expandedWidth : model.notchWidth + 100)
        .background(
            UnevenRoundedRectangle(
                cornerRadii: .init(bottomLeading: model.expanded ? 22 : 12,
                                   bottomTrailing: model.expanded ? 22 : 12),
                style: .continuous
            )
            .fill(Island.black)
            .shadow(color: .black.opacity(model.expanded ? 0.45 : 0.25), radius: model.expanded ? 14 : 5, y: 4)
        )
        .onHover { model.hovering = $0 }
        .animation(.spring(duration: 0.32, bounce: 0.18), value: model.expanded)
    }

    /// The strip that hugs the physical notch. The middle stays empty (it sits
    /// behind the notch itself); indicators live on the wings.
    private var collapsedBar: some View {
        HStack {
            Image(systemName: "sparkle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Island.accent)
                .padding(.leading, 16)
            Spacer()
            StatusDot(state: model.aggregateState)
                .padding(.trailing, 18)
        }
        .frame(height: model.barHeight)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            switch model.askState {
            case .running(let prompt):
                askRunningSection(prompt)
            case .answer(let answer):
                askResultSection(answer, isError: false)
            case .error(let message):
                askResultSection(message, isError: true)
            case .idle:
                if let request = model.snapshot.pending.first {
                    requestSection(request, extra: model.snapshot.pending.count - 1)
                } else if !model.connected {
                    offlineSection
                } else {
                    sessionsSection
                    Spacer(minLength: 0)
                    askInputRow
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .frame(width: Island.expandedWidth, height: model.bodyHeight, alignment: .topLeading)
    }

    // MARK: Quick Ask

    private var askInputRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Island.accent)
            if model.renderingStatic {
                Text("Ask anything…")
                    .font(.system(size: 12))
                    .foregroundStyle(Island.paperSoft)
                Spacer(minLength: 0)
            } else {
                TextField("Ask anything…", text: $model.askDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Island.paper)
                    .tint(Island.accent)
                    .disableAutocorrection(true)
                    .onSubmit { model.submitAsk() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Island.slate.opacity(0.7), in: Capsule())
    }

    private func askRunningSection(_ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prompt)
                .font(.system(size: 11))
                .foregroundStyle(Island.paperSoft)
                .lineLimit(2)
            HStack(spacing: 8) {
                StatusDot(state: .working)
                Text("Thinking…")
                    .font(.system(size: 14).weight(.semibold))
                    .foregroundStyle(Island.paper)
                Spacer()
                Button("Cancel") { model.dismissAsk() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Island.paperSoft)
            }
        }
    }

    private func askResultSection(_ text: String, isError: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(isError ? "Couldn't answer" : "Answer",
                      systemImage: isError ? "exclamationmark.triangle" : "sparkle")
                    .font(.system(size: 11).weight(.semibold))
                    .foregroundStyle(isError ? .orange : Island.accent)
                Spacer()
                Button { model.dismissAsk() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Island.paperSoft)
                }
                .buttonStyle(.plain)
            }
            ScrollView {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Island.paper)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 10, weight: .semibold))
            Text("Code")
                .font(.system(size: 12).weight(.semibold))
            Spacer()
            if model.snapshot.updateAvailable == true {
                Text("↑ Update available")
                    .font(.system(size: 10).weight(.semibold))
                    .foregroundStyle(Island.accent)
                    .help("Run: notchcast update")
                    .padding(.trailing, 4)
            }
            HStack(spacing: 6) {
                Text("Remote approvals")
                    .font(.system(size: 10))
                IslandToggle(isOn: Binding(
                    get: { model.snapshot.remoteMode },
                    set: { model.setRemoteMode($0) }
                ))
            }
        }
        .foregroundStyle(Island.paperSoft)
    }

    private func requestSection(_ request: PendingRequest, extra: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Running session · \(request.project)")
                    .font(.system(size: 10))
                    .foregroundStyle(Island.paperSoft)
                Text("Requests to \(request.summary)")
                    .font(.system(size: 15).weight(.bold))
                    .foregroundStyle(Island.paper)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            HStack(spacing: 8) {
                Button("Always allow") { model.respond(request, decision: "always") }
                    .buttonStyle(IslandButtonStyle(background: Island.accent))
                Button("Allow once") { model.respond(request, decision: "once") }
                    .buttonStyle(IslandButtonStyle(background: Island.slate))
                Button("Deny") { model.respond(request, decision: "deny") }
                    .buttonStyle(IslandButtonStyle(background: Island.stone))
            }
            .buttonStyle(.plain)
            if extra > 0 {
                Text("+\(extra) more waiting")
                    .font(.system(size: 10))
                    .foregroundStyle(Island.paperSoft)
            }
        }
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let live = Array(model.snapshot.liveSessions.prefix(2))
            if live.isEmpty {
                Text("No active sessions")
                    .font(.system(size: 14).weight(.semibold))
                    .foregroundStyle(Island.paperSoft)
                Text("Start Claude Code in a terminal — sessions appear here.")
                    .font(.system(size: 11))
                    .foregroundStyle(Island.paperSoft)
            } else {
                ForEach(live) { session in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(session.state == "working" ? Island.accent : Island.paperSoft)
                                .frame(width: 6, height: 6)
                            Text(session.title)
                                .font(.system(size: 13).weight(.bold))
                                .foregroundStyle(Island.paper)
                                .lineLimit(1)
                            Spacer()
                            Text(session.state == "working" && !session.currentTool.isEmpty
                                 ? "\(session.stateLabel) · \(session.currentTool)"
                                 : session.stateLabel)
                                .font(.system(size: 10))
                                .foregroundStyle(Island.paperSoft)
                        }
                        if !session.lastPrompt.isEmpty {
                            Text(session.lastPrompt)
                                .font(.system(size: 11))
                                .foregroundStyle(Island.paperSoft)
                                .lineLimit(1)
                                .padding(.leading, 12)
                        }
                    }
                }
            }
        }
    }

    private var offlineSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Relay offline")
                .font(.system(size: 14).weight(.semibold))
                .foregroundStyle(Island.paper)
            Text("Run `node server/server.js` (and install.sh once) to connect.")
                .font(.system(size: 11))
                .foregroundStyle(Island.paperSoft)
        }
    }
}

/// The collapsed indicator: gray when offline, dim when idle, terracotta and
/// pulsing while Claude works, orange when a request is waiting.
struct StatusDot: View {
    let state: StatusModel.AggregateState
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(shouldPulse ? (pulsing ? 0.35 : 1) : 1)
            .animation(shouldPulse ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
                       value: pulsing)
            .task { pulsing = true } // off the initial render pass, so offscreen snapshots get full opacity
            .id(state)
    }

    private var shouldPulse: Bool {
        switch state {
        case .working, .pending: return true
        default: return false
        }
    }

    private var color: Color {
        switch state {
        case .offline: return .gray.opacity(0.5)
        case .empty: return Island.paperSoft.opacity(0.4)
        case .idle: return .green.opacity(0.7)
        case .working: return Island.accent
        case .pending: return .orange
        }
    }
}
