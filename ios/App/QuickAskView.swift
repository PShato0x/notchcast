import SwiftUI

/// Quick Ask: sends a one-shot prompt to the Mac, which runs `claude -p`
/// headlessly and returns the answer.
struct QuickAskView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var answer: String?
    @State private var errorMessage: String?
    @State private var isRunning = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.cream.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Ask Claude anything…", text: $prompt, axis: .vertical)
                        .lineLimit(3...6)
                        .padding()
                        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .disabled(isRunning)

                    Button {
                        Task { await run() }
                    } label: {
                        if isRunning {
                            HStack(spacing: 8) { ProgressView(); Text("Thinking…") }.frame(maxWidth: .infinity)
                        } else {
                            Text("Ask").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(WidgetActionButtonStyle(background: Theme.terracotta, foreground: Theme.paper))
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRunning)

                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red.opacity(0.8))
                    }

                    if let answer {
                        ScrollView {
                            Text(answer)
                                .font(.system(.body, design: .serif))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding()
                        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Quick Ask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
        }
    }

    private func run() async {
        errorMessage = nil
        answer = nil
        isRunning = true
        defer { isRunning = false }
        do {
            let client = try APIClient.fromSharedDefaults()
            let id = try await client.startAsk(prompt: prompt)
            // Poll until the headless run finishes (up to ~3 minutes).
            for _ in 0..<90 {
                try await Task.sleep(for: .seconds(2))
                let job = try await client.askResult(id: id)
                if job.state == "done" { answer = job.answer; return }
                if job.state == "error" { errorMessage = job.error; return }
            }
            errorMessage = "Timed out waiting for an answer."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
