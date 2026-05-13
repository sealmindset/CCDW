#!/usr/bin/env bash
# =============================================================================
# Claude Code — Access Check (macOS / Linux)
# Checks whether your computer is ready to install. Doesn't install anything.
# Usage:
#   ./check-access.command                 Check everything
#   ./check-access.command --ai=foundry    Check for Azure AI Foundry
#   ./check-access.command --ai=bedrock    Check for AWS Bedrock
#   ./check-access.command --ai=anthropic  Check for Anthropic API
# =============================================================================

cd "$(dirname "$0")" || exit 1

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

ok()   { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; [ -n "$2" ] && echo -e "    ${YELLOW}$2${NC}"; FAIL=$((FAIL + 1)); }
info() { echo -e "  ${YELLOW}?${NC} $1 ${BLUE}(verify manually)${NC}"; [ -n "$2" ] && echo -e "    ${YELLOW}$2${NC}"; WARN=$((WARN + 1)); }

# --- Parse --ai= argument ---
AI_PROVIDER=""
for arg in "$@"; do
    case "$arg" in
        --ai=*) AI_PROVIDER="${arg#--ai=}" ;;
    esac
done

case "$AI_PROVIDER" in
    foundry|azure-foundry|azure) AI_PROVIDER="foundry" ;;
    bedrock|aws-bedrock|aws)     AI_PROVIDER="bedrock" ;;
    anthropic|api-key|apikey)    AI_PROVIDER="anthropic" ;;
    "") ;; # check all
    *)
        echo -e "${RED}Unknown provider: $AI_PROVIDER${NC}"
        echo "  Valid: --ai=foundry | --ai=bedrock | --ai=anthropic"
        exit 1 ;;
esac

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Claude Code — Access Check${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "  This checks whether your computer is ready"
echo -e "  to install Claude Code. ${BOLD}It doesn't install anything.${NC}"
echo ""
echo -e "${BOLD}  Basic Requirements${NC}"
echo ""

# --- Docker installed ---
if command -v docker &>/dev/null; then
    ok "Docker CLI installed"
else
    fail "Docker is not installed" \
         "Install Docker Desktop (docker.com) or Rancher Desktop (rancherdesktop.io)."
fi

# --- Docker running ---
if docker info &>/dev/null 2>&1; then
    ok "Docker engine is running"
else
    fail "Docker engine is not running" \
         "Open Docker Desktop or Rancher Desktop and wait for it to start."
fi

# --- Internet connectivity ---
if curl -sf --connect-timeout 5 https://www.google.com -o /dev/null 2>/dev/null; then
    ok "Internet connectivity"
else
    fail "Cannot reach the internet" \
         "Check your Wi-Fi or Ethernet connection."
fi

# --- SSL / content filter detection ---
SSL_EXIT=0
curl -sf --connect-timeout 10 https://www.google.com -o /dev/null 2>/dev/null
SSL_EXIT=$?
if [ "$SSL_EXIT" -eq 0 ]; then
    ok "SSL/TLS connections working (no content filter blocking)"
elif [ "$SSL_EXIT" -eq 35 ] || [ "$SSL_EXIT" -eq 51 ] || [ "$SSL_EXIT" -eq 60 ]; then
    fail "SSL inspection is blocking HTTPS connections (curl exit $SSL_EXIT)" \
         "Zscaler, Netskope, or another content filter is interfering. Contact IT to get added to the DevOps bypass group."
else
    fail "HTTPS connection failed (curl exit $SSL_EXIT)" \
         "Check your network connection and proxy settings."
fi

# --- GitHub Container Registry ---
if curl -sf --connect-timeout 10 https://ghcr.io -o /dev/null 2>/dev/null; then
    ok "GitHub Container Registry (ghcr.io) reachable"
else
    fail "Cannot reach ghcr.io (GitHub Container Registry)" \
         "Your network may be blocking GitHub. Contact IT or try from a different network."
fi

# --- Disk space (5 GB minimum) ---
FREE_KB=$(df -k "$(pwd)" 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "$FREE_KB" ] && [ "$FREE_KB" -ge 5242880 ] 2>/dev/null; then
    FREE_GB=$(( FREE_KB / 1048576 ))
    ok "Disk space: ${FREE_GB} GB free (5 GB required)"
elif [ -n "$FREE_KB" ]; then
    FREE_GB=$(( FREE_KB / 1048576 ))
    fail "Low disk space: ${FREE_GB} GB free (5 GB required)" \
         "Free up space before installing."
else
    info "Could not check disk space"
fi

# --- AI provider config files ---
CONFIG_COUNT=$(find config -name '*.json' -not -name '*.template.*' -not -name 'code-server*' -not -name 'continue*' 2>/dev/null | wc -l | tr -d ' ')
if [ "$CONFIG_COUNT" -gt 0 ]; then
    ok "AI provider config found (${CONFIG_COUNT} config files in config/)"
else
    fail "No AI provider config files in config/" \
         "The config/ folder should contain foundry.json, bedrock.json, or anthropic.json."
fi

# =========================================================================
# Provider-specific checks
# =========================================================================
check_foundry() {
    echo ""
    echo -e "${BOLD}  Azure AI Foundry${NC}"
    echo ""

    # Azure CLI
    if command -v az &>/dev/null; then
        ok "Azure CLI installed"
    else
        fail "Azure CLI (az) is not installed" \
             "Install from: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi

    # Azure AD login endpoint
    if curl -sf --connect-timeout 10 https://login.microsoftonline.com -o /dev/null 2>/dev/null; then
        ok "Azure AD login reachable (login.microsoftonline.com)"
    else
        fail "Cannot reach Azure AD login" \
             "Check your internet connection or VPN."
    fi

    # Foundry endpoint (read from config if available)
    ENDPOINT=""
    if [ -f "config/foundry.json" ]; then
        ENDPOINT=$(python3 -c "import json; print(json.load(open('config/foundry.json')).get('endpoint',''))" 2>/dev/null)
    fi
    if [ -n "$ENDPOINT" ]; then
        HTTP_CODE=$(curl -so /dev/null -w '%{http_code}' --connect-timeout 10 "$ENDPOINT" 2>/dev/null)
        if [ "$HTTP_CODE" != "000" ]; then
            ok "AI Foundry endpoint reachable ($HTTP_CODE)"
        else
            fail "Cannot reach AI Foundry endpoint: $ENDPOINT" \
                 "You need corporate network (office Wi-Fi) or VPN (GlobalProtect)."
        fi
    else
        info "No Foundry endpoint configured" \
             "Set endpoint in config/foundry.json to test connectivity."
    fi

    # Azure subscription (informational)
    SUB_NAME=""
    if [ -f "config/foundry.json" ]; then
        SUB_NAME=$(python3 -c "import json; print(json.load(open('config/foundry.json')).get('subscription_name',''))" 2>/dev/null)
    fi
    if [ -n "$SUB_NAME" ]; then
        info "Azure subscription: $SUB_NAME" \
             "Verify you have access to this subscription in the Azure portal."
    fi
}

check_bedrock() {
    echo ""
    echo -e "${BOLD}  AWS Bedrock${NC}"
    echo ""

    # AWS CLI v2
    if command -v aws &>/dev/null; then
        AWS_VER=$(aws --version 2>&1)
        if echo "$AWS_VER" | grep -q "aws-cli/2"; then
            ok "AWS CLI v2 installed"
        else
            fail "AWS CLI v1 found (v2 required)" \
                 "Upgrade from: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        fi
    else
        fail "AWS CLI is not installed" \
             "Install AWS CLI v2 from: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    fi

    # AWS reachable
    if curl -sf --connect-timeout 10 https://aws.amazon.com -o /dev/null 2>/dev/null; then
        ok "AWS reachable (aws.amazon.com)"
    else
        fail "Cannot reach AWS" \
             "Check your internet connection."
    fi

    # SSO portal (read from config if available)
    SSO_URL=""
    if [ -f "config/bedrock.json" ]; then
        SSO_URL=$(python3 -c "import json; print(json.load(open('config/bedrock.json')).get('sso_start_url',''))" 2>/dev/null)
    fi
    if [ -n "$SSO_URL" ]; then
        SSO_HOST=$(echo "$SSO_URL" | sed 's|https://||; s|/.*||')
        if curl -sf --connect-timeout 10 "https://$SSO_HOST" -o /dev/null 2>/dev/null; then
            ok "AWS SSO portal reachable ($SSO_HOST)"
        else
            fail "Cannot reach AWS SSO portal: $SSO_HOST" \
                 "Check your network connection."
        fi
    fi

    # Okta group (informational)
    info "Okta group: aws-bedrock-model-access" \
         "Verify you are in this Okta group. If not, create an EMB ticket requesting access."
}

check_anthropic() {
    echo ""
    echo -e "${BOLD}  Anthropic API${NC}"
    echo ""

    # API key check (just informational)
    HAS_KEY=0
    if [ -f "config/anthropic.json" ]; then
        KEY=$(python3 -c "import json; print(json.load(open('config/anthropic.json')).get('api_key',''))" 2>/dev/null)
        [ -n "$KEY" ] && HAS_KEY=1
    fi
    if [ -f ".env" ]; then
        grep -q "^ANTHROPIC_API_KEY=sk-" ".env" 2>/dev/null && HAS_KEY=1
    fi

    if [ "$HAS_KEY" -eq 1 ]; then
        ok "Anthropic API key configured"
    else
        info "No API key found yet" \
             "You will need an Anthropic API key (sk-ant-...) during installation. Get one at console.anthropic.com."
    fi

    # API reachable
    if curl -sf --connect-timeout 10 https://api.anthropic.com -o /dev/null 2>/dev/null; then
        ok "Anthropic API reachable (api.anthropic.com)"
    else
        fail "Cannot reach Anthropic API" \
             "Check your internet connection. Corporate networks may block this."
    fi
}

# Run provider checks
if [ -n "$AI_PROVIDER" ]; then
    case "$AI_PROVIDER" in
        foundry)   check_foundry ;;
        bedrock)   check_bedrock ;;
        anthropic) check_anthropic ;;
    esac
else
    # Check all providers that have config files
    [ -f "config/foundry.json" ]   && check_foundry
    [ -f "config/bedrock.json" ]   && check_bedrock
    [ -f "config/anthropic.json" ] && check_anthropic
fi

# =========================================================================
# Summary
# =========================================================================
echo ""
echo -e "${BLUE}========================================${NC}"
TOTAL=$((PASS + FAIL + WARN))
if [ "$FAIL" -eq 0 ]; then
    echo -e "  ${GREEN}Ready to install!${NC}  ($PASS passed"$([ "$WARN" -gt 0 ] && echo ", $WARN to verify")")"
    echo ""
    echo -e "  Run ${BOLD}install.command${NC} to get started."
else
    echo -e "  ${RED}${FAIL} item(s) need attention${NC} before installing."
    [ "$WARN" -gt 0 ] && echo -e "  ${YELLOW}${WARN} item(s) need manual verification.${NC}"
    echo ""
    echo -e "  Fix the items marked with ${RED}✗${NC} above, then run this check again."
fi
echo -e "${BLUE}========================================${NC}"
echo ""
read -p "Press Enter to close..."
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
