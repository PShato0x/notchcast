#!/usr/bin/env bash
# NotchAI — Mac-side installer.
# Creates ~/.notchai with a config (auth token) and the hook scripts,
# then prints the hooks snippet for ~/.claude/settings.json.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CW_DIR="$HOME/.notchai"
CONFIG="$CW_DIR/config.json"

command -v node >/dev/null 2>&1 || { echo "Node.js 18+ is required (brew install node)"; exit 1; }

mkdir -p "$CW_DIR/hooks"
cp "$REPO_DIR/hooks/permission-gate.mjs" "$REPO_DIR/hooks/status-report.mjs" "$CW_DIR/hooks/"

if [[ -f "$CONFIG" ]]; then
  echo "Keeping existing config at $CONFIG"
  TOKEN=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$CONFIG','utf8')).token || '')")
else
  TOKEN=$(openssl rand -hex 24)
  cat > "$CONFIG" <<EOF
{
  "port": 8787,
  "token": "$TOKEN",
  "url": "http://127.0.0.1:8787",
  "gateTimeoutMs": 120000,
  "remoteMode": true
}
EOF
  echo "Wrote $CONFIG"
fi

cat <<EOF

Done. Next steps:

1. Add the hooks to ~/.claude/settings.json (merge with any existing "hooks"):
   see $REPO_DIR/hooks/settings.example.json
   The scripts are installed at: $CW_DIR/hooks/

2. Start the relay (keep it running while you work):
     node "$REPO_DIR/server/server.js"

3. Build and launch the island:
     cd "$REPO_DIR/macos" && ./build.sh --run

(Or skip all of this next time: get.sh does every step, including the
launchd service and Login Item.)

EOF
