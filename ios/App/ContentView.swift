import SwiftUI
import WidgetKit

@MainActor
final class StatusModel: ObservableObject {
    @Published var snapshot: StatusSnapshot = .empty
    @Published var configured = ServerConfig.load() != nil
    @Published var errorMessage: String?

    private var pollTask: Task<Void, Never>?

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopPolling() { pollTask?.cancel() }

    func refresh() async {
        configured = ServerConfig.load() != nil
        guard let client = try? APIClient.fromSharedDefaults() else { return }
        do {
            snapshot = try await client.status()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func respond(_ request: PendingRequest, decision: String) async {
        guard let client = try? APIClient.fromSharedDefaults() else { return }
        do {
            try await client.respond(requestID: request.id, decision: decision)
            snapshot.pending.removeAll { $0.id == request.id }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }

    func setRemoteMode(_ on: Bool) async {
        guard let client = try? APIClient.fromSharedDefaults() else { return }
        do {
            try await client.setRemoteMode(on)
            snapshot.remoteMode = on
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ContentView: View {
    @StateObject private var model = StatusModel()
    @State private var showSettings = false
    @State private var showQuickAsk = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.cream.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if !model.configured {
                            setupCard
                        } else {
                            if let error = model.errorMessage {
                                Label(error, systemImage: "wifi.exclamationmark")
                                    .font(.footnote)
                                    .foregroundStyle(.red.opacity(0.8))
                            }
                            remoteModeCard
                            ForEach(model.snapshot.pending) { request in
                                PendingRequestCard(request: request) { decision in
                                    Task { await model.respond(request, decision: decision) }
                                }
                            }
                            sessionsSection
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Claude Code")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showQuickAsk = true } label: { Image(systemName: "bubble.left.and.text.bubble.right") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: { Task { await model.refresh() } }) {
                SettingsView()
            }
            .sheet(isPresented: $showQuickAsk) { QuickAskView() }
            .refreshable { await model.refresh() }
            .onAppear { model.startPolling() }
            .onDisappear { model.stopPolling() }
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connect to your Mac")
                .font(.system(.title3, design: .serif).weight(.bold))
            Text("Run the relay server on your Mac (see the project README), then add its URL and token here.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
            Button("Open Settings") { showSettings = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var remoteModeCard: some View {
        Toggle(isOn: Binding(
            get: { model.snapshot.remoteMode },
            set: { on in Task { await model.setRemoteMode(on) } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Remote approvals")
                    .font(.system(.body, design: .serif).weight(.semibold))
                Text("Route permission prompts to this phone")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding()
        .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sessions")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Theme.inkSoft)
            if model.snapshot.sessions.isEmpty {
                Text("No active sessions. Start Claude Code on your Mac.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
            }
            ForEach(model.snapshot.sessions) { session in
                SessionCard(session: session)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PendingRequestCard: View {
    let request: PendingRequest
    let onDecision: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Running Session from your Mac")
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(Theme.inkSoft)
                Text(request.project)
                    .font(.system(.subheadline, design: .serif).weight(.bold))
            }
            Text("Claude requests to \(request.summary)")
                .font(.system(.title3, design: .serif).weight(.bold))
            VStack(spacing: 8) {
                Button("Always allow") { onDecision("always") }
                    .buttonStyle(WidgetActionButtonStyle(background: Theme.terracotta, foreground: Theme.paper))
                Button("Allow once") { onDecision("once") }
                    .buttonStyle(WidgetActionButtonStyle(background: Theme.ink, foreground: Theme.paper))
                Button("Don't allow") { onDecision("deny") }
                    .buttonStyle(WidgetActionButtonStyle(background: Theme.stone, foreground: Theme.ink))
            }
        }
        .padding()
        .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct SessionCard: View {
    let session: SessionStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.title)
                    .font(.system(.body, design: .serif).weight(.bold))
                Spacer()
                Text(session.stateLabel)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.creamDeep, in: Capsule())
                    .foregroundStyle(Theme.inkSoft)
            }
            if !session.lastPrompt.isEmpty {
                Text(session.lastPrompt)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
            }
            if !session.currentTool.isEmpty && session.state == "working" {
                Label(session.currentTool, systemImage: "hammer")
                    .font(.caption)
                    .foregroundStyle(Theme.terracotta)
            }
            if !session.message.isEmpty {
                Text(session.message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
