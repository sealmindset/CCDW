#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Entrypoint
# Starts ttyd + code-server, runs setup wizard if needed, auto-updates skills
# =============================================================================
SCRIPTS_DIR="/opt/claude-code-docker/scripts"
GITHUB_DIR="/home/coder/Documents/GitHub"
ENV_FILE="${GITHUB_DIR}/.env"
SETUP_DONE_MARKER="/home/coder/.claude/.setup-done"

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

# ---------------------------------------------------------------------------
# Ensure workspace directory exists
# ---------------------------------------------------------------------------
if [ -d "$GITHUB_DIR" ]; then
    chown -R coder:coder "$GITHUB_DIR" 2>/dev/null || true
    echo -e "${GREEN}[OK]${NC} Workspace: $GITHUB_DIR"
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

# ---------------------------------------------------------------------------
# Ensure ~/Drives directory exists for external drive mounts
# ---------------------------------------------------------------------------
mkdir -p /home/coder/Drives
chown coder:coder /home/coder/Drives 2>/dev/null || true

# ---------------------------------------------------------------------------
# Docker socket permissions (entrypoint runs as root, so we can fix this)
# ---------------------------------------------------------------------------
if [ -S /var/run/docker.sock ]; then
    chmod 666 /var/run/docker.sock 2>/dev/null || true
    echo -e "${GREEN}[OK]${NC} Docker socket accessible"
fi

# ---------------------------------------------------------------------------
# Auto-update /make-it skills (if enabled)
# ---------------------------------------------------------------------------
if [ "${SKILLS_AUTO_UPDATE:-1}" = "1" ]; then
    echo -e "${YELLOW}[...]${NC} Checking for skill updates..."
    su-exec coder "$SCRIPTS_DIR/auto-update.sh" || echo -e "${YELLOW}[WARN]${NC} Skill update check failed (continuing anyway)"
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
fi

# ---------------------------------------------------------------------------
# Fix volume ownership (mounted volumes may be root-owned)
# ---------------------------------------------------------------------------
for dir in /home/coder/.config /home/coder/.claude /home/coder/.azure /home/coder/.aws \
           /home/coder/.gitconfig.d /home/coder/.local /home/coder/.continue \
           /home/coder/.npm /home/coder/go; do
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
"$SCRIPTS_DIR/configure-provider.sh"

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
# Start code-server (VS Code in browser) in background
# No password required -- this is a local-only container.
# If you need password auth, set CODE_SERVER_AUTH=password in .env.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# From here on, everything runs as the coder user
# ---------------------------------------------------------------------------
echo -e "${GREEN}[OK]${NC} Starting code-server on port 8080..."
export XDG_CONFIG_HOME=/tmp/.config
mkdir -p /tmp/.config
chown -R coder:coder /tmp/.config 2>/dev/null || true

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

# ---------------------------------------------------------------------------
# Continue.dev AI assistant config (auto-detect provider from Claude settings)
# ---------------------------------------------------------------------------
CONTINUE_DIR="/home/coder/.continue"
mkdir -p "$CONTINUE_DIR"
if [ ! -f "$CONTINUE_DIR/config.json" ]; then
    python3 -c "
import json, os, sys
config = {'models': [], 'allowAnonymousTelemetry': False}
env = {}
sp = '/home/coder/.claude/settings.json'
if os.path.isfile(sp):
    with open(sp) as f:
        env = json.load(f).get('env', {})
api_key = os.environ.get('ANTHROPIC_API_KEY','') or env.get('ANTHROPIC_API_KEY','')
foundry  = os.environ.get('ANTHROPIC_FOUNDRY_BASE_URL','') or env.get('ANTHROPIC_FOUNDRY_BASE_URL','')
if api_key:
    m = {'title':'Claude','provider':'anthropic','model':'claude-sonnet-4-20250514','apiKey':api_key}
    config['models'] = [m]
    config['tabAutocompleteModel'] = {'title':'Claude Haiku','provider':'anthropic','model':'claude-haiku-4-5-20251001','apiKey':api_key}
elif foundry:
    token = env.get('ANTHROPIC_FOUNDRY_AUTH_TOKEN','')
    config['models'] = [{'title':'Claude (Foundry)','provider':'anthropic','model':'claude-sonnet-4-20250514','apiBase':foundry,'apiKey':token or 'run-az-login'}]
elif os.path.isfile('/home/coder/.aws/config'):
    config['models'] = [{'title':'Claude (Bedrock)','provider':'bedrock','model':'anthropic.claude-sonnet-4-20250514-v1:0','region':'us-east-1'}]
with open('$CONTINUE_DIR/config.json','w') as f:
    json.dump(config, f, indent=2)
" 2>/dev/null || cp "$CS_CONFIG/continue-config.json" "$CONTINUE_DIR/config.json" 2>/dev/null || true
    chown -R coder:coder "$CONTINUE_DIR" 2>/dev/null || true
fi

CS_AUTH="${CODE_SERVER_AUTH:-none}"
if [ "$CS_AUTH" = "password" ]; then
    if [ -z "$CODE_SERVER_PASSWORD" ]; then
        export CODE_SERVER_PASSWORD=$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)
    fi
fi

export NODE_EXTRA_CA_CERTS="${NODE_EXTRA_CA_CERTS:-/etc/ssl/certs/ca-certificates.crt}"
export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
su-exec coder code-server \
    --bind-addr 0.0.0.0:8080 \
    --auth "$CS_AUTH" \
    --config /tmp/.config/code-server/config.yaml \
    --disable-telemetry \
    --disable-update-check \
    /home/coder/Documents/GitHub &

# ---------------------------------------------------------------------------
# Start Workshop server (Business User IDE)
# ---------------------------------------------------------------------------
echo -e "${GREEN}[OK]${NC} Starting Workshop on port ${WORKSHOP_PORT:-9200}..."
su-exec coder "$SCRIPTS_DIR/workshop-server.sh" &

# ---------------------------------------------------------------------------
# Start welcome page server (landing page with status + links)
# ---------------------------------------------------------------------------
echo -e "${GREEN}[OK]${NC} Starting welcome page on port 3000..."
su-exec coder "$SCRIPTS_DIR/welcome-server.sh" &

# ---------------------------------------------------------------------------
# Start health monitor (self-healing: replaces watchdog + token-monitor)
# ---------------------------------------------------------------------------
su-exec coder "$SCRIPTS_DIR/health-monitor.sh" &
echo -e "${GREEN}[OK]${NC} Health monitor started (self-healing enabled)."

# ---------------------------------------------------------------------------
# Start ttyd (web terminal) -- this is the foreground process
# Uses tmux so browser reconnects resume the same session.
# ---------------------------------------------------------------------------
echo -e "${GREEN}[OK]${NC} Starting web terminal on port 7681..."
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "  Workshop:      ${GREEN}http://localhost:${WORKSHOP_PORT:-9200}${NC}"
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

# Second ttyd (port 7682): each browser tab gets a NEW tmux window.
# Use this for additional terminals without disturbing the main session.
echo -e "${GREEN}[OK]${NC} New Terminal service on port ${TTYD_NEW_PORT:-7682}..."
su-exec coder ttyd \
    --port "${TTYD_NEW_PORT:-7682}" \
    --writable \
    --client-option "$TTYD_FONT" \
    --client-option 'fontSize=14' \
    --client-option 'cursorBlink=true' \
    "$SCRIPTS_DIR/new-terminal.sh" &

# Tmux config (navigation breadcrumb, mouse, scrollback)
TMUX_CONF="/opt/claude-code-docker/config/tmux.conf"

# Main ttyd (port 7681): always reconnects to the same tmux session.
exec su-exec coder ttyd \
    --port 7681 \
    --writable \
    --client-option "$TTYD_FONT" \
    --client-option 'fontSize=14' \
    --client-option 'cursorBlink=true' \
    tmux -f "$TMUX_CONF" new-session -A -s main "bash --init-file $SCRIPTS_DIR/shell-init.sh"
