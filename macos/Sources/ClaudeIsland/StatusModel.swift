import SwiftUI
import Combine

@MainActor
final class StatusModel: ObservableObject {
    @Published private(set) var snapshot: StatusSnapshot = .empty
    @Published private(set) var connected = false
    @Published private(set) var expanded = false

    /// Set from the SwiftUI view; keeps the island open while the mouse is on it.
    @Published var hovering = false { didSet { recomputeExpansion() } }

    /// Screen metrics injected by the app delegate so views can hug the notch.
    var notchWidth: CGFloat = 196
    var barHeight: CGFloat = 37

    private var client: RelayClient? = RelayClient.fromConfigFile()
    private var pollTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?

    /// The island stays open on its own while something needs the user.
    var pinnedOpen: Bool {
        !snapshot.pending.isEmpty || snapshot.liveSessions.contains { $0.state == "attention" }
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
