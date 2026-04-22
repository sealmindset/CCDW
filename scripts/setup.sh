#!/bin/sh
# Setup -- Open the AI Provider Setup wizard
# Prints the setup URL for the user to open in their browser.

WORKSHOP_PORT="${WORKSHOP_PORT:-9200}"
HOST="${HOSTNAME:-localhost}"

NC='\033[0m'
BOLD='\033[1m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'

echo ""
echo -e "${BOLD}AI Provider Setup${NC}"
echo -e "Configure Claude Code, OpenAI, Azure, or AWS Bedrock credentials."
echo ""

# Check if Workshop is running
if curl -sf "http://127.0.0.1:${WORKSHOP_PORT}/health" >/dev/null 2>&1; then
    echo -e "${GREEN}Workshop is running.${NC} Open this URL in your browser:"
    echo ""
    echo -e "  ${CYAN}${BOLD}http://localhost:${WORKSHOP_PORT}/setup.html${NC}"
    echo ""
else
    echo -e "${YELLOW}Workshop is not running on port ${WORKSHOP_PORT}.${NC}"
    echo -e "Start it first, or configure manually:"
    echo ""
    echo -e "  ${CYAN}claude${NC}  -- then use ${CYAN}/provider${NC} to configure interactively"
    echo ""
fi

# Show current status
SETTINGS="/home/coder/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
    if grep -q "ANTHROPIC_API_KEY" "$SETTINGS" 2>/dev/null; then
        echo -e "Current provider: ${GREEN}Anthropic API${NC}"
    elif grep -q "ANTHROPIC_FOUNDRY_BASE_URL" "$SETTINGS" 2>/dev/null; then
        echo -e "Current provider: ${GREEN}Azure AI Foundry${NC}"
    elif grep -q "CLAUDE_CODE_USE_BEDROCK" "$SETTINGS" 2>/dev/null; then
        echo -e "Current provider: ${GREEN}AWS Bedrock${NC}"
    else
        echo -e "Current provider: ${YELLOW}Unknown (settings.json exists but no known provider detected)${NC}"
    fi
elif [ -n "$ANTHROPIC_API_KEY" ]; then
    echo -e "Current provider: ${GREEN}Anthropic API (env var)${NC}"
else
    echo -e "Current provider: ${YELLOW}Not configured${NC}"
fi

echo ""
