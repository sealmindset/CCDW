#!/usr/bin/env bash
# =============================================================================
# Shell initialization for ttyd sessions
# Sources environment, runs preflight checks, guides first-time setup
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
CHECK_PASS="${GREEN}✓${NC}"
CHECK_FAIL="${RED}✗${NC}"

SCRIPTS_DIR="/opt/claude-code-docker/scripts"
CONFIG_FILE="/opt/claude-code-docker/config/providers.yml"

# ---------------------------------------------------------------------------
# Load .env if it exists in workspace
# ---------------------------------------------------------------------------
if [ -f /home/coder/Documents/GitHub/.env ]; then
    set -a
    source /home/coder/Documents/GitHub/.env
    set +a
fi

# ---------------------------------------------------------------------------
# Custom prompt
# ---------------------------------------------------------------------------
export PS1="\[\033[0;34m\]claude-code\[\033[0m\]:\[\033[0;32m\]\w\[\033[0m\]\$ "

# ---------------------------------------------------------------------------
# Aliases
# ---------------------------------------------------------------------------
alias cc='/opt/claude-code-docker/scripts/claude-wrapper.sh'
alias doctor='/opt/claude-code-docker/scripts/doctor.sh'
alias backup='/opt/claude-code-docker/scripts/backup.sh'
alias restore='/opt/claude-code-docker/scripts/restore.sh'

# ---------------------------------------------------------------------------
# Load provider config from settings.json (generated from providers.yml)
# ---------------------------------------------------------------------------
CLAUDE_SETTINGS="/home/coder/.claude/settings.json"
if [ -f "$CLAUDE_SETTINGS" ] && [ -z "$ANTHROPIC_FOUNDRY_BASE_URL" ] && [ -z "$ANTHROPIC_API_KEY" ] && [ "${CLAUDE_CODE_USE_BEDROCK}" != "1" ]; then
    eval "$(python3 -c "
import json
try:
    with open('$CLAUDE_SETTINGS') as f:
        s = json.load(f)
    for k, v in s.get('env', {}).items():
        if v:
            print(f'export {k}=\"{v}\"')
except:
    pass
" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# Read helpers from providers.yml
# ---------------------------------------------------------------------------
read_yaml() {
    python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
val = cfg
for key in '$1'.split('.'):
    if isinstance(val, dict) and key in val:
        val = val[key]
    else:
        val = ''
        break
print(val if val is not None else '')
" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Preflight checks (run silently, store results)
# ---------------------------------------------------------------------------
AI_OK=0; AI_LABEL=""
if [ -n "$ANTHROPIC_API_KEY" ]; then
    AI_LABEL="Anthropic API"; AI_OK=1
elif [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
    AI_LABEL="Azure AI Foundry"; AI_OK=1
elif [ "${CLAUDE_CODE_USE_BEDROCK}" = "1" ]; then
    AI_LABEL="AWS Bedrock"; AI_OK=1
fi

AZ_OK=0
if [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
    az account show &>/dev/null 2>&1 && AZ_OK=1
fi

GH_OK=0
gh auth status &>/dev/null 2>&1 && GH_OK=1

DOCKER_OK=0
docker info >/dev/null 2>&1 && DOCKER_OK=1

# ---------------------------------------------------------------------------
# First-run vs. returning user
# ---------------------------------------------------------------------------
FIRST_RUN_MARKER="/home/coder/.claude/.first-run-done"

if [ ! -f "$FIRST_RUN_MARKER" ]; then
    # =======================================================================
    # FIRST TIME — guided walkthrough
    # =======================================================================
    echo ""
    echo -e "${BLUE}  Welcome to Claude Code Docker!${NC}"
    echo -e "  Let's get you set up. This only takes a few minutes."
    echo ""

    # --- Step 1: Azure login (if Azure provider and not already logged in) ---
    if [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ] && [ "$AZ_OK" = "0" ]; then
        echo -e "  ${BOLD}Step 1 of 2: Log in to Azure${NC}"
        echo -e "  This connects you to the AI service that powers Claude."
        echo ""
        echo -e "  You'll see a URL and a code. Open the URL in your browser,"
        echo -e "  enter the code, and sign in with your work account."
        echo ""
        read -p "  Press Enter to start..." _
        echo ""

        az login --use-device-code

        if az account show &>/dev/null 2>&1; then
            # Auto-select the correct subscription from providers.yml
            SUB_ID=$(read_yaml "providers.azure-foundry.subscription_id")
            SUB_NAME=$(read_yaml "providers.azure-foundry.subscription_name")
            if [ -n "$SUB_ID" ]; then
                echo ""
                echo -e "  Setting subscription to ${GREEN}${SUB_NAME}${NC}..."
                az account set --subscription "$SUB_ID" 2>/dev/null
                if [ $? -eq 0 ]; then
                    echo -e "  ${CHECK_PASS} Subscription set to ${GREEN}${SUB_NAME}${NC}"
                else
                    echo -e "  ${YELLOW}!${NC} Could not set subscription. You may need to select it manually."
                fi
            fi

            echo ""
            echo -e "  ${CHECK_PASS} ${GREEN}Azure login successful!${NC}"
            AZ_OK=1
        else
            echo ""
            echo -e "  ${CHECK_FAIL} Azure login didn't complete."
            echo -e "  You can try again later by typing: ${GREEN}az login --use-device-code${NC}"
        fi
        echo ""
    elif [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ] && [ "$AZ_OK" = "1" ]; then
        # Already logged in — make sure the right subscription is set
        SUB_ID=$(read_yaml "providers.azure-foundry.subscription_id")
        if [ -n "$SUB_ID" ]; then
            CURRENT_SUB=$(az account show --query id -o tsv 2>/dev/null)
            if [ "$CURRENT_SUB" != "$SUB_ID" ]; then
                az account set --subscription "$SUB_ID" 2>/dev/null
            fi
        fi
    fi

    # --- Step 2: GitHub login ---
    if [ "$GH_OK" = "0" ]; then
        STEP_NUM="1"
        [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ] && STEP_NUM="2"

        echo -e "  ${BOLD}Step ${STEP_NUM} of 2: Log in to GitHub${NC}"
        echo -e "  This is where your code gets saved and shared with your team."
        echo ""

        if [ "$AZ_OK" = "1" ] && [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
            echo -e "  Since you just signed in with Azure, this should be quick —"
            echo -e "  your browser will use the same login automatically."
            echo ""
        fi

        echo -e "  You'll get a one-time code and a URL."
        echo -e "  Open the URL on your computer, paste the code, and approve."
        echo -e "  ${YELLOW}(Ignore any message about opening a browser.)${NC}"
        echo ""
        read -p "  Press Enter to start..." _
        echo ""

        # --web triggers device-code flow: prints URL + code, user opens in host browser.
        # No pipes — gh needs a TTY to poll for completion.
        gh auth login --hostname github.com --git-protocol https --web

        if gh auth status &>/dev/null 2>&1; then
            echo ""
            echo -e "  ${CHECK_PASS} ${GREEN}GitHub login successful!${NC}"
            GH_OK=1
        else
            echo ""
            echo -e "  ${CHECK_FAIL} GitHub login didn't complete."
            echo -e "  You can try again later by typing: ${GREEN}gh auth login${NC}"
        fi
        echo ""
    fi

    # --- Regenerate settings.json now that Azure is logged in ---
    if [ "$AZ_OK" = "1" ] && [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
        # Force regeneration so the token helper is fresh
        rm -f "$CLAUDE_SETTINGS" /home/coder/.claude/get-claude-token.sh
        "$SCRIPTS_DIR/configure-provider.sh" 2>/dev/null
    fi

    # --- Final status ---
    echo -e "${BLUE}  Setup complete! Here's your status:${NC}"
    echo ""

    [ "$AI_OK" = "1" ] && echo -e "  ${CHECK_PASS} AI Provider  ${GREEN}${AI_LABEL}${NC}" || echo -e "  ${CHECK_FAIL} AI Provider"
    if [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
        [ "$AZ_OK" = "1" ] && echo -e "  ${CHECK_PASS} Azure login" || echo -e "  ${CHECK_FAIL} Azure login"
    fi
    [ "$GH_OK" = "1" ] && echo -e "  ${CHECK_PASS} GitHub login" || echo -e "  ${CHECK_FAIL} GitHub login"
    [ "$DOCKER_OK" = "1" ] && echo -e "  ${CHECK_PASS} Docker" || echo -e "  ${CHECK_FAIL} Docker"

    echo ""
    if [ "$AI_OK" = "1" ] && [ "$AZ_OK" = "1" ] && [ "$GH_OK" = "1" ]; then
        echo -e "  ${GREEN}You're all set!${NC} Type ${GREEN}claude${NC} to start."
        echo -e "  Then type ${GREEN}/make-it${NC} to build your first app."
    else
        echo -e "  Fix any remaining items, then type ${GREEN}claude${NC} to start."
    fi
    echo ""

    # Mark first run complete
    mkdir -p /home/coder/.claude
    touch "$FIRST_RUN_MARKER"

else
    # =======================================================================
    # RETURNING USER — compact status check
    # =======================================================================

    # Pick up background token monitor warnings
    WARNING_FILE="/tmp/.azure-token-warning"
    if [ -f "$WARNING_FILE" ]; then
        TOKEN_WARN=$(cat "$WARNING_FILE" 2>/dev/null)
        [ "$TOKEN_WARN" = "expired" ] && AZ_OK=0
    fi

    # Make sure correct subscription is set
    if [ "$AZ_OK" = "1" ] && [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
        SUB_ID=$(read_yaml "providers.azure-foundry.subscription_id")
        if [ -n "$SUB_ID" ]; then
            CURRENT_SUB=$(az account show --query id -o tsv 2>/dev/null)
            if [ "$CURRENT_SUB" != "$SUB_ID" ]; then
                az account set --subscription "$SUB_ID" 2>/dev/null
            fi
        fi
    fi

    ALL_GOOD=1
    echo ""
    echo -e "${BLUE}  Claude Code Docker${NC}"
    echo ""

    if [ "$AI_OK" = "1" ]; then
        echo -e "  ${CHECK_PASS} AI Provider  ${GREEN}${AI_LABEL}${NC}"
    else
        echo -e "  ${CHECK_FAIL} AI Provider  Run the setup wizard"
        ALL_GOOD=0
    fi

    if [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
        if [ "$AZ_OK" = "1" ]; then
            AZ_WARN=$("$SCRIPTS_DIR/check-azure-token.sh" 2>/dev/null)
            if [ -n "$AZ_WARN" ]; then
                echo -e "$AZ_WARN"
            else
                echo -e "  ${CHECK_PASS} Azure login"
            fi
        else
            echo -e "  ${CHECK_FAIL} Azure login  Run: ${GREEN}az login --use-device-code${NC}"
            ALL_GOOD=0
        fi
    fi

    if [ "$GH_OK" = "1" ]; then
        echo -e "  ${CHECK_PASS} GitHub login"
    else
        echo -e "  ${CHECK_FAIL} GitHub login Run: ${GREEN}gh auth login${NC}"
        ALL_GOOD=0
    fi

    if [ "$DOCKER_OK" = "1" ]; then
        echo -e "  ${CHECK_PASS} Docker"
    else
        echo -e "  ${CHECK_FAIL} Docker       Mount /var/run/docker.sock"
        ALL_GOOD=0
    fi

    echo ""
    if [ "$ALL_GOOD" = "1" ]; then
        echo -e "  ${GREEN}Ready.${NC} Type ${GREEN}claude${NC} to start, then ${GREEN}/make-it${NC} to build an app."
    else
        echo -e "  Fix the items above, then type ${GREEN}claude${NC} to start."
    fi
    echo ""
fi
