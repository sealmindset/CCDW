#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Setup Wizard
# Interactive provider selection. Runs if no provider is auto-configured.
# Reads available providers from config/providers.yml.
# =============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPTS_DIR="/opt/claude-code-docker/scripts"
CONFIG_FILE="/opt/claude-code-docker/config/providers.yml"

# ---------------------------------------------------------------------------
# Read provider names from YAML
# ---------------------------------------------------------------------------
AZ_NAME=$(python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
print(cfg.get('providers',{}).get('azure-foundry',{}).get('name','Azure AI Foundry'))
" 2>/dev/null || echo "Azure AI Foundry")

BK_NAME=$(python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
print(cfg.get('providers',{}).get('bedrock',{}).get('name','AWS Bedrock'))
" 2>/dev/null || echo "AWS Bedrock")

AK_NAME=$(python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
print(cfg.get('providers',{}).get('api-key',{}).get('name','Anthropic API (Personal)'))
" 2>/dev/null || echo "Anthropic API (Personal)")

echo ""
echo -e "${BLUE}  Claude Code Docker - Setup${NC}"
echo ""
echo "  How will you connect to Claude?"
echo ""
echo -e "  ${BOLD}1${NC}  ${AZ_NAME}      Company Azure subscription"
echo -e "  ${BOLD}2${NC}  ${BK_NAME}            Company AWS account"
echo -e "  ${BOLD}3${NC}  ${AK_NAME}  Personal use"
echo ""

while true; do
    read -p "  Select (1/2/3): " CHOICE
    case "$CHOICE" in
        1|2|3) break ;;
        *) echo -e "  ${YELLOW}Enter 1, 2, or 3.${NC}" ;;
    esac
done

echo ""

case "$CHOICE" in
    1)
        # Azure AI Foundry — endpoint comes from providers.yml
        DEFAULT_ENDPOINT=$(python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
print(cfg.get('providers',{}).get('azure-foundry',{}).get('endpoint',''))
" 2>/dev/null)

        echo -e "  ${BOLD}${AZ_NAME}${NC}"
        echo ""
        if [ -n "$DEFAULT_ENDPOINT" ]; then
            echo -e "  Endpoint: ${GREEN}${DEFAULT_ENDPOINT}${NC}"
            read -p "  Press Enter to use this, or type a different URL: " CUSTOM_URL
            ENDPOINT="${CUSTOM_URL:-$DEFAULT_ENDPOINT}"
        else
            read -p "  Endpoint URL: " ENDPOINT
        fi

        if [ -z "$ENDPOINT" ]; then
            echo -e "  ${RED}No endpoint. Setup cancelled.${NC}"
            exit 1
        fi

        # Set the env var and re-run configure-provider.sh
        export ANTHROPIC_FOUNDRY_BASE_URL="$ENDPOINT"
        # Remove existing settings so configure-provider regenerates
        rm -f /home/coder/.claude/settings.json
        "$SCRIPTS_DIR/configure-provider.sh"
        ;;

    2)
        # AWS Bedrock
        DEFAULT_REGION=$(python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
print(cfg.get('providers',{}).get('bedrock',{}).get('region','us-east-1'))
" 2>/dev/null)

        echo -e "  ${BOLD}${BK_NAME}${NC}"
        echo ""
        read -p "  AWS Region (default: ${DEFAULT_REGION}): " CUSTOM_REGION
        export AWS_REGION="${CUSTOM_REGION:-$DEFAULT_REGION}"
        export CLAUDE_CODE_USE_BEDROCK=1

        rm -f /home/coder/.claude/settings.json
        "$SCRIPTS_DIR/configure-provider.sh"
        ;;

    3)
        # Anthropic API Key (personal)
        echo -e "  ${BOLD}${AK_NAME}${NC}"
        echo "  Get your key at: https://console.anthropic.com/settings/keys"
        echo ""
        read -sp "  API key (starts with sk-ant-): " API_KEY
        echo ""

        if [ -z "$API_KEY" ]; then
            echo -e "  ${RED}No key provided. Setup cancelled.${NC}"
            exit 1
        fi

        export ANTHROPIC_API_KEY="$API_KEY"
        rm -f /home/coder/.claude/settings.json
        "$SCRIPTS_DIR/configure-provider.sh"

        # Save key to .env so it persists
        mkdir -p /home/coder/Documents/GitHub
        echo "ANTHROPIC_API_KEY=$API_KEY" > /home/coder/Documents/GitHub/.env
        ;;
esac

# Mark setup as done
mkdir -p /home/coder/.claude
touch /home/coder/.claude/.setup-done

echo ""
echo -e "  ${GREEN}Done!${NC} Type ${GREEN}claude${NC} to start Claude Code."
echo ""
