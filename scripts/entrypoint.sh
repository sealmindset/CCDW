#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Entrypoint
# Starts ttyd + code-server, runs setup wizard if needed, auto-updates skills
# =============================================================================
SCRIPTS_DIR="/opt/claude-code-docker/scripts"
GITHUB_DIR="/home/coder/Documents/GitHub"
ENV_FILE="${GITHUB_DIR}/.env"
SETUP_DONE_MARKER="/home/coder/.claude/.setup-done"
STARTUP_LOG="/tmp/.startup-log"

# Structured startup log: status|label|detail
# status: ok, busy, error, info
slog() {
    echo "$1|$2|$3" >> "$STARTUP_LOG"
}

# Clear previous startup log
: > "$STARTUP_LOG"

# ---------------------------------------------------------------------------
# nav-proxy: the browser-facing ports (7681/7682/8080) are served by a tiny
# node reverse proxy that injects the shared top-nav into ttyd + code-server.
# The real apps bind INTERNAL ports; the proxy forwards to them.
# ---------------------------------------------------------------------------
TTYD_INT_PORT=17681        # ttyd main session (internal)
TTYD_NEW_INT_PORT=17682    # ttyd new-window   (internal)
CS_INT_PORT=18080          # code-server       (internal)

# start_nav_proxy <public_port> <target_port> <app: terminal|vscode>
start_nav_proxy() {
    su-exec coder env \
        NAV_PROXY_PORT="$1" NAV_TARGET_PORT="$2" NAV_APP="$3" \
        NAV_ASSETS_DIR="/opt/claude-code-docker/welcome" \
        node "$SCRIPTS_DIR/nav-proxy.js" >>"/tmp/nav-proxy-$1.log" 2>&1 &
}

# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Claude Code Docker${NC}"
echo -e "${BLUE}========================================${NC}"
slog "info|Startup|Initializing Claude Code Docker..."

# ---------------------------------------------------------------------------
# Ensure workspace directory exists
# ---------------------------------------------------------------------------
if [ -d "$GITHUB_DIR" ]; then
    chown -R coder:coder "$GITHUB_DIR" 2>/dev/null || true
    echo -e "${GREEN}[OK]${NC} Workspace: $GITHUB_DIR"
    slog "ok|Workspace|$GITHUB_DIR"
elif [ -L "$GITHUB_DIR" ] || [ -e "$GITHUB_DIR" ]; then
    # Symlink or file exists but isn't a usable directory — don't touch it
    GITHUB_DIR="/home/coder/Documents"
    ENV_FILE="/home/coder/Documents/.env"
    echo -e "${GREEN}[OK]${NC} Workspace: $GITHUB_DIR"
else
    mkdir -p "$GITHUB_DIR" 2>/dev/null || true
    if [ -d "$GITHUB_DIR" ]; then
        chown -R coder:coder "$GITHUB_DIR" 2>/dev/null || true
        echo -e "${GREEN}[OK]${NC} Workspace: $GITHUB_DIR"
    else
        GITHUB_DIR="/home/coder/Documents"
        ENV_FILE="/home/coder/Documents/.env"
        echo -e "${GREEN}[OK]${NC} Workspace: $GITHUB_DIR"
    fi
fi

# Export resolved workspace dir so Workshop and other services use it
export PROJECTS_DIR="$GITHUB_DIR"

# ---------------------------------------------------------------------------
# Ensure ~/Drives directory exists for external drive mounts
# ---------------------------------------------------------------------------
mkdir -p /home/coder/Drives
chown coder:coder /home/coder/Drives 2>/dev/null || true

# ---------------------------------------------------------------------------
# Host path parity — make host-style absolute paths resolve inside the
# container. HOST_HOME (e.g. /Users/<you> on macOS) is passed from compose.
# Symlinking it to /home/coder means a path copied from the Mac
# (/Users/<you>/Documents/x) resolves to the same file inside the container,
# and /Volumes is already mounted 1:1. Result: paths in error messages,
# `pwd`, and copy-paste match between host and container.
# ---------------------------------------------------------------------------
if [ -n "${HOST_HOME:-}" ] && [ "$HOST_HOME" != "/home/coder" ] \
   && [ "$HOST_HOME" != "/" ] && [ ! -e "$HOST_HOME" ]; then
    parent_dir="$(dirname "$HOST_HOME")"
    if mkdir -p "$parent_dir" 2>/dev/null && ln -sfn /home/coder "$HOST_HOME" 2>/dev/null; then
        echo -e "${GREEN}[OK]${NC} Path parity: $HOST_HOME -> /home/coder"
        slog "ok|Path Parity|$HOST_HOME"
    fi
fi

# ---------------------------------------------------------------------------
# Docker socket permissions (entrypoint runs as root, so we can fix this)
# ---------------------------------------------------------------------------
if [ -S /var/run/docker.sock ]; then
    chmod 666 /var/run/docker.sock 2>/dev/null || true
    echo -e "${GREEN}[OK]${NC} Docker socket accessible"
    slog "ok|Docker|Socket accessible"
else
    slog "error|Docker|Socket not found"
fi

# ---------------------------------------------------------------------------
# Auto-update /make-it skills (if enabled)
# ---------------------------------------------------------------------------
if [ "${SKILLS_AUTO_UPDATE:-1}" = "1" ]; then
    slog "busy|Skills|Checking for updates..."
    echo -e "${YELLOW}[...]${NC} Checking for skill updates..."
    if su-exec coder "$SCRIPTS_DIR/auto-update.sh"; then
        slog "ok|Skills|Up to date"
    else
        echo -e "${YELLOW}[WARN]${NC} Skill update check failed (continuing anyway)"
        slog "error|Skills|Update check failed (continuing)"
    fi
fi

# ---------------------------------------------------------------------------
# Sync image defaults into volume (plugins, skills, CLAUDE.md)
# Uses rsync --ignore-existing so user customizations are never overwritten.
# New files from image updates (e.g., new plugins) are added automatically.
# ---------------------------------------------------------------------------
if [ -d /home/coder/.claude-defaults ]; then
    rsync -a --ignore-existing /home/coder/.claude-defaults/ /home/coder/.claude/
    chown -R coder:coder /home/coder/.claude 2>/dev/null || true
    echo -e "${GREEN}[OK]${NC} Synced image defaults into .claude volume"
    slog "ok|Settings|Synced defaults"
fi

# ---------------------------------------------------------------------------
# Fix volume ownership (mounted volumes may be root-owned)
# ---------------------------------------------------------------------------
for dir in /home/coder/.config /home/coder/.claude /home/coder/.azure /home/coder/.aws \
           /home/coder/.kube /home/coder/.gitconfig.d /home/coder/.local /home/coder/.continue \
           /home/coder/.npm /home/coder/.shell-persist /home/coder/go; do
    if [ -d "$dir" ]; then
        chown -R coder:coder "$dir" 2>/dev/null || true
    fi
done
chown coder:coder /home/coder 2>/dev/null || true
chown coder:coder /home/coder/.gitconfig 2>/dev/null || true
chown coder:coder /home/coder/.claude.json 2>/dev/null || true

# ---------------------------------------------------------------------------
# Restore .claude.json if missing (backup lives inside the volume)
# ---------------------------------------------------------------------------
CLAUDE_JSON="/home/coder/.claude.json"
if [ ! -f "$CLAUDE_JSON" ]; then
    LATEST_BACKUP=$(ls -t /home/coder/.claude/backups/.claude.json.backup.* 2>/dev/null | head -1)
    if [ -n "$LATEST_BACKUP" ]; then
        cp "$LATEST_BACKUP" "$CLAUDE_JSON"
        chown coder:coder "$CLAUDE_JSON"
        echo -e "${GREEN}[OK]${NC} Restored Claude config from backup"
    fi
fi

# ---------------------------------------------------------------------------
# Disable Claude Code auto-updater (version is pinned in the Docker image)
# ---------------------------------------------------------------------------
export DISABLE_AUTOUPDATER=1

# ---------------------------------------------------------------------------
# npm CA bundle (corporate SSL inspection / Zscaler compatibility)
# ---------------------------------------------------------------------------
if [ -f /etc/ssl/certs/ca-certificates.crt ]; then
    su-exec coder npm config set cafile /etc/ssl/certs/ca-certificates.crt 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Configure AI provider from providers.yml
# Reads config/providers.yml and generates settings.json + token helper.
# Skips if settings.json already exists (preserves user edits).
# ---------------------------------------------------------------------------
slog "busy|AI Provider|Configuring..."
"$SCRIPTS_DIR/configure-provider.sh"
slog "ok|AI Provider|Configured"

# Source the exported env vars so downstream checks (token monitor) work
CLAUDE_SETTINGS="/home/coder/.claude/settings.json"
if [ -f "$CLAUDE_SETTINGS" ]; then
    # Extract ANTHROPIC_FOUNDRY_BASE_URL from settings if not already set
    if [ -z "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
        FOUNDRY_URL=$(python3 -c "import json; d=json.load(open('$CLAUDE_SETTINGS')); print(d.get('env',{}).get('ANTHROPIC_FOUNDRY_BASE_URL',''))" 2>/dev/null)
        [ -n "$FOUNDRY_URL" ] && export ANTHROPIC_FOUNDRY_BASE_URL="$FOUNDRY_URL"
    fi
fi

# ---------------------------------------------------------------------------
# GitHub zero-touch sign-in via stored Personal Access Token
# Orgs that enforce SAML SSO + MFA block headless device-flow auth, so a
# PAT (SSO-authorized once, saved by gh-token-setup.command) is the reliable
# no-browser path. Log in now so GitHub is ready before the user clicks.
# Token source: GH_TOKEN env, or the local-only file in the mounted volume.
# ---------------------------------------------------------------------------
GH_TOKEN_FILE="/home/coder/Documents/.ccdw/gh-token"
GH_PAT="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -z "$GH_PAT" ] && [ -f "$GH_TOKEN_FILE" ]; then
    GH_PAT="$(tr -d '[:space:]' < "$GH_TOKEN_FILE" 2>/dev/null)"
fi
if [ -n "$GH_PAT" ]; then
    if ! su-exec coder gh auth status >/dev/null 2>&1; then
        if printf '%s\n' "$GH_PAT" | su-exec coder gh auth login --with-token >/dev/null 2>&1; then
            su-exec coder gh auth setup-git >/dev/null 2>&1 || true
            echo -e "${GREEN}[OK]${NC} GitHub signed in via stored token"
            slog "ok|GitHub|Signed in via token"
        else
            echo -e "${YELLOW}[WARN]${NC} GitHub token present but sign-in failed (check SSO authorization)"
            slog "error|GitHub|Token sign-in failed (check SSO authorization)"
        fi
    fi
fi
unset GH_PAT

# ---------------------------------------------------------------------------
# Start code-server (VS Code in browser) in background
# No password required -- this is a local-only container.
# If you need password auth, set CODE_SERVER_AUTH=password in .env.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# From here on, everything runs as the coder user
# ---------------------------------------------------------------------------
slog "busy|VS Code|Starting on port 8080..."
echo -e "${GREEN}[OK]${NC} Starting code-server on port 8080..."
export XDG_CONFIG_HOME=/tmp/.config
mkdir -p /tmp/.config
chown -R coder:coder /tmp/.config 2>/dev/null || true

# Clear code-server's cached workspace state so it always opens $PROJECTS_DIR
# The .vscdb files persist last-opened folder across container recreations
find /home/coder/.local/share/code-server/ -name "*.vscdb*" -delete 2>/dev/null || true

# ---------------------------------------------------------------------------
# Code-server settings: panel on right, Claude Code terminal profile
# ---------------------------------------------------------------------------
CS_USER_DIR="/home/coder/.local/share/code-server/User"
CS_CONFIG="/opt/claude-code-docker/config"
mkdir -p "$CS_USER_DIR"
if [ ! -f "$CS_USER_DIR/settings.json" ]; then
    cp "$CS_CONFIG/code-server-settings.json" "$CS_USER_DIR/settings.json"
fi
# Workspace task: auto-launch Claude Code on folder open
VSCODE_DIR="$GITHUB_DIR/.vscode"
mkdir -p "$VSCODE_DIR"
if [ ! -f "$VSCODE_DIR/tasks.json" ]; then
    cp "$CS_CONFIG/code-server-tasks.json" "$VSCODE_DIR/tasks.json"
fi
chown -R coder:coder "$CS_USER_DIR" "$VSCODE_DIR" 2>/dev/null || true

# Continue.dev was removed: its native core binary is downloaded per-platform
# from S3 and the linux-arm64 build is chronically missing ("No body returned"),
# breaking on Apple Silicon. No Continue config is written. Claude Code
# (CLI + Chat + Workshop) is the AI; it does not depend on Continue.

CS_AUTH="${CODE_SERVER_AUTH:-none}"
if [ "$CS_AUTH" = "password" ]; then
    if [ -z "$CODE_SERVER_PASSWORD" ]; then
        export CODE_SERVER_PASSWORD=$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)
    fi
fi

export NODE_EXTRA_CA_CERTS="${NODE_EXTRA_CA_CERTS:-/etc/ssl/certs/ca-certificates.crt}"
export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
export NODE_OPTIONS="--use-openssl-ca ${NODE_OPTIONS:-}"
su-exec coder code-server \
    --bind-addr "0.0.0.0:${CS_INT_PORT}" \
    --auth "$CS_AUTH" \
    --config /tmp/.config/code-server/config.yaml \
    --disable-telemetry \
    --disable-update-check \
    "$PROJECTS_DIR" &
# nav-proxy fronts code-server on the public :8080 and injects the top-nav
start_nav_proxy 8080 "$CS_INT_PORT" vscode
slog "ok|VS Code|Running on port 8080"

# ---------------------------------------------------------------------------
# Start Workshop server (Business User IDE)
# ---------------------------------------------------------------------------
slog "busy|Workshop|Starting on port ${WORKSHOP_PORT:-9200}..."
echo -e "${GREEN}[OK]${NC} Starting Workshop on port ${WORKSHOP_PORT:-9200}..."
su-exec coder "$SCRIPTS_DIR/workshop-server.sh" &
slog "ok|Workshop|Running"

# ---------------------------------------------------------------------------
# Start Claude Chat server (standalone chat interface)
# ---------------------------------------------------------------------------
slog "busy|Claude Chat|Starting on port ${CHAT_PORT:-3002}..."
echo -e "${GREEN}[OK]${NC} Starting Claude Chat on port ${CHAT_PORT:-3002}..."
su-exec coder "$SCRIPTS_DIR/chat-server.sh" &
slog "ok|Claude Chat|Running"

# ---------------------------------------------------------------------------
# Start welcome page server (landing page with status + links)
# ---------------------------------------------------------------------------
slog "busy|Dashboard|Starting on port 3000..."
echo -e "${GREEN}[OK]${NC} Starting welcome page on port 3000..."
su-exec coder "$SCRIPTS_DIR/welcome-server.sh" &

# ---------------------------------------------------------------------------
# Start health monitor (self-healing: replaces watchdog + token-monitor)
# ---------------------------------------------------------------------------
su-exec coder "$SCRIPTS_DIR/health-monitor.sh" &
echo -e "${GREEN}[OK]${NC} Health monitor started (self-healing enabled)."
slog "ok|Health Monitor|Running"

# ---------------------------------------------------------------------------
# Start ttyd (web terminal) -- this is the foreground process
# Uses tmux so browser reconnects resume the same session.
# ---------------------------------------------------------------------------
slog "busy|Web Terminal|Starting on port 7681..."
echo -e "${GREEN}[OK]${NC} Starting web terminal on port 7681..."
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "  Workshop:      ${GREEN}http://localhost:${WORKSHOP_PORT:-9200}${NC}"
echo -e "  Claude Chat:   ${GREEN}http://localhost:${CHAT_PORT:-3002}${NC}"
echo -e "  Dashboard:     ${GREEN}http://localhost:${WELCOME_PORT:-3000}${NC}"
echo -e "  Web Terminal:  ${GREEN}http://localhost:${TTYD_PORT:-7681}${NC}"
echo -e "  New Terminal:  ${GREEN}http://localhost:${TTYD_NEW_PORT:-7682}${NC}"
echo -e "  VS Code:       ${GREEN}http://localhost:${CODE_SERVER_PORT:-8080}${NC}"
if [ "$CS_AUTH" = "password" ]; then
    echo -e "  VS Code Pass:  ${GREEN}${CODE_SERVER_PASSWORD}${NC}"
else
    echo -e "  VS Code Auth:  ${GREEN}None (local access)${NC}"
fi
echo -e "${BLUE}========================================${NC}"
echo ""

# ttyd connects to a tmux session so closing the browser tab and
# reopening reconnects to the same terminal (session persistence).
# Font stack: system monospace fonts with good Unicode block element coverage
# (needed for Claude Code's logo and box-drawing UI)
TTYD_FONT='fontFamily="Menlo, Cascadia Mono, Consolas, DejaVu Sans Mono, Liberation Mono, monospace"'

# Native-feel xterm client options (applied to both ttyd instances):
#   macOptionIsMeta   Option key sends Meta/Alt (Option+b/f word-nav, meta binds)
#   scrollback        deep scrollback like a real terminal
#   rendererType      canvas renderer (fast, stable in WKWebView)
#   disableLeaveAlert drop the "are you sure you want to leave" prompt
#   theme             macOS-dark palette matching the CCDW UI
TTYD_THEME='theme={"background":"#0b0e14","foreground":"#c9d1d9","cursor":"#c9d1d9","cursorAccent":"#0b0e14","selectionBackground":"#264f78"}'
TTYD_OPTS=(
    --client-option "$TTYD_FONT"
    --client-option 'fontSize=14'
    --client-option 'cursorBlink=true'
    --client-option 'enableClipboard=true'
    --client-option 'macOptionIsMeta=true'
    --client-option 'scrollback=10000'
    --client-option 'rendererType=canvas'
    --client-option 'disableLeaveAlert=true'
    --client-option "$TTYD_THEME"
)

# Second ttyd (port 7682): each browser tab gets a NEW tmux window.
# Use this for additional terminals without disturbing the main session.
echo -e "${GREEN}[OK]${NC} New Terminal service on port ${TTYD_NEW_PORT:-7682}..."
su-exec coder ttyd \
    --port "$TTYD_NEW_INT_PORT" \
    --writable \
    "${TTYD_OPTS[@]}" \
    "$SCRIPTS_DIR/new-terminal.sh" &
# nav-proxy fronts the new-terminal ttyd on its public port and injects the top-nav
start_nav_proxy "${TTYD_NEW_PORT:-7682}" "$TTYD_NEW_INT_PORT" terminal

# Tmux config (navigation breadcrumb, mouse, scrollback)
TMUX_CONF="/opt/claude-code-docker/config/tmux.conf"

slog "ok|Web Terminal|Running"
slog "ok|Ready|All services started"

# Main ttyd (public 7681): binds an internal port; nav-proxy owns 7681 and
# injects the top-nav. Start the proxy first (background), then exec ttyd as the
# foreground/PID-1 process so the container lifecycle still tracks the terminal.
start_nav_proxy 7681 "$TTYD_INT_PORT" terminal

# Main ttyd always reconnects to the same tmux session.
exec su-exec coder ttyd \
    --port "$TTYD_INT_PORT" \
    --writable \
    "${TTYD_OPTS[@]}" \
    tmux -f "$TMUX_CONF" new-session -A -s main "bash --init-file $SCRIPTS_DIR/shell-init.sh"
