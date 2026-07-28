#!/bin/bash
# =============================================================================
# CCDW-Host-Bridge.command — install & start the CCDW host bridge (macOS).
# -----------------------------------------------------------------------------
# Double-click once. Sets up a per-user launchd agent that runs ccdw-hostd on
# 127.0.0.1, so the containerized terminal can reach the real macOS pasteboard,
# `open` host apps, reveal files in Finder, and post notifications.
#
# Re-running is safe: it regenerates config, reinstalls the agent, and reloads.
# To stop:  launchctl bootout gui/$(id -u)/com.ccdw.hostbridge
# =============================================================================
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
REPO_DIR="$(cd "$SELF_DIR/../.." 2>/dev/null && pwd)"

LABEL="com.ccdw.hostbridge"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="$HOME/Library/Logs/CCDW"
PORT="${CCDW_BRIDGE_PORT:-7690}"

NODE_BIN="$(command -v node || true)"
if [ -z "$NODE_BIN" ]; then
  echo "  Node.js is required on the host. Install Node, then re-run." >&2
  read -r -p "  Press Return to close... " _ || true
  exit 1
fi

# --- resolve host mount paths (mirror docker-compose bind mounts) -----------
# Honor .env overrides if present, else the compose defaults.
PROJECTS_PATH="$HOME/Documents"
EXTERNAL_DRIVES_PATH="/Volumes"
if [ -r "$REPO_DIR/.env" ]; then
  # shellcheck disable=SC1090
  _pp=$(grep -E '^PROJECTS_PATH=' "$REPO_DIR/.env" | tail -1 | cut -d= -f2-)
  _ed=$(grep -E '^EXTERNAL_DRIVES_PATH=' "$REPO_DIR/.env" | tail -1 | cut -d= -f2-)
  [ -n "${_pp:-}" ] && PROJECTS_PATH="${_pp/#\~/$HOME}"
  [ -n "${_ed:-}" ] && EXTERNAL_DRIVES_PATH="${_ed/#\~/$HOME}"
fi

DOCUMENTS_HOST="$PROJECTS_PATH"
DOWNLOADS_HOST="$HOME/Downloads"
DESKTOP_HOST="$HOME/Desktop"
VOLUMES_HOST="$EXTERNAL_DRIVES_PATH"

# --- generate token + shared config (readable by the container mount) -------
TOKEN="$(openssl rand -hex 32)"
CCDW_DIR="$PROJECTS_PATH/.ccdw"
CONFIG="$CCDW_DIR/host-bridge.json"
mkdir -p "$CCDW_DIR" "$LOG_DIR"
umask 177
printf '{"port":%s,"token":"%s"}\n' "$PORT" "$TOKEN" > "$CONFIG"
umask 022
chmod 600 "$CONFIG"

echo "  Config written: $CONFIG"
echo "  (container reads it at /home/coder/Documents/.ccdw/host-bridge.json)"

# --- write launchd agent ----------------------------------------------------
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${NODE_BIN}</string>
    <string>${SELF_DIR}/ccdw-hostd.mjs</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin</string>
    <key>CCDW_BRIDGE_PORT</key><string>${PORT}</string>
    <key>CCDW_BRIDGE_TOKEN</key><string>${TOKEN}</string>
    <key>CCDW_HOST_HOME</key><string>${HOME}</string>
    <key>CCDW_HOST_DOCUMENTS</key><string>${DOCUMENTS_HOST}</string>
    <key>CCDW_HOST_DOWNLOADS</key><string>${DOWNLOADS_HOST}</string>
    <key>CCDW_HOST_DESKTOP</key><string>${DESKTOP_HOST}</string>
    <key>CCDW_HOST_VOLUMES</key><string>${VOLUMES_HOST}</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${LOG_DIR}/host-bridge.out.log</string>
  <key>StandardErrorPath</key><string>${LOG_DIR}/host-bridge.err.log</string>
</dict>
</plist>
PLIST
chmod 600 "$PLIST"

# --- (re)load the agent -----------------------------------------------------
DOMAIN="gui/$(id -u)"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
if launchctl bootstrap "$DOMAIN" "$PLIST" 2>/dev/null; then
  :
else
  # Older macOS fallback
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST" 2>/dev/null || true
fi
launchctl enable "$DOMAIN/$LABEL" 2>/dev/null || true

ok=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS --max-time 2 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    ok=1; break
  fi
  sleep 0.5
done
if [ -n "$ok" ]; then
  echo "  Host bridge running on 127.0.0.1:${PORT}."
  echo "  Terminal clipboard, open, reveal, and notifications are now native."
else
  echo "  Started, but health check did not respond yet." >&2
  echo "  Logs: $LOG_DIR/host-bridge.*.log" >&2
fi

echo ""
read -r -p "  Press Return to close... " _ || true
