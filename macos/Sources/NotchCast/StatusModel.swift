import SwiftUI
import Combine

@MainActor
final class StatusModel: ObservableObject {
    @Published private(set) var snapshot: StatusSnapshot = .empty
    @Published private(set) var connected = false
    @Published private(set) var expanded = false

    /// Set from the SwiftUI view; keeps the island open while the mouse is on it.
    @Published var hovering = false { didSet { recomputeExpansion() } }

    // MARK: Quick Ask

    enum AskState: Equatable {
        case idle
        case running(prompt: String)
        case answer(String)
        case error(String)
    }

    @Published private(set) var askState: AskState = .idle {
        didSet { updateBodyHeight(); recomputeExpansion() }
    }
    /// Bound to the notch input; a non-empty draft pins the island open.
    @Published var askDraft = "" { didSet { recomputeExpansion() } }
    /// Height the expanded body should adopt (answers need more room).
    @Published private(set) var bodyHeight: CGFloat = Island.expandedBodyHeight

    /// Screen metrics injected by the app delegate so views can hug the notch.
    var notchWidth: CGFloat = 196
    var barHeight: CGFloat = 37

    /// Set by the offscreen asset renderer: AppKit-backed controls (TextField)
    /// don't render there, so views draw static stand-ins instead.
    var renderingStatic = false

    private var client: RelayClient? = RelayClient.fromConfigFile()
    private var pollTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?

    /// The island stays open on its own while something needs the user.
    var pinnedOpen: Bool {
        !snapshot.pending.isEmpty
            || snapshot.liveSessions.contains { $0.state == "attention" }
            || askState != .idle
            || !askDraft.isEmpty
            || transcriptState != .idle
    }

    /// Aggregate state that drives the collapsed indicator dot.
    var aggregateState: AggregateState {
        if !connected { return .offline }
        if !snapshot.pending.isEmpty { return .pending }
        let live = snapshot.liveSessions
        if live.contains(where: { $0.state == "attention" || $0.state == "waiting" }) { return .pending }
        if live.contains(where: { $0.state == "working" }) { return .working }
        if live.isEmpty { return .empty }
        return .idle
    }

    enum AggregateState { case offline, empty, idle, working, pending }

    func start() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    func refresh() async {
        if client == nil { client = RelayClient.fromConfigFile() }
        guard let client else { connected = false; recomputeExpansion(); return }
        do {
            snapshot = try await client.status()
            connected = true
        } catch {
            connected = false
        }
        recomputeExpansion()
    }

    func respond(_ request: PendingRequest, decision: String) {
        Task {
            try? await client?.respond(requestID: request.id, decision: decision)
            snapshot.pending.removeAll { $0.id == request.id }
            await refresh()
        }
    }

    func setRemoteMode(_ on: Bool) {
        Task {
            try? await client?.setRemoteMode(on)
            snapshot.remoteMode = on
            await refresh()
        }
    }

    func submitAsk() {
        let prompt = askDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, askState != .running(prompt: prompt), let client else { return }
        askState = .running(prompt: prompt)
        askDraft = ""
        Task {
            do {
                // Run in the most recent session's project so answers have context.
                let cwd = snapshot.liveSessions.first?.cwd
                let id = try await client.startAsk(prompt: prompt, cwd: cwd)
                await pollAskJob(id: id, prompt: prompt)
            } catch {
                askState = .error(error.localizedDescription)
            }
        }
    }

    private func pollAskJob(id: String, prompt: String) async {
        guard let client else { return }
        do {
            for _ in 0..<150 { // up to ~5 minutes
                try await Task.sleep(for: .seconds(2))
                guard askState == .running(prompt: prompt) else { return } // dismissed
                let job = try await client.askResult(id: id)
                if job.state == "done" {
                    // Headless runs use the CLI's own login, which may be
                    // missing even when the desktop app is signed in.
                    if job.answer.contains("authentication_error") || job.answer.contains("Not logged in") {
                        askState = .error("The claude CLI isn't logged in on this Mac. Run `claude /login` in a terminal once, then ask again.")
                    } else {
                        askState = .answer(job.answer)
                    }
                    return
                }
                if job.state == "error" { askState = .error(job.error); return }
            }
            askState = .error("Timed out waiting for an answer.")
        } catch {
            askState = .error(error.localizedDescription)
        }
    }

    func dismissAsk() {
        askState = .idle
    }

    // MARK: View Session (transcript peek)

    enum TranscriptState: Equatable {
        case idle
        case loading(title: String)
        case loaded(RelayClient.Transcript)
        case error(String)
    }

    @Published private(set) var transcriptState: TranscriptState = .idle {
        didSet { updateBodyHeight(); recomputeExpansion() }
    }

    func viewSession(_ session: SessionStatus) {
        guard let client else { return }
        transcriptState = .loading(title: session.title)
        Task {
            do {
                transcriptState = .loaded(try await client.transcript(sessionID: session.id))
            } catch {
                transcriptState = .error("Couldn't load the transcript — the session may be too new or its file moved.")
            }
        }
    }

    func dismissTranscript() {
        transcriptState = .idle
    }

    private func updateBodyHeight() {
        switch askState {
        case .answer, .error: bodyHeight = 280; return
        default: break
        }
        switch transcriptState {
        case .loaded, .error: bodyHeight = 300
        default: bodyHeight = Island.expandedBodyHeight
        }
    }

    /// Inject state directly — used by the README asset renderer and previews
    /// instead of a live relay.
    func apply(snapshot: StatusSnapshot, connected: Bool) {
        self.snapshot = snapshot
        self.connected = connected
        recomputeExpansion()
    }

    private func recomputeExpansion() {
        if hovering || pinnedOpen {
            collapseTask?.cancel()
            collapseTask = nil
            if !expanded { expanded = true }
        } else if expanded, collapseTask == nil {
            // Small grace period so the island doesn't flicker when the mouse
            // skims past it.
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, !Task.isCancelled else { return }
                if !self.hovering && !self.pinnedOpen { self.expanded = false }
                self.collapseTask = nil
            }
        }
    }
}
