#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Entrypoint
# Starts ttyd + code-server, runs setup wizard if needed, auto-updates skills
# =============================================================================
set -e

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
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Claude Code Docker${NC}"
echo -e "${BLUE}========================================${NC}"

# ---------------------------------------------------------------------------
# Ensure workspace directory exists
# ---------------------------------------------------------------------------
if [ ! -d "$GITHUB_DIR" ]; then
    echo -e "${YELLOW}[...]${NC} Creating workspace directory..."
    mkdir -p "$GITHUB_DIR"
fi

if [ -w "$GITHUB_DIR" ]; then
    echo -e "${GREEN}[OK]${NC} Workspace: $GITHUB_DIR"
else
    echo -e "${YELLOW}[WARN]${NC} Workspace directory is not writable: $GITHUB_DIR"
    echo -e "         Projects may fail to save. Check your volume mount permissions."
fi

# ---------------------------------------------------------------------------
# Docker socket permissions
# ---------------------------------------------------------------------------
if [ -S /var/run/docker.sock ]; then
    DOCKER_SOCK_GID=$(stat -c '%g' /var/run/docker.sock 2>/dev/null || stat -f '%g' /var/run/docker.sock 2>/dev/null)
    if [ -n "$DOCKER_SOCK_GID" ] && [ "$DOCKER_SOCK_GID" != "0" ]; then
        echo -e "${GREEN}[OK]${NC} Docker socket accessible (GID: $DOCKER_SOCK_GID)"
    fi
fi

# ---------------------------------------------------------------------------
# Auto-update /make-it skills (if enabled)
# ---------------------------------------------------------------------------
if [ "${SKILLS_AUTO_UPDATE:-1}" = "1" ]; then
    echo -e "${YELLOW}[...]${NC} Checking for skill updates..."
    "$SCRIPTS_DIR/auto-update.sh" || echo -e "${YELLOW}[WARN]${NC} Skill update check failed (continuing anyway)"
fi

# ---------------------------------------------------------------------------
# Setup wizard (first run only)
# ---------------------------------------------------------------------------
if [ ! -f "$SETUP_DONE_MARKER" ] && [ -z "$ANTHROPIC_API_KEY" ] && [ -z "$CLAUDE_CODE_USE_BEDROCK" ] && [ -z "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
    echo ""
    echo -e "${YELLOW}No AI provider configured.${NC}"
    echo "The setup wizard will run in your terminal session."
    echo "Connect to the web terminal and follow the prompts."
    export RUN_SETUP_WIZARD=1
fi

# ---------------------------------------------------------------------------
# Fix volume ownership (mounted volumes may be root-owned)
# ---------------------------------------------------------------------------
for dir in /home/coder/.config /home/coder/.claude /home/coder/.azure; do
    if [ -d "$dir" ] && [ ! -w "$dir" ]; then
        # Can't chown from non-root, use a fallback location
        true
    fi
done

# ---------------------------------------------------------------------------
# Start code-server (VS Code in browser) in background
# No password required -- this is a local-only container.
# If you need password auth, set CODE_SERVER_AUTH=password in .env.
# ---------------------------------------------------------------------------
echo -e "${GREEN}[OK]${NC} Starting code-server on port 8080..."
export XDG_CONFIG_HOME=/tmp/.config
mkdir -p /tmp/.config

CS_AUTH="${CODE_SERVER_AUTH:-none}"
if [ "$CS_AUTH" = "password" ]; then
    if [ -z "$CODE_SERVER_PASSWORD" ]; then
        export CODE_SERVER_PASSWORD=$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)
    fi
fi

code-server \
    --bind-addr 0.0.0.0:8080 \
    --auth "$CS_AUTH" \
    --config /tmp/.config/code-server/config.yaml \
    --disable-telemetry \
    --disable-update-check \
    /home/coder/Documents/GitHub &

# ---------------------------------------------------------------------------
# Start welcome page server (landing page with status + links)
# ---------------------------------------------------------------------------
echo -e "${GREEN}[OK]${NC} Starting welcome page on port 3000..."
"$SCRIPTS_DIR/welcome-server.sh" &

# ---------------------------------------------------------------------------
# Start watchdog (auto-restarts code-server if it crashes)
# ---------------------------------------------------------------------------
"$SCRIPTS_DIR/watchdog.sh" &
echo -e "${GREEN}[OK]${NC} Service watchdog started."

# ---------------------------------------------------------------------------
# Start Azure token monitor (background expiry warnings)
# ---------------------------------------------------------------------------
if [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
    "$SCRIPTS_DIR/token-monitor.sh" &
    echo -e "${GREEN}[OK]${NC} Azure token monitor started."
fi

# ---------------------------------------------------------------------------
# Start ttyd (web terminal) -- this is the foreground process
# Uses tmux so browser reconnects resume the same session.
# ---------------------------------------------------------------------------
echo -e "${GREEN}[OK]${NC} Starting web terminal on port 7681..."
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "  Dashboard:     ${GREEN}http://localhost:${WELCOME_PORT:-3000}${NC}"
echo -e "  Web Terminal:  ${GREEN}http://localhost:${TTYD_PORT:-7681}${NC}"
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
exec ttyd \
    --port 7681 \
    --writable \
    tmux new-session -A -s main "bash --init-file $SCRIPTS_DIR/shell-init.sh"
