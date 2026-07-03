#!/usr/bin/env bash
# Build ClaudeIsland.app with plain swiftc — works with just the Xcode
# Command Line Tools, no Xcode.app or SwiftPM required.
#   ./build.sh          release build -> macos/ClaudeIsland.app
#   ./build.sh --run    build then launch
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$DIR/ClaudeIsland.app"
BIN="$APP/Contents/MacOS/ClaudeIsland"

# --- Workaround for a broken CLT install ---------------------------------
# Some Command Line Tools upgrades leave a stale usr/include/swift/module.modulemap
# behind that duplicates bridging.modulemap ("redefinition of module
# 'SwiftBridging'"). If both files define the module, mask the stale one with
# a VFS overlay instead of requiring sudo to delete it.
EXTRA_FLAGS=()
CLT_SWIFT_INC="/Library/Developer/CommandLineTools/usr/include/swift"
if [[ -f "$CLT_SWIFT_INC/module.modulemap" && -f "$CLT_SWIFT_INC/bridging.modulemap" ]] \
   && grep -q "module SwiftBridging" "$CLT_SWIFT_INC/module.modulemap" \
   && grep -q "module SwiftBridging" "$CLT_SWIFT_INC/bridging.modulemap"; then
  echo "note: masking stale CLT module.modulemap (duplicate SwiftBridging definition)"
  OVERLAY_DIR="$(mktemp -d)"
  : > "$OVERLAY_DIR/empty.modulemap"
  cat > "$OVERLAY_DIR/overlay.yaml" <<EOF
{
  "version": 0,
  "case-sensitive": "false",
  "use-external-names": false,
  "roots": [
    {
      "name": "$CLT_SWIFT_INC",
      "type": "directory",
      "contents": [
        { "name": "module.modulemap", "type": "file", "external-contents": "$OVERLAY_DIR/empty.modulemap" }
      ]
    }
  ]
}
EOF
  EXTRA_FLAGS=(
    -Xfrontend -vfsoverlay -Xfrontend "$OVERLAY_DIR/overlay.yaml"
    -Xcc -ivfsoverlay -Xcc "$OVERLAY_DIR/overlay.yaml"
  )
fi
# --------------------------------------------------------------------------

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>          <string>ClaudeIsland</string>
    <key>CFBundleIdentifier</key>          <string>dev.claudewidget.island</string>
    <key>CFBundleName</key>                <string>Claude Island</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleShortVersionString</key>  <string>0.1.0</string>
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>
    <key>LSUIElement</key>                 <true/>
</dict>
</plist>
EOF

echo "Compiling…"
swiftc -O -parse-as-library \
  "${EXTRA_FLAGS[@]}" \
  "$DIR/Sources/ClaudeIsland/"*.swift \
  -o "$BIN"

codesign --force --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
if [[ "${1:-}" == "--run" ]]; then
  open "$APP"
fi
