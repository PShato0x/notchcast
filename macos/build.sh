#!/usr/bin/env bash
# Build NotchCast.app with plain swiftc — works with just the Xcode
# Command Line Tools, no Xcode.app or SwiftPM required.
#   ./build.sh                  release build -> macos/NotchCast.app
#   ./build.sh --run            build then launch
#   ./build.sh --readme-assets  render docs/island-*.png from the real views
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$DIR/NotchCast.app"
BIN="$APP/Contents/MacOS/NotchCast"

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

if [[ "${1:-}" == "--readme-assets" ]]; then
  DOCS="$(cd "$DIR/.." && pwd)/docs"
  mkdir -p "$DOCS"
  TMP="$(mktemp -d)"
  echo "Compiling asset renderer…"
  swiftc -O -parse-as-library \
    "${EXTRA_FLAGS[@]}" \
    "$DIR/Sources/NotchCast/IslandView.swift" \
    "$DIR/Sources/NotchCast/StatusModel.swift" \
    "$DIR/Sources/NotchCast/RelayClient.swift" \
    "$DIR/Scripts/RenderReadmeAssets.swift" \
    -o "$TMP/render-assets"
  "$TMP/render-assets" "$DOCS"
  # The animated demo is a hand-authored vector: docs/island-demo.svg.
  # Keep it in sync with the theme when the island's design changes.
  exit 0
fi

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>          <string>NotchCast</string>
    <key>CFBundleIdentifier</key>          <string>dev.notchcast.app</string>
    <key>CFBundleName</key>                <string>NotchCast</string>
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
  "$DIR/Sources/NotchCast/"*.swift \
  -o "$BIN"

codesign --force --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
if [[ "${1:-}" == "--run" ]]; then
  open "$APP"
fi
