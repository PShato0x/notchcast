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

        renderGifFrames(outDir: outDir, session: session, request: request, now: now)
    }

    /// Renders the README demo animation as numbered frames (assembled into a
    /// GIF by build.sh). Synthetic on purpose: no screen capture, nothing from
    /// the maintainer's desktop, and it always matches the current theme.
    @MainActor
    static func renderGifFrames(outDir: String, session: SessionStatus, request: PendingRequest, now: Double) {
        let framesDir = "\(outDir)/gif-frames"
        try? FileManager.default.removeItem(atPath: framesDir)
        try! FileManager.default.createDirectory(atPath: framesDir, withIntermediateDirectories: true)

        let idle = StatusModel()
        idle.apply(
            snapshot: StatusSnapshot(remoteMode: true, serverTime: now,
                                     sessions: [session], pending: [], rules: []),
            connected: true
        )

        let asking = StatusModel()
        asking.apply(
            snapshot: StatusSnapshot(remoteMode: true, serverTime: now,
                                     sessions: [session], pending: [request], rules: []),
            connected: true
        )

        // Post-approval: expanded session overview (as if still hovered).
        let after = StatusModel()
        after.apply(
            snapshot: StatusSnapshot(remoteMode: true, serverTime: now,
                                     sessions: [session], pending: [], rules: []),
            connected: true
        )
        after.hovering = true

        var index = 0
        let canvasW: CGFloat = 560, canvasH: CGFloat = 195
        func emit(_ model: StatusModel, maskHeight: CGFloat? = nil, times: Int = 1) {
            let island = IslandView(model: model)
                .frame(width: canvasW, height: canvasH, alignment: .top)
                .mask(alignment: .top) {
                    UnevenRoundedRectangle(
                        cornerRadii: .init(bottomLeading: 22, bottomTrailing: 22),
                        style: .continuous
                    )
                    .frame(width: canvasW, height: maskHeight ?? canvasH)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            // A believable Mac top-of-screen: wallpaper gradient + menu bar,
            // so collapsed frames read as "the notch area", not an empty box.
            let composed = ZStack(alignment: .top) {
                LinearGradient(
                    colors: [Color(red: 0.245, green: 0.235, blue: 0.310),
                             Color(red: 0.135, green: 0.125, blue: 0.180)],
                    startPoint: .top, endPoint: .bottom
                )
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        Text("\u{F8FF}").font(.system(size: 12))
                        Text("Finder").font(.system(size: 11, weight: .semibold))
                        Text("File").font(.system(size: 11))
                        Text("Edit").font(.system(size: 11))
                        Text("View").font(.system(size: 11))
                        Spacer()
                        Image(systemName: "wifi").font(.system(size: 10))
                        Image(systemName: "battery.75percent").font(.system(size: 11))
                        Text("Fri 9:41 AM").font(.system(size: 11))
                    }
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 14)
                    .frame(height: model.barHeight)
                    .background(.black.opacity(0.18))
                    Spacer()
                }
                island
            }
            .frame(width: canvasW, height: canvasH)

            let renderer = ImageRenderer(content: composed)
            renderer.scale = 1
            renderer.isOpaque = true
            guard
                let image = renderer.nsImage,
                let tiff = image.tiffRepresentation,
                let rep = NSBitmapImageRep(data: tiff),
                let png = rep.representation(using: .png, properties: [:])
            else { fputs("failed gif frame \(index)\n", stderr); exit(1) }
            for _ in 0..<times {
                index += 1
                try? png.write(to: URL(fileURLWithPath: String(format: "%@/f%03d.png", framesDir, index)))
            }
        }

        emit(idle, times: 7)                                   // collapsed, agent working
        for h in [70, 115, 150, 175] { emit(asking, maskHeight: CGFloat(h)) }  // island grows
        emit(asking, times: 15)                                // request card holds
        emit(after, times: 8)                                  // approved -> session overview
        for h in [140, 85] { emit(after, maskHeight: CGFloat(h)) }             // shrink away
        emit(idle, times: 7)                                   // back to collapsed
        print("wrote \(index) gif frames to \(framesDir)")
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
