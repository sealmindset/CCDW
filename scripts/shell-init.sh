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

# Version is pinned in the Docker image — disable Claude Code auto-updater
export DISABLE_AUTOUPDATER=1

# ---------------------------------------------------------------------------
# Aliases
# ---------------------------------------------------------------------------
alias cc='/opt/claude-code-docker/scripts/claude-wrapper.sh'
alias doctor='/opt/claude-code-docker/scripts/doctor.sh'
alias backup='/opt/claude-code-docker/scripts/backup.sh'
alias restore='/opt/claude-code-docker/scripts/restore.sh'
alias login='/opt/claude-code-docker/scripts/login-wizard.sh --force'
alias setup='/opt/claude-code-docker/scripts/setup.sh'

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
# SSL proxy detection (content filter intercepting HTTPS)
# ---------------------------------------------------------------------------
SSL_PROXY=0
_ssl_rc=0
curl -s --connect-timeout 5 -o /dev/null https://www.google.com 2>/dev/null
_ssl_rc=$?
if [ "$_ssl_rc" -eq 35 ] || [ "$_ssl_rc" -eq 51 ] || [ "$_ssl_rc" -eq 60 ]; then
    SSL_PROXY=1
fi

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

AUTH_OK=0
if [ -n "$ANTHROPIC_API_KEY" ]; then
    AUTH_OK=1
elif [ -n "$ANTHROPIC_FOUNDRY_API_KEY" ]; then
    AUTH_OK=1
elif [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
    if az account show &>/dev/null 2>&1; then
        AUTH_OK=1
    elif [ -f /home/coder/.azure/msal_token_cache.json ]; then
        sleep 1
        az account show &>/dev/null 2>&1 && AUTH_OK=1
    fi
elif [ "${CLAUDE_CODE_USE_BEDROCK}" = "1" ]; then
    AWS_SSO_PROFILE="${AWS_PROFILE:-sso-bedrock}"
    if aws sts get-caller-identity --profile "$AWS_SSO_PROFILE" &>/dev/null 2>&1; then
        AUTH_OK=1
    fi
fi

# Backwards compat alias
AZ_OK=$AUTH_OK

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
    # FIRST TIME — launch the login wizard
    # The wizard handles: preflight, Azure sign-in, validation
    # =======================================================================
    if [ "$AZ_OK" = "0" ]; then
        "$SCRIPTS_DIR/login-wizard.sh"
        WIZARD_EXIT=$?

        # Re-check status after wizard
        az account show &>/dev/null 2>&1 && AZ_OK=1

        # If wizard completed, first-run marker is already set by the wizard
    else
        # Everything already logged in — just show status and mark done
        echo ""
        echo -e "${BLUE}  Welcome to Claude Code Docker!${NC}"
        echo ""
        [ "$AI_OK" = "1" ] && echo -e "  ${CHECK_PASS} AI Provider  ${GREEN}${AI_LABEL}${NC}" || echo -e "  ${CHECK_FAIL} AI Provider"
        if [ -n "$ANTHROPIC_API_KEY" ]; then
            echo -e "  ${CHECK_PASS} Auth          ${GREEN}API Key (personal)${NC}"
        elif [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
            [ "$AZ_OK" = "1" ] && echo -e "  ${CHECK_PASS} Azure login" || echo -e "  ${CHECK_FAIL} Azure login"
        fi
        [ "$DOCKER_OK" = "1" ] && echo -e "  ${CHECK_PASS} Docker" || echo -e "  ${CHECK_FAIL} Docker"
        echo ""
        if [ "$SSL_PROXY" = "1" ]; then
            echo -e "  ${YELLOW}╭──────────────────────────────────────────────────────────────────╮${NC}"
            echo -e "  ${YELLOW}│${NC} ${RED}Content filter is blocking secure connections${NC}                   ${YELLOW}│${NC}"
            echo -e "  ${YELLOW}│${NC}                                                                ${YELLOW}│${NC}"
            echo -e "  ${YELLOW}│${NC} A security tool (Zscaler, Netskope, GlobalProtect) is          ${YELLOW}│${NC}"
            echo -e "  ${YELLOW}│${NC} intercepting HTTPS. Extensions, AI, and downloads will fail.   ${YELLOW}│${NC}"
            echo -e "  ${YELLOW}│${NC}                                                                ${YELLOW}│${NC}"
            echo -e "  ${YELLOW}│${NC} ${BOLD}To fix:${NC} Pause the security tool in your menu bar or system    ${YELLOW}│${NC}"
            echo -e "  ${YELLOW}│${NC} tray, pick the longest time option, then re-enable when done.  ${YELLOW}│${NC}"
            echo -e "  ${YELLOW}╰──────────────────────────────────────────────────────────────────╯${NC}"
            echo ""
        fi
        echo -e "  ${GREEN}You're all set!${NC} Type ${GREEN}claude${NC} to start."
        echo -e "  Then type ${GREEN}/make-it${NC} to build your first app."
        echo ""
        mkdir -p /home/coder/.claude
        touch "$FIRST_RUN_MARKER"
    fi

else
    # =======================================================================
    # RETURNING USER — compact status check
    # =======================================================================

    # Pick up health monitor state
    SH_STATE_FILE="/tmp/.health-state.json"
    if [ -f "$SH_STATE_FILE" ]; then
        SH_FAILURE=$(python3 -c "import json; print(json.load(open('$SH_STATE_FILE')).get('failure_type',''))" 2>/dev/null || echo "")
        [ "$SH_FAILURE" = "azure_token_expired" ] && AZ_OK=0
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

    # --- If auth needs recovery, run wizard BEFORE showing status ---
    NEEDS_REAUTH=0
    if [ -z "$ANTHROPIC_API_KEY" ] && [ -z "$ANTHROPIC_FOUNDRY_API_KEY" ] && [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
        if [ "$AUTH_OK" = "1" ]; then
            AZ_WARN=$("$SCRIPTS_DIR/check-azure-token.sh" 2>/dev/null)
            [ -n "$AZ_WARN" ] && NEEDS_REAUTH=1
        else
            NEEDS_REAUTH=1
        fi
    elif [ "${CLAUDE_CODE_USE_BEDROCK}" = "1" ] && [ "$AUTH_OK" = "0" ]; then
        NEEDS_REAUTH=1
    fi

    if [ "$NEEDS_REAUTH" = "1" ]; then
        "$SCRIPTS_DIR/login-wizard.sh" --refresh
        # Re-check after wizard
        if [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
            az account show &>/dev/null 2>&1 && AUTH_OK=1 && NEEDS_REAUTH=0
        elif [ "${CLAUDE_CODE_USE_BEDROCK}" = "1" ]; then
            aws sts get-caller-identity --profile "${AWS_PROFILE:-sso-bedrock}" &>/dev/null 2>&1 && AUTH_OK=1 && NEEDS_REAUTH=0
        fi
        AZ_OK=$AUTH_OK
    fi

    # --- Now show the status (post-recovery if wizard ran) ---
    echo ""
    echo -e "${BLUE}  Claude Code Docker${NC}"
    echo ""

    if [ "$AI_OK" = "1" ]; then
        echo -e "  ${CHECK_PASS} AI Provider  ${GREEN}${AI_LABEL}${NC}"
    else
        echo -e "  ${CHECK_FAIL} AI Provider"
    fi

    if [ -n "$ANTHROPIC_API_KEY" ]; then
        echo -e "  ${CHECK_PASS} Auth          ${GREEN}API Key (personal)${NC}"
    elif [ -n "$ANTHROPIC_FOUNDRY_API_KEY" ]; then
        echo -e "  ${CHECK_PASS} Auth          ${GREEN}API Key (Foundry)${NC}"
    elif [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
        if [ "$AUTH_OK" = "1" ]; then
            echo -e "  ${CHECK_PASS} Azure login"
        else
            echo -e "  ${CHECK_FAIL} Azure login"
        fi
    elif [ "${CLAUDE_CODE_USE_BEDROCK}" = "1" ]; then
        if [ "$AUTH_OK" = "1" ]; then
            echo -e "  ${CHECK_PASS} AWS SSO       ${GREEN}Active${NC}"
        else
            echo -e "  ${CHECK_FAIL} AWS SSO       ${RED}Not signed in${NC}"
        fi
    fi

    if [ "$DOCKER_OK" = "1" ]; then
        echo -e "  ${CHECK_PASS} Docker"
    else
        echo -e "  ${CHECK_FAIL} Docker"
    fi

    echo ""

    if [ "$SSL_PROXY" = "1" ]; then
        echo -e "  ${YELLOW}╭──────────────────────────────────────────────────────────────────╮${NC}"
        echo -e "  ${YELLOW}│${NC} ${RED}Content filter is blocking secure connections${NC}                   ${YELLOW}│${NC}"
        echo -e "  ${YELLOW}│${NC}                                                                ${YELLOW}│${NC}"
        echo -e "  ${YELLOW}│${NC} A security tool (Zscaler, Netskope, GlobalProtect) is          ${YELLOW}│${NC}"
        echo -e "  ${YELLOW}│${NC} intercepting HTTPS. Extensions, AI, and downloads will fail.   ${YELLOW}│${NC}"
        echo -e "  ${YELLOW}│${NC}                                                                ${YELLOW}│${NC}"
        echo -e "  ${YELLOW}│${NC} ${BOLD}To fix:${NC} Pause the security tool in your menu bar or system    ${YELLOW}│${NC}"
        echo -e "  ${YELLOW}│${NC} tray, pick the longest time option, then re-enable when done.  ${YELLOW}│${NC}"
        echo -e "  ${YELLOW}╰──────────────────────────────────────────────────────────────────╯${NC}"
        echo ""
    fi

    if [ "$AI_OK" = "1" ] && [ "$AUTH_OK" = "1" ]; then
        echo -e "  ${GREEN}Ready.${NC} Type ${GREEN}claude${NC} to start, then ${GREEN}/make-it${NC} to build an app."
    elif [ "$NEEDS_REAUTH" = "1" ]; then
        echo -e "  Some items still need attention. Type ${GREEN}login${NC} to try again."
    fi
    echo ""
fi
