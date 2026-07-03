import AppKit
import SwiftUI
import Combine

/// Borderless, non-activating panel that floats over the menu bar area.
/// Clicking its buttons never steals focus from the app you're working in.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel!
    private var model: StatusModel!
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon

        model = StatusModel()
        let metrics = screenMetrics()
        model.notchWidth = metrics.notchWidth
        model.barHeight = metrics.barHeight
        model.start()

        setUpPanel()
        setUpStatusItem()

        model.$expanded
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] expanded in self?.layoutPanel(expanded: expanded) }
            .store(in: &cancellables)

        // Re-anchor when displays change (lid open/close, external monitor).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let m = self.screenMetrics()
                self.model.notchWidth = m.notchWidth
                self.model.barHeight = m.barHeight
                self.layoutPanel(expanded: self.model.expanded)
            }
        }

        layoutPanel(expanded: false)
        panel.orderFrontRegardless()
    }

    // MARK: Screen / notch geometry

    private var targetScreen: NSScreen {
        // Prefer the built-in display with a notch; fall back to the main screen.
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func screenMetrics() -> (notchWidth: CGFloat, barHeight: CGFloat) {
        let screen = targetScreen
        let barHeight = max(screen.safeAreaInsets.top, 30)
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return (screen.frame.width - left.width - right.width, barHeight)
        }
        return (196, barHeight) // no notch: draw a floating pill of a sensible width
    }

    // MARK: Panel

    private func setUpPanel() {
        panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // the SwiftUI shape draws its own shadow
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = NSHostingView(rootView: IslandView(model: model))
    }

    private func layoutPanel(expanded: Bool) {
        let m = screenMetrics()
        let size = expanded
            ? NSSize(width: Island.expandedWidth, height: m.barHeight + Island.expandedBodyHeight)
            : NSSize(width: m.notchWidth + 100, height: m.barHeight + 8)
        let screenFrame = targetScreen.frame
        let frame = NSRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        if expanded {
            panel.setFrame(frame, display: true)
        } else {
            // Let the SwiftUI collapse animation play before shrinking the window,
            // otherwise the content gets clipped mid-animation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
                guard let self, !self.model.expanded else { return }
                self.panel.setFrame(frame, display: true)
            }
        }
    }

    // MARK: Menu bar fallback

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "sparkle",
            accessibilityDescription: "Claude Island"
        )

        let menu = NSMenu()
        let statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        let remoteItem = NSMenuItem(title: "Remote Approvals", action: #selector(toggleRemote), keyEquivalent: "")
        remoteItem.target = self
        menu.addItem(remoteItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Claude Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        // Keep the menu's status line and checkmark current.
        model.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                let live = snapshot.liveSessions
                if !self.model.connected {
                    statusLine.title = "Relay offline"
                } else if live.isEmpty {
                    statusLine.title = "No active sessions"
                } else {
                    let working = live.filter { $0.state == "working" }.count
                    statusLine.title = "\(live.count) session(s) · \(working) working"
                }
                if snapshot.updateAvailable == true {
                    statusLine.title += " · update available (claude-widget update)"
                }
                remoteItem.state = snapshot.remoteMode ? .on : .off
            }
            .store(in: &cancellables)
    }

    @objc private func toggleRemote() {
        model.setRemoteMode(!model.snapshot.remoteMode)
    }
}

@main
enum ClaudeIslandMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
