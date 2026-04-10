#!/usr/bin/env bash
# =============================================================================
# Shell initialization for ttyd sessions
# Sources environment, runs setup wizard if needed, configures prompt
# =============================================================================

# Source user profile
[ -f /home/coder/.bashrc ] && source /home/coder/.bashrc

# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Load .env if it exists in workspace
# ---------------------------------------------------------------------------
if [ -f /home/coder/Documents/GitHub/.env ]; then
    set -a
    source /home/coder/Documents/GitHub/.env
    set +a
fi

# ---------------------------------------------------------------------------
# Setup wizard (first run, no provider configured)
# ---------------------------------------------------------------------------
if [ "${RUN_SETUP_WIZARD}" = "1" ]; then
    /opt/claude-code-docker/scripts/setup-wizard.sh
    unset RUN_SETUP_WIZARD
fi

# ---------------------------------------------------------------------------
# Custom prompt
# ---------------------------------------------------------------------------
export PS1="\[\033[0;34m\]claude-code\[\033[0m\]:\[\033[0;32m\]\w\[\033[0m\]\$ "

# ---------------------------------------------------------------------------
# Azure token idle warning (picked up from background monitor)
# ---------------------------------------------------------------------------
WARNING_FILE="/tmp/.azure-token-warning"
if [ -f "$WARNING_FILE" ]; then
    TOKEN_WARN=$(cat "$WARNING_FILE" 2>/dev/null)
    if [ "$TOKEN_WARN" = "expired" ]; then
        echo ""
        echo -e "  ${RED}================================================${NC}"
        echo -e "  ${RED}  Your Azure token has expired!${NC}"
        echo -e "  ${RED}  Run 'az login' on your HOST machine to fix.${NC}"
        echo -e "  ${RED}================================================${NC}"
        echo ""
    elif [ -n "$TOKEN_WARN" ]; then
        echo ""
        echo -e "  ${YELLOW}================================================${NC}"
        echo -e "  ${YELLOW}  Azure token expires in ~${TOKEN_WARN} minutes.${NC}"
        echo -e "  ${YELLOW}  Run 'az login' on your host soon.${NC}"
        echo -e "  ${YELLOW}================================================${NC}"
        echo ""
    fi
fi

# ---------------------------------------------------------------------------
# Welcome message
# ---------------------------------------------------------------------------
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Claude Code Docker${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check AI provider status
if [ -n "$ANTHROPIC_API_KEY" ]; then
    echo -e "  AI Provider:   ${GREEN}Anthropic API${NC}"
elif [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
    echo -e "  AI Provider:   ${GREEN}Azure AI Foundry${NC}"
    # Check Azure token health (with VPN detection)
    /opt/claude-code-docker/scripts/check-azure-token.sh
elif [ "${CLAUDE_CODE_USE_BEDROCK}" = "1" ]; then
    echo -e "  AI Provider:   ${GREEN}AWS Bedrock${NC}"
else
    echo -e "  AI Provider:   ${RED}Not configured${NC}"
    echo -e "  Run: ${YELLOW}/opt/claude-code-docker/scripts/setup-wizard.sh${NC}"
fi

# Check Docker
if docker info >/dev/null 2>&1; then
    echo -e "  Docker:        ${GREEN}Connected${NC}"
else
    echo -e "  Docker:        ${YELLOW}Not available${NC} (mount /var/run/docker.sock)"
fi

# Check skills
if [ -d /home/coder/.claude/make-it ]; then
    VERSION=$(cat /home/coder/.claude/make-it/VERSION 2>/dev/null || echo "unknown")
    echo -e "  Skills:        ${GREEN}v${VERSION}${NC}"
else
    echo -e "  Skills:        ${YELLOW}Not installed${NC}"
fi

# ---------------------------------------------------------------------------
# Aliases for convenience
# ---------------------------------------------------------------------------
alias cc='/opt/claude-code-docker/scripts/claude-wrapper.sh'
alias doctor='/opt/claude-code-docker/scripts/doctor.sh'
alias backup='/opt/claude-code-docker/scripts/backup.sh'
alias restore='/opt/claude-code-docker/scripts/restore.sh'

# ---------------------------------------------------------------------------
# First-run walkthrough (only shown once, ever)
# ---------------------------------------------------------------------------
FIRST_RUN_MARKER="/home/coder/.claude/.first-run-done"
if [ ! -f "$FIRST_RUN_MARKER" ]; then
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Welcome! Here's how to get started:${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "  ${BOLD}Step 1:${NC} Type ${GREEN}claude${NC} and press Enter"
    echo -e "         This starts your AI assistant."
    echo ""
    echo -e "  ${BOLD}Step 2:${NC} Type ${GREEN}/make-it${NC} and press Enter"
    echo -e "         This launches the app builder. Just describe"
    echo -e "         what you want in plain English."
    echo ""
    echo -e "  ${BOLD}Helpful commands:${NC}"
    echo -e "    ${GREEN}doctor${NC}   -- Check if everything is working"
    echo -e "    ${GREEN}backup${NC}   -- Save your settings to a file"
    echo -e "    ${GREEN}restore${NC}  -- Restore settings from a backup"
    echo ""
    echo -e "  ${BLUE}========================================${NC}"
    echo ""

    # Create marker so this only shows once
    mkdir -p /home/coder/.claude
    touch "$FIRST_RUN_MARKER"
else
    echo ""
    echo -e "  Type ${GREEN}claude${NC} to start Claude Code"
    echo -e "  Type ${GREEN}doctor${NC} to troubleshoot connection issues"
    echo -e "  Type ${GREEN}/make-it${NC} inside Claude Code to build an app"
    echo ""
fi
