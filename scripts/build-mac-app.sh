#!/usr/bin/env bash
# =============================================================================
# build-mac-app.sh — (re)build the "Claude Code.app" macOS launcher bundle.
#
# The bundle is deliberately thin: its executable is a tiny bash stub that
# exec's the repo's scripts/launch-mac.sh. Because it references the repo path
# (rather than copying the launcher into the bundle), the .app always runs the
# latest launcher after a git pull — no rebuild required for launcher changes.
#
# Usage:
#   ./build-mac-app.sh [DEST_DIR]
#
#   DEST_DIR   Directory to place "Claude Code.app" in. Default: "$HOME/Desktop".
#
# The build is idempotent: any existing "Claude Code.app" at the destination is
# removed first, then rebuilt from scratch.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths.
# ---------------------------------------------------------------------------
# Resolve the repo root from this script's own location (scripts/ -> repo root).
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
REPO_DIR="$(cd "${_SELF_DIR}/.." 2>/dev/null && pwd)"

# Known install path baked into the launcher stub. The .app has no repo context
# of its own, so the stub hardcodes this canonical location and falls back to a
# couple of sensible alternatives if it has moved.
INSTALL_REPO_DIR="$HOME/Documents/CCDW"

DEST_DIR="${1:-$HOME/Desktop}"
APP_NAME="Claude Code.app"
APP_DIR="${DEST_DIR}/${APP_NAME}"

ASSETS_DIR="${REPO_DIR}/assets"
ICON_ICNS_SRC="${ASSETS_DIR}/claude-icon.icns"
ICON_PNG_SRC="${ASSETS_DIR}/claude-icon.png"

# The launcher the bundle exec's at runtime.
LAUNCH_SCRIPT_REL="scripts/launch-mac.sh"

log()  { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Code-signing configuration (all via environment — NEVER commit credentials).
#
# For distribution to arbitrary Macs (zip / share drive / MDM / download), the
# bundle MUST be Developer ID signed AND notarized, or macOS Gatekeeper blocks
# it once it carries the quarantine attribute. For the per-user install-time
# build (built locally on the user's own Mac, no quarantine) an ad-hoc
# signature is enough. This script does the best it can with what's available:
#
#   1. Developer ID identity available  -> Developer ID sign (hardened runtime).
#   2. + notarization credentials       -> notarize + staple (distributable).
#   3. Neither                           -> ad-hoc sign (local launch only).
#
# Signing identity (pick ONE, or let it auto-detect):
#   MACOS_SIGN_IDENTITY   Exact identity, e.g.
#                         "Developer ID Application: Sleep Number Corp (TEAMID)".
#                         If unset, the first "Developer ID Application" identity
#                         in the keychain is used; if none, falls back to ad-hoc.
#   MACOS_SIGN_ADHOC=1    Force ad-hoc even if a Developer ID identity exists.
#
# Notarization credentials (pick ONE method; omit all to skip notarization):
#   a) Stored profile:  MACOS_NOTARY_PROFILE   (notarytool --keychain-profile)
#   b) App Store API:   MACOS_NOTARY_KEY_ID + MACOS_NOTARY_KEY_PATH(.p8) +
#                       MACOS_NOTARY_ISSUER
#   c) Apple ID:        MACOS_NOTARY_APPLE_ID + MACOS_NOTARY_TEAM_ID +
#                       MACOS_NOTARY_PASSWORD (an app-specific password)
#   SKIP_NOTARIZE=1     Developer ID sign but skip notarization.
# ---------------------------------------------------------------------------

# _detect_signing_identity — echo the codesign identity to use.
# Prints a real Developer ID identity when available, else "-" (ad-hoc).
_detect_signing_identity() {
    if [ "${MACOS_SIGN_ADHOC:-}" = "1" ]; then printf '%s' "-"; return; fi
    if [ -n "${MACOS_SIGN_IDENTITY:-}" ]; then printf '%s' "$MACOS_SIGN_IDENTITY"; return; fi
    local found
    found="$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -o 'Developer ID Application: [^"]*' | head -1)"
    if [ -n "$found" ]; then printf '%s' "$found"; else printf '%s' "-"; fi
}

# _notary_args — echo the notarytool credential args for the configured method,
# or empty string if no complete credential set is present.
_notary_args() {
    if [ -n "${MACOS_NOTARY_PROFILE:-}" ]; then
        printf '%s' "--keychain-profile ${MACOS_NOTARY_PROFILE}"
    elif [ -n "${MACOS_NOTARY_KEY_ID:-}" ] && [ -n "${MACOS_NOTARY_KEY_PATH:-}" ] && [ -n "${MACOS_NOTARY_ISSUER:-}" ]; then
        printf '%s' "--key ${MACOS_NOTARY_KEY_PATH} --key-id ${MACOS_NOTARY_KEY_ID} --issuer ${MACOS_NOTARY_ISSUER}"
    elif [ -n "${MACOS_NOTARY_APPLE_ID:-}" ] && [ -n "${MACOS_NOTARY_TEAM_ID:-}" ] && [ -n "${MACOS_NOTARY_PASSWORD:-}" ]; then
        printf '%s' "--apple-id ${MACOS_NOTARY_APPLE_ID} --team-id ${MACOS_NOTARY_TEAM_ID} --password ${MACOS_NOTARY_PASSWORD}"
    fi
}

# sign_bundle APP_DIR — sign (and, if possible, notarize + staple) the bundle.
# Never hard-fails the build: on any signing/notarization problem it warns and
# leaves the best signature it achieved (falling back to ad-hoc).
sign_bundle() {
    local app="$1" identity
    if ! command -v codesign >/dev/null 2>&1; then
        warn "'codesign' not found (install Xcode command line tools); the app may not launch on double-click until signed."
        return 0
    fi

    identity="$(_detect_signing_identity)"

    if [ "$identity" = "-" ]; then
        # Ad-hoc: launches locally (installer-built, no quarantine). A copied /
        # downloaded copy on another Mac will be Gatekeeper-blocked.
        if codesign --force --deep -s - "$app" >/dev/null 2>&1; then
            log "Ad-hoc signed (launches on THIS Mac / installer builds)."
            warn "No Developer ID identity found: a COPIED or DOWNLOADED .app will be blocked by Gatekeeper on other Macs. Set MACOS_SIGN_IDENTITY (+ notarization creds) to produce a distributable bundle."
        else
            warn "Ad-hoc code-signing failed; the app may not launch on double-click."
        fi
        return 0
    fi

    # Developer ID signing with hardened runtime + secure timestamp (required
    # for notarization).
    log "Developer ID signing as: $identity"
    if ! codesign --force --deep --options runtime --timestamp -s "$identity" "$app" >/dev/null 2>&1; then
        warn "Developer ID signing failed; falling back to ad-hoc."
        codesign --force --deep -s - "$app" >/dev/null 2>&1 || true
        return 0
    fi

    if [ "${SKIP_NOTARIZE:-}" = "1" ]; then
        log "Developer ID signed (notarization skipped by SKIP_NOTARIZE=1)."
        warn "Un-notarized: a downloaded copy may still warn on first launch until notarized + stapled."
        return 0
    fi

    local nargs; nargs="$(_notary_args)"
    if [ -z "$nargs" ]; then
        log "Developer ID signed (no notarization credentials provided — skipping notarize)."
        warn "Provide MACOS_NOTARY_* credentials to notarize; without it a downloaded copy may warn on first launch."
        return 0
    fi

    if ! command -v xcrun >/dev/null 2>&1 || ! xcrun --find notarytool >/dev/null 2>&1; then
        warn "notarytool not available (need Xcode); signed but NOT notarized."
        return 0
    fi

    # Notarize: submit a zip of the .app, wait, then staple the ticket onto it.
    local zip; zip="$(mktemp -d)/ClaudeCode.zip"
    log "Notarizing (this can take a few minutes)..."
    if /usr/bin/ditto -c -k --keepParent "$app" "$zip" >/dev/null 2>&1 \
        && xcrun notarytool submit "$zip" $nargs --wait >/dev/null 2>&1; then
        if xcrun stapler staple "$app" >/dev/null 2>&1; then
            log "Notarized and stapled — distributable to any Mac."
        else
            warn "Notarization submitted but stapling failed; run: xcrun stapler staple \"$app\""
        fi
    else
        warn "Notarization failed (check credentials / submission log via 'xcrun notarytool log'). Bundle is Developer ID signed but not notarized."
    fi
    rm -rf "$(dirname "$zip")" 2>/dev/null || true
    return 0
}

# ---------------------------------------------------------------------------
# Sanity checks.
# ---------------------------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || die "build-mac-app.sh must run on macOS."

if [ ! -f "${REPO_DIR}/${LAUNCH_SCRIPT_REL}" ]; then
    warn "Expected launcher not found at ${REPO_DIR}/${LAUNCH_SCRIPT_REL}."
    warn "The bundle will still be built and will look for the launcher at runtime."
fi

mkdir -p "$DEST_DIR" || die "Cannot create destination dir: $DEST_DIR"

# ---------------------------------------------------------------------------
# Idempotent: remove any existing bundle first.
# ---------------------------------------------------------------------------
if [ -e "$APP_DIR" ]; then
    log "Removing existing bundle: $APP_DIR"
    rm -rf "$APP_DIR"
fi

# ---------------------------------------------------------------------------
# Bundle skeleton.
# ---------------------------------------------------------------------------
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RES_DIR="${CONTENTS_DIR}/Resources"
mkdir -p "$MACOS_DIR" "$RES_DIR"

# ---------------------------------------------------------------------------
# Info.plist.
# ---------------------------------------------------------------------------
# Note: LSBackgroundOnly is intentionally NOT set — we want the app to appear
# and behave normally (Dock icon, focusable) when double-clicked.
cat > "${CONTENTS_DIR}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Claude Code</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Code</string>
    <key>CFBundleExecutable</key>
    <string>launcher</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIdentifier</key>
    <string>com.sleepnumber.ccdw.launcher</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
</dict>
</plist>
PLIST

# ---------------------------------------------------------------------------
# Launcher stub (Contents/MacOS/launcher).
#
# This is intentionally tiny: it resolves the repo path (hardcoded known
# install location, with fallbacks) and exec's the repo's launch-mac.sh so the
# bundle always runs the latest launcher.
# ---------------------------------------------------------------------------
LAUNCHER_STUB="${MACOS_DIR}/launcher"
cat > "$LAUNCHER_STUB" <<STUB
#!/usr/bin/env bash
# Auto-generated by build-mac-app.sh. Do not edit — rebuild the .app instead.
#
# Resolve the CCDW repo, then exec its launch-mac.sh. The .app carries no repo
# context of its own, so we start from the known install path and fall back to
# a couple of common locations before giving up with a visible error dialog.
set -euo pipefail

# Candidate repo roots, in priority order.
CANDIDATES=(
    "${INSTALL_REPO_DIR}"
    "\$HOME/Documents/CCDW"
    "\$HOME/CCDW"
    "\$HOME/src/CCDW"
)

REPO=""
for c in "\${CANDIDATES[@]}"; do
    if [ -f "\$c/${LAUNCH_SCRIPT_REL}" ]; then
        REPO="\$c"
        break
    fi
done

if [ -z "\$REPO" ]; then
    /usr/bin/osascript -e 'display dialog "Could not find the Claude Code installation (CCDW repo). Expected it at ~/Documents/CCDW. Please reinstall or run the installer, then rebuild this app." buttons {"OK"} default button "OK" with icon caution with title "Claude Code"' >/dev/null 2>&1 || true
    exit 1
fi

exec "\$REPO/${LAUNCH_SCRIPT_REL}"
STUB

chmod +x "$LAUNCHER_STUB"

# ---------------------------------------------------------------------------
# Icon (Contents/Resources/AppIcon.icns).
#
#  1. If assets/claude-icon.icns exists, copy it verbatim.
#  2. Else if assets/claude-icon.png exists, generate an .icns via the standard
#     sips + iconutil iconset pipeline.
#  3. Else warn and skip (the app still runs; it just uses a generic icon).
# ---------------------------------------------------------------------------
ICON_DEST="${RES_DIR}/AppIcon.icns"

generate_icns_from_png() {
    local png="$1" out="$2"
    command -v sips     >/dev/null 2>&1 || { warn "'sips' not found; cannot generate icon."; return 1; }
    command -v iconutil >/dev/null 2>&1 || { warn "'iconutil' not found; cannot generate icon."; return 1; }

    local tmp_root tmp_iconset
    tmp_root="$(mktemp -d)"
    # Clean up the temp dir on ANY return path (success or the || return 1 below)
    # so a mid-way icon failure never orphans a /var/folders temp dir.
    trap 'rm -rf "$tmp_root"' RETURN
    tmp_iconset="${tmp_root}/AppIcon.iconset"
    mkdir -p "$tmp_iconset"

    # Standard iconset sizes (points @ 1x and 2x).
    local sizes=(16 32 128 256 512)
    local s
    for s in "${sizes[@]}"; do
        sips -z "$s"   "$s"   "$png" --out "${tmp_iconset}/icon_${s}x${s}.png"       >/dev/null 2>&1 || return 1
        local s2=$(( s * 2 ))
        sips -z "$s2"  "$s2"  "$png" --out "${tmp_iconset}/icon_${s}x${s}@2x.png"    >/dev/null 2>&1 || return 1
    done

    iconutil -c icns "$tmp_iconset" -o "$out" >/dev/null 2>&1 || return 1
    return 0
}

if [ -f "$ICON_ICNS_SRC" ]; then
    log "Using existing icon: $ICON_ICNS_SRC"
    cp "$ICON_ICNS_SRC" "$ICON_DEST"
elif [ -f "$ICON_PNG_SRC" ]; then
    log "Generating icon from PNG: $ICON_PNG_SRC"
    if ! generate_icns_from_png "$ICON_PNG_SRC" "$ICON_DEST"; then
        warn "Icon generation failed; the app will use a generic icon."
        rm -f "$ICON_DEST"
    fi
else
    warn "No icon found (looked for $ICON_ICNS_SRC and $ICON_PNG_SRC); skipping icon."
fi

# ---------------------------------------------------------------------------
# Strip the quarantine attribute so Gatekeeper doesn't block first launch.
# ---------------------------------------------------------------------------
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Code-sign (and notarize if credentials are available). Without a signature,
# macOS LaunchServices silently refuses to launch a script-based .app on
# double-click. See sign_bundle() above for the Developer ID / ad-hoc logic.
# ---------------------------------------------------------------------------
sign_bundle "$APP_DIR"

# Nudge Finder/LaunchServices to pick up the new icon promptly.
touch "$APP_DIR" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Portable .command fallback ("Launch Claude Code.command").
#
# A plain executable script with a .command extension double-clicks open in
# Terminal and runs — with NO code signature required, ever, and it survives
# being copied (a downloaded copy just needs a one-time right-click -> Open).
# This is the no-signing safety net for anyone who receives the launcher
# without running the installer, or on a locked-down Mac where the unsigned
# .app won't launch. It resolves the repo the same way the .app stub does and
# exec's the same launch-mac.sh, so both paths behave identically.
# ---------------------------------------------------------------------------
COMMAND_FILE="${DEST_DIR}/Launch Claude Code.command"
cat > "$COMMAND_FILE" <<CMD
#!/bin/bash
# Auto-generated by build-mac-app.sh. Portable launcher — no code signing needed.
# Resolve the CCDW repo, then exec its launch-mac.sh.
set -euo pipefail

CANDIDATES=(
    "${INSTALL_REPO_DIR}"
    "\$HOME/Documents/CCDW"
    "\$HOME/CCDW"
    "\$HOME/src/CCDW"
)

REPO=""
for c in "\${CANDIDATES[@]}"; do
    if [ -f "\$c/${LAUNCH_SCRIPT_REL}" ]; then
        REPO="\$c"
        break
    fi
done

if [ -z "\$REPO" ]; then
    /usr/bin/osascript -e 'display dialog "Could not find the Claude Code installation (CCDW repo). Expected it at ~/Documents/CCDW. Please reinstall or run the installer." buttons {"OK"} default button "OK" with icon caution with title "Claude Code"' >/dev/null 2>&1 || true
    exit 1
fi

exec "\$REPO/${LAUNCH_SCRIPT_REL}"
CMD
chmod +x "$COMMAND_FILE"
xattr -dr com.apple.quarantine "$COMMAND_FILE" 2>/dev/null || true
log "Built portable fallback: $COMMAND_FILE"

log ""
log "Built: $APP_DIR"
log "It launches: ${REPO_DIR}/${LAUNCH_SCRIPT_REL} (resolved at runtime from ~/Documents/CCDW)"
