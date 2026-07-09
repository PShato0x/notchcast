#!/usr/bin/env bash
# NotchCast one-line installer / updater.
#
#   curl -fsSL https://raw.githubusercontent.com/PShato0x/notchcast/main/get.sh | bash
#
# Idempotent: safe to re-run anytime (that's also how `notchcast update`
# applies new versions). Installs:
#   ~/.notchcast/            config, token, hooks, always-allow rules
#   ~/.notchcast/src/        the repo checkout (skipped if you run this
#                                from your own clone — it uses that instead)
#   ~/Library/LaunchAgents/dev.notchcast.relay.plist   relay service
#   ~/.local/bin/notchcast   CLI (update / status / restart / uninstall)
#   NotchCast.app            built from source, added to Login Items
#
# Flags: --no-services  skip launchd/login-item/app-launch (for CI/testing)
set -euo pipefail

REPO_URL="https://github.com/PShato0x/notchcast"
CW_DIR="$HOME/.notchcast"
BIN_DIR="$HOME/.local/bin"
LABEL="dev.notchcast.relay"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
NO_SERVICES=0
[[ "${1:-}" == "--no-services" ]] && NO_SERVICES=1

say()  { printf '\033[1;38;5;173m✳\033[0m \033[1m%s\033[0m\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# ---------- prerequisites ----------
command -v git  >/dev/null || fail "git is required — run: xcode-select --install"
command -v node >/dev/null || fail "Node.js 18+ is required — https://nodejs.org (or: brew install node)"
node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 18 ? 0 : 1)' \
  || fail "Node.js 18+ required (found $(node --version))"
xcode-select -p >/dev/null 2>&1 || fail "Xcode Command Line Tools required — run: xcode-select --install, then re-run this script"

# ---------- migrate from pre-rename installs (claude-widget, notchai) ----------
for OLD_DIR in "$HOME/.claude-widget" "$HOME/.notchai"; do
  if [[ -d "$OLD_DIR" && ! -d "$CW_DIR" ]]; then
    echo "migrating $OLD_DIR -> $CW_DIR"
    mv "$OLD_DIR" "$CW_DIR"
  fi
done
for OLD_LABEL in dev.claudewidget.relay dev.notchai.relay; do
  if [[ -f "$HOME/Library/LaunchAgents/$OLD_LABEL.plist" ]]; then
    launchctl bootout "gui/$(id -u)/$OLD_LABEL" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$OLD_LABEL.plist"
  fi
done
rm -f "$BIN_DIR/claude-widget" "$BIN_DIR/notchai"
for OLD_APP in ClaudeIsland NotchAI; do
  osascript -e "tell application \"System Events\" to delete (every login item whose name is \"$OLD_APP\")" >/dev/null 2>&1 || true
  pkill -x "$OLD_APP" 2>/dev/null || true
done

# ---------- source checkout ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-/dev/null}")" 2>/dev/null && pwd || true)"
if [[ -n "${NOTCHCAST_SRC:-}" && -f "$NOTCHCAST_SRC/server/server.js" ]]; then
  # Homebrew-managed: the formula bakes NOTCHCAST_SRC into the CLI wrapper.
  SRC="$NOTCHCAST_SRC"
  say "Using Homebrew install: $SRC"
elif [[ -n "${SCRIPT_DIR:-}" && -f "$SCRIPT_DIR/server/server.js" && -e "$SCRIPT_DIR/.git" ]]; then
  SRC="$SCRIPT_DIR"
  say "Using this checkout: $SRC"
else
  SRC="$CW_DIR/src"
  if [[ -d "$SRC/.git" ]]; then
    say "Updating $SRC"
    git -C "$SRC" pull --ff-only
  else
    say "Cloning $REPO_URL"
    mkdir -p "$CW_DIR"
    git clone --depth 1 "$REPO_URL" "$SRC"
  fi
fi
VERSION="$(cat "$SRC/VERSION" 2>/dev/null || echo dev)"

# ---------- config, token, hook scripts ----------
say "Setting up ~/.notchcast (v$VERSION)"
bash "$SRC/install.sh" > /dev/null
# Record the absolute claude path: the launchd relay has a minimal PATH and
# couldn't find `claude` otherwise (needed for Quick Ask's headless runs).
CLAUDE_BIN_DETECTED="$(command -v claude || true)"
node -e "
const fs = require('fs'), p = '$CW_DIR/config.json';
const c = JSON.parse(fs.readFileSync(p, 'utf8'));
c.srcDir = '$SRC';
if ('$CLAUDE_BIN_DETECTED') c.claudeBin = '$CLAUDE_BIN_DETECTED';
fs.writeFileSync(p, JSON.stringify(c, null, 2));
"

# ---------- Claude Code hooks ----------
say "Merging hooks into ~/.claude/settings.json"
node "$SRC/hooks/merge-settings.mjs"

# ---------- CLI ----------
if [[ -z "${NOTCHCAST_SRC:-}" ]]; then
  # Homebrew owns the CLI in its own bin; only install ours for git installs.
  mkdir -p "$BIN_DIR"
  cp "$SRC/bin/notchcast" "$BIN_DIR/notchcast"
  chmod +x "$BIN_DIR/notchcast"
fi

# ---------- build the island ----------
if [[ -n "${NOTCHCAST_SRC:-}" && -x "$SRC/macos/NotchCast.app/Contents/MacOS/NotchCast" ]]; then
  say "Using the NotchCast.app built by Homebrew"
else
  say "Building NotchCast.app (first build takes ~30s)"
  bash "$SRC/macos/build.sh" | grep -v '^note:' || true
  [[ -x "$SRC/macos/NotchCast.app/Contents/MacOS/NotchCast" ]] || fail "island build failed — see output above"
fi

if [[ "$NO_SERVICES" == "0" ]]; then
  # ---------- relay as a launchd service ----------
  say "Installing relay service ($LABEL)"
  NODE_BIN="$(command -v node)"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>            <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$NODE_BIN</string>
        <string>$SRC/server/server.js</string>
    </array>
    <key>RunAtLoad</key>        <true/>
    <key>KeepAlive</key>        <true/>
    <key>StandardOutPath</key>  <string>$CW_DIR/relay.log</string>
    <key>StandardErrorPath</key><string>$CW_DIR/relay.log</string>
</dict>
</plist>
EOF
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"

  # ---------- island: login item + launch ----------
  say "Launching NotchCast"
  osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null \
      | grep -q "NotchCast" \
    || osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$SRC/macos/NotchCast.app\", hidden:false}" \
      >/dev/null 2>&1 || true
  pkill -x NotchCast 2>/dev/null || true
  sleep 0.5
  open "$SRC/macos/NotchCast.app"
fi

TOKEN="$(node -e "console.log(JSON.parse(require('fs').readFileSync('$CW_DIR/config.json','utf8')).token)")"

cat <<EOF

$(printf '\033[1m')NotchCast v$VERSION installed.$(printf '\033[0m')

  ✳ The island is on your notch — hover it, or wait for Claude to ask something.
  ✳ Restart any open Claude Code sessions so they pick up the hooks.
  ✳ CLI: notchcast {status|update|restart|uninstall}
$( [[ ":$PATH:" != *":$BIN_DIR:"* ]] && echo "    (add ~/.local/bin to your PATH to use it)" )

EOF
