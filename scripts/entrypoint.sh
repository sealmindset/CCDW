#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Entrypoint
# Starts ttyd + code-server, runs setup wizard if needed, auto-updates skills
# =============================================================================
set -e

SCRIPTS_DIR="/opt/claude-code-docker/scripts"
ENV_FILE="/home/coder/workspace/.env"
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
if [ ! -f "$SETUP_DONE_MARKER" ] && [ -z "$ANTHROPIC_API_KEY" ] && [ -z "$CLAUDE_CODE_USE_BEDROCK" ]; then
    echo ""
    echo -e "${YELLOW}No AI provider configured.${NC}"
    echo "The setup wizard will run in your terminal session."
    echo "Connect to the web terminal and follow the prompts."
    export RUN_SETUP_WIZARD=1
fi

# ---------------------------------------------------------------------------
# Generate code-server password if not set
# ---------------------------------------------------------------------------
if [ -z "$CODE_SERVER_PASSWORD" ]; then
    if [ -f "/home/coder/.config/code-server-password" ]; then
        export CODE_SERVER_PASSWORD=$(cat /home/coder/.config/code-server-password)
    else
        export CODE_SERVER_PASSWORD=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
        mkdir -p /home/coder/.config
        echo "$CODE_SERVER_PASSWORD" > /home/coder/.config/code-server-password
    fi
fi

# ---------------------------------------------------------------------------
# Start code-server (VS Code in browser) in background
# ---------------------------------------------------------------------------
echo -e "${GREEN}[OK]${NC} Starting code-server on port 8080..."
code-server \
    --bind-addr 0.0.0.0:8080 \
    --auth password \
    --disable-telemetry \
    --disable-update-check \
    /home/coder/workspace &

# ---------------------------------------------------------------------------
# Start ttyd (web terminal) -- this is the foreground process
# ---------------------------------------------------------------------------
echo -e "${GREEN}[OK]${NC} Starting web terminal on port 7681..."
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "  Web Terminal:  ${GREEN}http://localhost:${TTYD_PORT:-7681}${NC}"
echo -e "  VS Code:       ${GREEN}http://localhost:${CODE_SERVER_PORT:-8080}${NC}"
echo -e "  VS Code Pass:  ${GREEN}${CODE_SERVER_PASSWORD}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# ttyd runs bash with the shell-init script for setup wizard support
exec ttyd \
    --port 7681 \
    --writable \
    bash --init-file "$SCRIPTS_DIR/shell-init.sh"
