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
NC='\033[0m'

# ---------------------------------------------------------------------------
# Load .env if it exists in workspace
# ---------------------------------------------------------------------------
if [ -f /home/coder/workspace/.env ]; then
    set -a
    source /home/coder/workspace/.env
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
    # Check Azure token health
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

echo ""
echo -e "  Type ${GREEN}claude${NC} to start Claude Code"
echo -e "  Type ${GREEN}cc${NC} for Claude Code with friendly error messages"
echo -e "  Type ${GREEN}doctor${NC} to troubleshoot connection issues"
echo -e "  Type ${GREEN}/make-it${NC} inside Claude Code to build an app"
echo ""
