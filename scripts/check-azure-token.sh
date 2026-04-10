#!/usr/bin/env bash
# =============================================================================
# Azure Token Health Check
# Detects expired/missing Azure CLI tokens and provides plain-English guidance.
# Called from shell-init.sh on each terminal session.
# =============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

# Only run if Azure AI Foundry is the configured provider
if [ -z "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
    exit 0
fi

# Check if Azure CLI is available
if ! command -v az &> /dev/null; then
    echo -e "  Azure Token:   ${RED}Azure CLI not installed${NC}"
    echo -e "                 ${YELLOW}The container needs Azure CLI to authenticate.${NC}"
    exit 1
fi

# Check if logged in
if ! az account show &> /dev/null 2>&1; then
    echo -e "  Azure Token:   ${RED}Not logged in${NC}"
    echo ""
    echo -e "  ${YELLOW}Your Azure session has expired or is not set up.${NC}"
    echo -e "  ${BOLD}To fix this, run on your HOST machine (not here):${NC}"
    echo ""
    echo -e "    ${GREEN}az login${NC}"
    echo ""
    echo -e "  The container shares your host's Azure credentials,"
    echo -e "  so logging in on your host will fix it here too."
    echo ""
    exit 1
fi

# Try to get a token and check expiry
TOKEN_JSON=$(az account get-access-token --resource https://cognitiveservices.azure.com 2>/dev/null)
if [ $? -ne 0 ]; then
    echo -e "  Azure Token:   ${RED}Could not get token${NC}"
    echo ""
    echo -e "  ${YELLOW}Your Azure login may have expired.${NC}"
    echo -e "  ${BOLD}To fix this, run on your HOST machine:${NC}"
    echo ""
    echo -e "    ${GREEN}az login${NC}"
    echo ""
    exit 1
fi

# Parse expiry time (works with both GNU and BSD date)
EXPIRES_ON=$(echo "$TOKEN_JSON" | grep -o '"expiresOn"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"expiresOn"[[:space:]]*:[[:space:]]*"//' | sed 's/"//')
if [ -n "$EXPIRES_ON" ]; then
    # Try to compute minutes remaining
    EXPIRY_EPOCH=$(date -d "$EXPIRES_ON" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$EXPIRES_ON" +%s 2>/dev/null)
    NOW_EPOCH=$(date +%s)

    if [ -n "$EXPIRY_EPOCH" ]; then
        REMAINING=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 60 ))

        if [ "$REMAINING" -le 0 ]; then
            echo -e "  Azure Token:   ${RED}Expired${NC}"
            echo ""
            echo -e "  ${YELLOW}Your Azure token has expired.${NC}"
            echo -e "  ${BOLD}To fix this, run on your HOST machine:${NC}"
            echo ""
            echo -e "    ${GREEN}az login${NC}"
            echo ""
            exit 1
        elif [ "$REMAINING" -le 10 ]; then
            echo -e "  Azure Token:   ${YELLOW}Expiring soon (${REMAINING} min left)${NC}"
            echo -e "                 ${YELLOW}Run 'az login' on your host if Claude stops working.${NC}"
        else
            echo -e "  Azure Token:   ${GREEN}Valid (${REMAINING} min remaining)${NC}"
        fi
    else
        echo -e "  Azure Token:   ${GREEN}Valid${NC}"
    fi
else
    echo -e "  Azure Token:   ${GREEN}Valid${NC}"
fi
