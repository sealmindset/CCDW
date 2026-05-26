#!/usr/bin/env bash
# =============================================================================
# Claude Code Wrapper
# Wraps the claude command with friendly error handling.
# Instead of raw stack traces, shows plain-English error messages.
# =============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

# Run claude with all passed arguments, capture exit code
claude "$@"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Friendly error messages based on common failure patterns
# ---------------------------------------------------------------------------
echo ""
echo -e "${RED}========================================${NC}"
echo -e "${RED}  Something went wrong${NC}"
echo -e "${RED}========================================${NC}"
echo ""

# Check for common issues and give specific guidance
# 1. No API key / auth failure
if [ -z "$ANTHROPIC_API_KEY" ] && [ -z "$ANTHROPIC_FOUNDRY_BASE_URL" ] && [ "${CLAUDE_CODE_USE_BEDROCK}" != "1" ] && [ "${CLAUDE_CODE_PROVIDER}" != "claude" ]; then
    echo -e "  ${BOLD}Problem:${NC} No AI provider is configured."
    echo ""
    echo -e "  ${BOLD}How to fix:${NC}"
    echo -e "    Run the setup wizard: ${GREEN}/opt/claude-code-docker/scripts/setup-wizard.sh${NC}"
    echo ""
    exit $EXIT_CODE
fi

# 2. Azure token issues (skip when personal API key is set)
if [ -z "$ANTHROPIC_API_KEY" ] && [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
    if ! az account show &>/dev/null 2>&1; then
        echo -e "  ${BOLD}Problem:${NC} Your Azure login has expired."
        echo ""
        echo -e "  ${BOLD}How to fix:${NC}"
        echo -e "    Type ${GREEN}login${NC} to re-authenticate."
        echo ""
        exit $EXIT_CODE
    fi
fi

# 3. Network / connectivity with VPN detection
# Personal API key always checks api.anthropic.com (no VPN needed)
if [ -n "$ANTHROPIC_API_KEY" ]; then
    AI_ENDPOINT="https://api.anthropic.com"
else
    AI_ENDPOINT="${ANTHROPIC_FOUNDRY_BASE_URL:-https://api.anthropic.com}"
fi
if ! curl -s --connect-timeout 5 -o /dev/null "$AI_ENDPOINT" 2>/dev/null; then
    # Check if general internet works (VPN detection)
    if curl -s --connect-timeout 5 -o /dev/null https://www.google.com 2>/dev/null; then
        # Internet works but AI endpoint doesn't -- likely a VPN issue
        echo -e "  ${BOLD}Problem:${NC} Can't reach the AI service, but your internet is working."
        echo ""
        echo -e "  ${BOLD}This usually means you need to connect to VPN.${NC}"
        echo ""
        echo -e "  The AI endpoint (${YELLOW}${AI_ENDPOINT}${NC})"
        echo -e "  is on a private network that requires VPN access."
        echo ""
        echo -e "  ${BOLD}How to fix:${NC}"
        echo -e "    1. Connect to your corporate VPN on your host machine"
        echo -e "    2. Try again here"
        echo ""
    else
        echo -e "  ${BOLD}Problem:${NC} Can't reach the internet."
        echo ""
        echo -e "  ${BOLD}Possible causes:${NC}"
        echo -e "    - Your internet connection is down"
        echo -e "    - Your Wi-Fi is disconnected"
        echo -e "    - DNS is not resolving"
        echo ""
        echo -e "  ${BOLD}Try:${NC}"
        echo -e "    - Check your network connection"
        echo -e "    - Restart your Wi-Fi"
        echo -e "    - Wait a moment and try again"
        echo ""
    fi
    exit $EXIT_CODE
fi

# 4. Generic error
echo -e "  ${BOLD}Claude Code exited with an error (code: $EXIT_CODE).${NC}"
echo ""
echo -e "  ${BOLD}Things to try:${NC}"
echo -e "    1. Run ${GREEN}claude${NC} again -- sometimes it's a temporary glitch"
echo -e "    2. Check your internet/VPN connection"
echo -e "    3. Run the setup wizard: ${GREEN}/opt/claude-code-docker/scripts/setup-wizard.sh${NC}"
echo ""
echo -e "  If the problem continues, check the logs:"
echo -e "    ${GREEN}docker compose logs -f${NC} (from your host machine)"
echo ""

exit $EXIT_CODE
