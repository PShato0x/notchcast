# NotchAI

✦ A dynamic island for your MacBook's notch. See what your AI coding agent is working on and approve its permission requests with one click — without staring at the terminal. Works with [Claude Code](https://claude.com/claude-code) today.

<p align="center">
  <img src="docs/island-demo.svg" width="500" alt="The island under the MacBook notch expands with “Requests to run `cargo test`”, the request is approved, and it settles back into the collapsed strip">
</p>
<p align="center">
  <img src="docs/island-request.png" width="508" alt="NotchAI expanded under the MacBook notch: “Requests to run `npm test`” with Always allow / Allow once / Deny buttons">
</p>
<p align="center">
  <img src="docs/island-status.png" width="380" alt="NotchAI showing a working session on hover">
  &nbsp;
  <img src="docs/island-collapsed.png" width="240" alt="Collapsed island: a slim strip hugging the notch with a status dot">
</p>
<p align="center"><sub>The stills are rendered from the real SwiftUI views — regenerate anytime with <code>macos/build.sh --readme-assets</code>.</sub></p>

## Install (one line)

```bash
curl -fsSL https://raw.githubusercontent.com/PShato0x/notchai/main/get.sh | bash
```

Needs macOS 14+ (Apple Silicon), Node.js 18+, and the Xcode Command Line Tools. Everything builds from source on your machine — no binaries are shipped. The installer is idempotent and doubles as the updater; afterwards you get a `notchai` CLI:

```
notchai status      # relay version, sessions, pending approvals
notchai update      # pull latest, rebuild, restart (island shows "↑ Update available" when there is one)
notchai restart     # bounce the relay + island
notchai uninstall   # remove services and app
```

Prefer to read before piping to bash? Quite right: [get.sh](get.sh). Manual setup is documented below. **Website: [notchai-production.up.railway.app](https://notchai-production.up.railway.app/)**

## Features

- **Collapsed**: a slim black extension of the notch with a status dot — the signature orange pulse while the agent works, bright amber when something needs you, green when idle.
- **Auto-expands** when the agent requests permission, showing **Always allow / Allow once / Deny** right under the notch. *Always allow* saves a rule (e.g. `Bash:npm`) that auto-approves matching requests from then on.
- **Hover** over the notch anytime to peek at active sessions and their last prompt, and to toggle remote approvals.
- **Never steals focus** — it's a non-activating panel; clicking buttons doesn't interrupt what you're doing. Menu-bar ✦ icon as fallback for Macs without a notch.
- **Fails open, fails safe** — if the relay is down or you don't answer in time, the agent falls back to its normal terminal prompt. Nothing is auto-approved without you.
- **Brand-neutral by design** — Claude Code is the first supported agent; the relay protocol and UI are agent-agnostic so other coding agents can plug in (see roadmap).

## How it works

```
┌────────────────── Mac ──────────────────┐
│                                         │
│  Claude Code                            │
│   │  hooks (PreToolUse,                 │
│   │  Stop, Notification, …)             │
│   ▼                                     │
│  relay server (Node, localhost:8787)    │
│   ▲                                     │
│   │  /status polling · /respond         │
│   ▼                                     │
│  ✦ NotchAI island (notch app, macos/)   │
└─────────────────────────────────────────┘
```

1. **Hooks** ([hooks/](hooks/)) — a `PreToolUse` hook forwards each permission-relevant tool call to the relay and *waits*; status hooks (`UserPromptSubmit`, `PostToolUse`, `Stop`, `Notification`, `SessionEnd`) report what the session is doing.
2. **Relay** ([server/server.js](server/server.js)) — a zero-dependency Node server that holds session state, pending requests, and your always-allow rules. A client answers `always | once | deny`; the hook returns Claude Code's `permissionDecision` accordingly.
3. **Island** ([macos/](macos/)) — native AppKit/SwiftUI notch panel polling the relay on localhost every 1.5 s, so requests appear near-instantly.

## Manual setup

```bash
./install.sh                    # once: creates ~/.notchai (token + hooks)
node server/server.js &         # the relay; keep it running
cd macos && ./build.sh --run    # build + launch the island (needs only Command Line Tools)
```

Then merge [hooks/settings.example.json](hooks/settings.example.json) into `~/.claude/settings.json` and restart Claude Code. To route approvals only for specific projects, put the hooks in that project's `.claude/settings.json` instead. The island reads its config from `~/.notchai/config.json` automatically.

> `build.sh` compiles with plain `swiftc` (no Xcode.app needed) and auto-works-around a common broken-CLT issue (stale duplicate `SwiftBridging` modulemap). A SwiftPM [Package.swift](macos/Package.swift) is also included if you prefer `swift build`.

## Security notes

- Every endpoint requires the bearer token created by `install.sh`. Treat it like a password.
- The relay binds to `127.0.0.1` by default — nothing outside this Mac can reach it. To pair a remote client, set `"host": "0.0.0.0"` in `~/.notchai/config.json`, prefer **Tailscale** (encrypts end-to-end), and never port-forward 8787 to the internet.
- The permission gate **fails open to the terminal** — a dead relay never silently approves anything.
- "Always allow" rules live in `~/.notchai/rules.json`; clear them anytime by deleting entries.

## Limitations (v1)

- The permission gate waits up to 2 minutes (configurable via `gateTimeoutMs`) for a click, then falls back to the terminal prompt.
- The relay keeps session state in memory — restarting it clears session history (rules and config persist on disk).
- The relay's `/ask` endpoint (one-shot headless `claude -p` runs) exists but has no island UI yet — see roadmap.

## Roadmap

- [ ] Quick Ask input right in the notch
- [ ] Click a session to peek at its transcript ("View Session")
- [ ] Homebrew tap (`brew install notchai`)
- [ ] Adapters for more agents (Codex CLI, Gemini CLI) over the same relay protocol

## Contributing

PRs welcome. The relay and hooks have no dependencies on purpose — keep it that way if you can.

## License

[MIT](LICENSE)
