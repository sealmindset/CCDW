#!/usr/bin/env bash
# =============================================================================
# build-terminal-app.sh — build the native CCDW Terminal.app (macOS).
# -----------------------------------------------------------------------------
# Compiles CCDWTerminal.swift into a real Mach-O app bundle and ad-hoc signs it
# so it launches locally under Gatekeeper. This is a compiled app (WKWebView),
# NOT a script .app — so the Gatekeeper problems the .command launcher avoids
# don't apply here.
#
# Usage:  ./build-terminal-app.sh [DEST_DIR]     (default: ~/Applications)
# For distribution: sign with a Developer ID cert and notarize instead of the
# ad-hoc "-" identity below.
# =============================================================================
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
SRC="$SELF_DIR/CCDWTerminal.swift"
DEST_DIR="${1:-$HOME/Applications}"
APP_NAME="CCDW Terminal"
APP="$DEST_DIR/$APP_NAME.app"
BUNDLE_ID="com.ccdw.terminal"

command -v swiftc >/dev/null || { echo "swiftc not found (install Xcode / Command Line Tools)." >&2; exit 1; }
[ -f "$SRC" ] || { echo "missing source: $SRC" >&2; exit 1; }

echo "  Building $APP_NAME.app ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# --- compile ----------------------------------------------------------------
swiftc -O -o "$APP/Contents/MacOS/CCDWTerminal" "$SRC" \
    -framework Cocoa -framework WebKit

# --- Info.plist -------------------------------------------------------------
# NSAllowsLocalNetworking lets the WKWebView load http://localhost (ttyd).
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleExecutable</key><string>CCDWTerminal</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST

# --- ad-hoc sign ------------------------------------------------------------
codesign --force --deep --sign - "$APP"
echo "  Signed (ad-hoc)."

# --- verify -----------------------------------------------------------------
codesign --verify --deep --strict "$APP" && echo "  codesign verify: OK"

echo ""
echo "  Built: $APP"
echo "  Launch:  open \"$APP\"   (start the container first: docker compose up -d)"
