#!/usr/bin/env bash
# =============================================================================
# Azure Token Health Check
# Prints a warning ONLY if the token is expired or expiring soon.
# Silent on success. Called from shell-init.sh.
# =============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Only run if Azure AI Foundry is the configured provider
if [ -z "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
    exit 0
fi

# Check if Azure CLI is available
if ! command -v az &> /dev/null; then
    exit 0
fi

# Check if logged in
if ! az account show &> /dev/null 2>&1; then
    echo -e "  ${RED}!${NC} Azure token expired. Run ${GREEN}az login --use-device-code${NC}"
    exit 1
fi

# Read token resource from providers.yml (fallback to default)
CONFIG_FILE="/opt/claude-code-docker/config/providers.yml"
TOKEN_RESOURCE=$(python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
print(cfg.get('providers',{}).get('azure-foundry',{}).get('token_resource','https://cognitiveservices.azure.com'))
" 2>/dev/null || echo "https://cognitiveservices.azure.com")

# Try to get a token and check expiry
TOKEN_JSON=$(az account get-access-token --resource "$TOKEN_RESOURCE" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo -e "  ${RED}!${NC} Azure token expired. Run ${GREEN}az login --use-device-code${NC}"
    exit 1
fi

# Parse expiry time
EXPIRES_ON=$(echo "$TOKEN_JSON" | grep -o '"expiresOn"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"expiresOn"[[:space:]]*:[[:space:]]*"//' | sed 's/"//')
if [ -n "$EXPIRES_ON" ]; then
    EXPIRY_EPOCH=$(date -d "$EXPIRES_ON" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$EXPIRES_ON" +%s 2>/dev/null)
    NOW_EPOCH=$(date +%s)

    if [ -n "$EXPIRY_EPOCH" ]; then
        REMAINING=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 60 ))
        if [ "$REMAINING" -le 0 ]; then
            echo -e "  ${RED}!${NC} Azure token expired. Run ${GREEN}az login --use-device-code${NC}"
        elif [ "$REMAINING" -le 10 ]; then
            echo -e "  ${YELLOW}!${NC} Azure token expires in ${REMAINING} min. Run ${GREEN}az login --use-device-code${NC} soon."
        fi
        # Silent when token is healthy
    fi
fi
