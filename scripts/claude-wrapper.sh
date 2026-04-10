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
if [ -z "$ANTHROPIC_API_KEY" ] && [ -z "$ANTHROPIC_FOUNDRY_BASE_URL" ] && [ "${CLAUDE_CODE_USE_BEDROCK}" != "1" ]; then
    echo -e "  ${BOLD}Problem:${NC} No AI provider is configured."
    echo ""
    echo -e "  ${BOLD}How to fix:${NC}"
    echo -e "    Run the setup wizard: ${GREEN}/opt/claude-code-docker/scripts/setup-wizard.sh${NC}"
    echo ""
    exit $EXIT_CODE
fi

# 2. Azure token issues
if [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
    if ! az account show &>/dev/null 2>&1; then
        echo -e "  ${BOLD}Problem:${NC} Your Azure login has expired."
        echo ""
        echo -e "  ${BOLD}How to fix:${NC}"
        echo -e "    On your ${BOLD}host machine${NC} (not inside this container), run:"
        echo ""
        echo -e "      ${GREEN}az login${NC}"
        echo ""
        echo -e "    Then try again here. The container shares your host's Azure credentials."
        echo ""
        exit $EXIT_CODE
    fi
fi

# 3. Network / connectivity
if ! curl -s --connect-timeout 5 -o /dev/null https://api.anthropic.com 2>/dev/null && \
   ! curl -s --connect-timeout 5 -o /dev/null "${ANTHROPIC_FOUNDRY_BASE_URL:-https://api.anthropic.com}" 2>/dev/null; then
    echo -e "  ${BOLD}Problem:${NC} Can't reach the AI service."
    echo ""
    echo -e "  ${BOLD}Possible causes:${NC}"
    echo -e "    - Your internet connection is down"
    echo -e "    - VPN is not connected (if required)"
    echo -e "    - The AI service is temporarily unavailable"
    echo ""
    echo -e "  ${BOLD}Try:${NC}"
    echo -e "    - Check your internet connection"
    echo -e "    - Connect to VPN if you're using Azure AI Foundry"
    echo -e "    - Wait a minute and try again"
    echo ""
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
