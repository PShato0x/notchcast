import SwiftUI
import WidgetKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var serverURL = ServerConfig.load()?.baseURL.absoluteString ?? "http://192.168.1.10:8787"
    @State private var token = ServerConfig.load()?.token ?? ""
    @State private var testResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Relay server") {
                    TextField("http://<mac-ip>:8787", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Token", text: $token)
                } footer: {
                    Text("Run install.sh on your Mac to get the token, then start the relay with `node server/server.js`. Use your Mac's LAN or Tailscale address.")
                }

                Section {
                    Button("Test connection") { Task { await test() } }
                    if let testResult {
                        Text(testResult).font(.footnote)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if let url = URL(string: serverURL.trimmingCharacters(in: .whitespaces)) {
                            ServerConfig(baseURL: url, token: token.trimmingCharacters(in: .whitespaces)).save()
                            WidgetCenter.shared.reloadAllTimelines()
                            dismiss()
                        }
                    }
                    .disabled(URL(string: serverURL) == nil || token.isEmpty)
                }
            }
        }
    }

    private func test() async {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespaces)) else {
            testResult = "Invalid URL"
            return
        }
        let client = APIClient(config: ServerConfig(baseURL: url, token: token.trimmingCharacters(in: .whitespaces)))
        do {
            let snapshot = try await client.status()
            testResult = "Connected — \(snapshot.sessions.count) session(s), remote approvals \(snapshot.remoteMode ? "on" : "off")."
        } catch {
            testResult = "Failed: \(error.localizedDescription)"
        }
    }
}
