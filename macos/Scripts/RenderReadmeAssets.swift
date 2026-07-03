// Renders the README screenshots straight from the real SwiftUI views, so the
// docs never drift from the actual UI. Not part of the app target (it has its
// own @main) — compiled and run by `build.sh --readme-assets`.

import AppKit
import SwiftUI

@main
enum RenderReadmeAssets {
    @MainActor
    static func main() {
        let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

        let now = Date.now.timeIntervalSince1970 * 1000
        let session = SessionStatus(
            id: "demo", title: "Coding Project V.1", cwd: "~/code/project",
            state: "working", lastPrompt: "Refactor the auth flow and add tests",
            currentTool: "Bash", message: "", updatedAt: now
        )
        let request = PendingRequest(
            id: "req1", sessionId: "demo", project: "Coding Project V.1", cwd: "~/code/project",
            tool: "Bash", signature: "Bash:npm", summary: "run `npm test`", createdAt: now
        )

        // Expanded, with a pending permission request (auto-pins open).
        let pendingModel = StatusModel()
        pendingModel.apply(
            snapshot: StatusSnapshot(remoteMode: true, serverTime: now,
                                     sessions: [session], pending: [request], rules: []),
            connected: true
        )
        render(model: pendingModel, to: "\(outDir)/island-request.png")

        // Expanded on hover, just showing session status.
        let statusModel = StatusModel()
        statusModel.apply(
            snapshot: StatusSnapshot(remoteMode: true, serverTime: now,
                                     sessions: [session], pending: [], rules: []),
            connected: true
        )
        statusModel.hovering = true
        render(model: statusModel, to: "\(outDir)/island-status.png")

        // Collapsed strip with the working pulse.
        let collapsedModel = StatusModel()
        collapsedModel.apply(
            snapshot: StatusSnapshot(remoteMode: true, serverTime: now,
                                     sessions: [session], pending: [], rules: []),
            connected: true
        )
        render(model: collapsedModel, to: "\(outDir)/island-collapsed.png")
    }

    @MainActor
    static func render(model: StatusModel, to path: String) {
        let width = model.expanded ? Island.expandedWidth : model.notchWidth + 100
        let height = model.expanded
            ? model.barHeight + Island.expandedBodyHeight
            : model.barHeight + 8
        let view = IslandView(model: model)
            .frame(width: width, height: height)
            .padding(24) // room for the drop shadow

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.isOpaque = false

        guard
            let image = renderer.nsImage,
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else {
            fputs("failed to render \(path)\n", stderr)
            exit(1)
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        } catch {
            fputs("failed to write \(path): \(error)\n", stderr)
            exit(1)
        }
    }
}
