#!/usr/bin/env bash
# =============================================================================
# build-terminal-app.sh — build the native CCDW Terminal.app (macOS).
# -----------------------------------------------------------------------------
# Builds a REAL terminal emulator (SwiftTerm) that drives a `docker exec -it`
# PTY into the claude-code container — no ttyd / xterm.js / WKWebView. Selection,
# copy, paste, and ⌘C/⌘V are genuinely native (Terminal.app behavior).
#
# Uses SwiftPM (swift build) to fetch + compile the SwiftTerm dependency, then
# assembles the compiled binary into an ad-hoc-signed .app bundle so it launches
# locally under Gatekeeper.
#
# Usage:  ./build-terminal-app.sh [DEST_DIR]     (default: <project>/dist)
# For distribution: sign with a Developer ID cert and notarize instead of the
# ad-hoc "-" identity below.
# =============================================================================
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
DEST_DIR="${1:-$SELF_DIR/dist}"
mkdir -p "$DEST_DIR"
APP_NAME="CCDW Terminal"
APP="$DEST_DIR/$APP_NAME.app"
BUNDLE_ID="com.ccdw.terminal"
BIN_NAME="CCDWTerminal"

command -v swift >/dev/null || { echo "swift not found (install Xcode / Command Line Tools)." >&2; exit 1; }
[ -f "$SELF_DIR/Package.swift" ] || { echo "missing Package.swift in $SELF_DIR" >&2; exit 1; }

# --- compile via SwiftPM (fetches SwiftTerm on first build) ------------------
echo "  Building $APP_NAME.app (SwiftTerm, release) ..."
( cd "$SELF_DIR" && swift build -c release )
BUILT_BIN="$(cd "$SELF_DIR" && swift build -c release --show-bin-path)/$BIN_NAME"
[ -x "$BUILT_BIN" ] || { echo "build did not produce $BUILT_BIN" >&2; exit 1; }

# --- assemble the .app bundle ------------------------------------------------
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILT_BIN" "$APP/Contents/MacOS/$BIN_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleExecutable</key><string>${BIN_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# --- ad-hoc sign -------------------------------------------------------------
codesign --force --deep --sign - "$APP"
echo "  Signed (ad-hoc)."

# --- verify ------------------------------------------------------------------
codesign --verify --deep --strict "$APP" && echo "  codesign verify: OK"

echo ""
echo "  Built: $APP"
echo "  Launch:  open \"$APP\"   (start the container first: docker compose up -d)"
