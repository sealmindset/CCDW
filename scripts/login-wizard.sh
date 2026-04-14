#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Login Wizard
# Guided 3-stage authentication flow for business users.
#
# Stages:
#   1. Preflight Checks  — VPN, network, tooling
#   2. Azure Sign In     — Device code flow
#   3. All Set           — Validation summary, ready to use Claude Code
#
# Usage:
#   login-wizard.sh              # Full wizard (first run)
#   login-wizard.sh --refresh    # Token refresh (returning user, shorter text)
#   login-wizard.sh --force      # Force fresh login (fixes 429/500 errors)
# =============================================================================

# ---------------------------------------------------------------------------
# Colors and symbols
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'
OK="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"
SKIP="${GREEN}✓${NC}"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPTS_DIR="/opt/claude-code-docker/scripts"
CONFIG_FILE="/opt/claude-code-docker/config/providers.yml"
MODE="${1:-full}"

# Cleanup handler for Ctrl+C
AZ_PID=""
TMPFILE=""
cleanup() {
    [ -n "$AZ_PID" ] && kill "$AZ_PID" 2>/dev/null
    [ -n "$TMPFILE" ] && rm -f "$TMPFILE"
    tput cnorm 2>/dev/null  # Restore cursor
    echo ""
    exit 1
}
trap cleanup INT TERM

# ---------------------------------------------------------------------------
# Read provider config from YAML
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

ENDPOINT=$(read_yaml "providers.azure-foundry.endpoint")
SUB_ID=$(read_yaml "providers.azure-foundry.subscription_id")
SUB_NAME=$(read_yaml "providers.azure-foundry.subscription_name")
TOKEN_RESOURCE=$(read_yaml "providers.azure-foundry.token_resource")

# ---------------------------------------------------------------------------
# Detect what needs to be done
# ---------------------------------------------------------------------------
NEED_AZURE=0

if [ "$MODE" = "--force" ]; then
    # Force mode: always re-authenticate (fixes stale tokens, 429/500 errors)
    NEED_AZURE=1
    # Clear existing session so az login starts fresh
    az logout &>/dev/null 2>&1
    az account clear &>/dev/null 2>&1
    rm -f /home/coder/.azure/msal_token_cache.json 2>/dev/null
elif [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ] || [ -n "$ENDPOINT" ]; then
    az account show &>/dev/null 2>&1 || NEED_AZURE=1
fi

# If nothing is needed, exit early
if [ "$NEED_AZURE" = "0" ]; then
    if [ "$MODE" = "--refresh" ]; then
        echo -e "  ${OK} Already signed in. No refresh needed."
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# TUI Helpers
# ---------------------------------------------------------------------------
BOX_W=54

draw_header() {
    local title="$1"
    local stage="$2"
    local step_label="Step ${stage}/3"
    local pad=$((BOX_W - ${#title} - ${#step_label} - 4))

    echo ""
    printf "  ╭"
    printf '─%.0s' $(seq 1 $BOX_W)
    printf "╮\n"
    printf "  │  %s%*s%s  │\n" "$title" "$pad" "" "$step_label"
    printf "  ╰"
    printf '─%.0s' $(seq 1 $BOX_W)
    printf "╯\n"
}

draw_progress() {
    local current=$1
    echo ""
    printf "  "
    for i in 1 2 3; do
        if [ "$i" -lt "$current" ]; then
            printf "${GREEN}●${NC}"
        elif [ "$i" -eq "$current" ]; then
            printf "${BLUE}●${NC}"
        else
            printf "${DIM}○${NC}"
        fi
        if [ "$i" -lt 3 ]; then
            if [ "$i" -lt "$current" ]; then
                printf "${GREEN}━━${NC}"
            else
                printf "${DIM}━━${NC}"
            fi
        fi
    done
    echo ""
    echo ""
}

draw_code_box() {
    local code="$1"
    local inner_w=$(( ${#code} + 6 ))

    echo ""
    printf "  ┌"
    printf '─%.0s' $(seq 1 $inner_w)
    printf "┐\n"
    printf "  │   ${BOLD}${GREEN}%s${NC}   │\n" "$code"
    printf "  └"
    printf '─%.0s' $(seq 1 $inner_w)
    printf "┘\n"
    echo ""
}

spinner_wait() {
    local pid=$1
    local message="$2"
    local frames=('|' '/' '-' '\')
    local i=0
    tput civis 2>/dev/null  # Hide cursor
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${BLUE}%s${NC} %s" "${frames[$i]}" "$message"
        i=$(( (i + 1) % 4 ))
        sleep 0.25
    done
    wait "$pid" 2>/dev/null
    SPINNER_EXIT=$?
    tput cnorm 2>/dev/null  # Restore cursor
    printf "\r%*s\r" 60 ""  # Clear the line
}

# ---------------------------------------------------------------------------
# Stage 1: Preflight Checks
# ---------------------------------------------------------------------------
stage_preflight() {
    clear
    draw_header "Preflight Checks" 1
    draw_progress 1

    local all_pass=1

    # Check 1: Azure CLI
    printf "  ${DIM}○${NC} Azure CLI"
    if command -v az &>/dev/null; then
        printf "\r  ${OK} Azure CLI\n"
    else
        printf "\r  ${FAIL} Azure CLI — not installed\n"
        all_pass=0
    fi

    # Check 2: GitHub CLI
    printf "  ${DIM}○${NC} GitHub CLI"
    if command -v gh &>/dev/null; then
        printf "\r  ${OK} GitHub CLI\n"
    else
        printf "\r  ${FAIL} GitHub CLI — not installed\n"
        all_pass=0
    fi

    # Check 3: Internet connectivity
    printf "  ${DIM}○${NC} Internet connection"
    if curl -s --connect-timeout 5 -o /dev/null https://www.microsoft.com 2>/dev/null; then
        printf "\r  ${OK} Internet connection\n"
    else
        printf "\r  ${FAIL} Internet connection — no network\n"
        all_pass=0
    fi

    # Check 4: Microsoft login service
    printf "  ${DIM}○${NC} Microsoft login service"
    if curl -s --connect-timeout 5 -o /dev/null https://login.microsoftonline.com 2>/dev/null; then
        printf "\r  ${OK} Microsoft login service\n"
    else
        printf "\r  ${FAIL} Microsoft login — unreachable\n"
        all_pass=0
    fi

    # Check 5: AI endpoint (VPN indicator)
    if [ -n "$ENDPOINT" ]; then
        printf "  ${DIM}○${NC} AI endpoint (VPN)"
        if curl -s --connect-timeout 8 -o /dev/null "$ENDPOINT" 2>/dev/null; then
            printf "\r  ${OK} AI endpoint (VPN connected)\n"
        else
            printf "\r  ${FAIL} AI endpoint — VPN not connected\n"
            echo ""
            echo -e "  ${YELLOW}The AI endpoint is not reachable.${NC}"
            echo -e "  Make sure you're connected to your company VPN."
            echo ""
            read -p "  Press Enter to retry, or Ctrl+C to exit... " _
            stage_preflight
            return $?
        fi
    fi

    echo ""

    if [ "$all_pass" = "0" ]; then
        echo -e "  ${YELLOW}Some checks failed. Fix the items above and try again.${NC}"
        echo ""
        read -p "  Press Enter to retry, or Ctrl+C to exit... " _
        stage_preflight
        return $?
    fi

    echo -e "  ${GREEN}All checks passed.${NC}"
    sleep 1.5
    return 0
}

# ---------------------------------------------------------------------------
# Stage 2: Azure Sign In (Device Code Flow)
# ---------------------------------------------------------------------------
stage_azure() {
    clear
    draw_header "Azure Sign In" 2
    draw_progress 2

    # Already logged in? Show as pre-completed.
    if [ "$NEED_AZURE" = "0" ]; then
        local az_user
        az_user=$(az account show --query user.name -o tsv 2>/dev/null || echo "authenticated")
        echo -e "  ${OK} Already signed in as ${GREEN}${az_user}${NC}"
        sleep 1.5
        return 0
    fi

    echo -e "  Starting Azure sign-in..."
    echo ""

    # Launch az login in background, capture output for device code parsing
    TMPFILE=$(mktemp /tmp/az-login-XXXXXX)
    az login --use-device-code >"$TMPFILE" 2>&1 &
    AZ_PID=$!

    # Wait for the device code to appear in stderr output
    local device_code=""
    local login_url=""
    local attempts=0
    while [ -z "$device_code" ] && [ $attempts -lt 60 ]; do
        sleep 0.5
        attempts=$((attempts + 1))
        # Parse: "...enter the code XXXXXXXX to authenticate."
        device_code=$(sed -n 's/.*enter the code \([A-Z0-9]*\) to.*/\1/p' "$TMPFILE" 2>/dev/null)
        # Parse the URL too (in case Microsoft changes it)
        if [ -z "$login_url" ]; then
            login_url=$(sed -n 's/.*open the page \(https:\/\/[^ ]*\).*/\1/p' "$TMPFILE" 2>/dev/null)
        fi
    done

    login_url="${login_url:-https://microsoft.com/devicelogin}"

    if [ -z "$device_code" ]; then
        echo -e "  ${FAIL} Could not start the sign-in process."
        echo ""
        echo -e "  Try running manually: ${GREEN}az login --use-device-code${NC}"
        wait "$AZ_PID" 2>/dev/null
        AZ_PID=""
        rm -f "$TMPFILE"
        TMPFILE=""
        echo ""
        read -p "  Press Enter to continue... " _
        return 1
    fi

    # Redraw the screen with the device code prominently displayed
    clear
    draw_header "Azure Sign In" 2
    draw_progress 2

    echo -e "  Enter this code at the Microsoft sign-in page:"
    draw_code_box "$device_code"
    echo -e "  ${BOLD}▸${NC} ${BOLD}${login_url}${NC}"
    echo -e "    ${DIM}(Click the link above — it opens in your browser)${NC}"
    echo ""

    # Wait for az login to complete
    spinner_wait "$AZ_PID" "Waiting for you to sign in..."
    local exit_code=$SPINNER_EXIT
    AZ_PID=""
    rm -f "$TMPFILE"
    TMPFILE=""

    # Also verify by checking if az is actually logged in
    if [ $exit_code -ne 0 ] && ! az account show &>/dev/null; then
        echo -e "  ${FAIL} Sign-in was not completed."
        echo ""
        echo -e "  ${DIM}This can happen if the code expired or login was cancelled.${NC}"
        echo -e "  ${DIM}The code is valid for about 15 minutes.${NC}"
        echo ""
        read -p "  Press Enter to try again, or Ctrl+C to exit... " _
        NEED_AZURE=1
        stage_azure
        return $?
    fi

    # Auto-select the correct subscription
    if [ -n "$SUB_ID" ]; then
        az account set --subscription "$SUB_ID" 2>/dev/null
    fi

    echo -e "  ${OK} Azure sign-in successful!"
    NEED_AZURE=0
    sleep 1.5
    return 0
}

# ---------------------------------------------------------------------------
# Stage 3: All Set
# ---------------------------------------------------------------------------
stage_allset() {
    clear
    draw_header "All Set" 3
    draw_progress 3

    # --- Azure validation ---
    if [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ] || [ -n "$ENDPOINT" ]; then
        local az_user az_sub token_mins
        az_user=$(az account show --query user.name -o tsv 2>/dev/null || echo "unknown")
        az_sub=$(az account show --query name -o tsv 2>/dev/null || echo "unknown")

        echo -e "  ${OK} Signed in as       ${GREEN}${az_user}${NC}"
        echo -e "  ${OK} Subscription       ${GREEN}${az_sub}${NC}"

        # Check AI endpoint connectivity
        if curl -s --connect-timeout 5 -o /dev/null "${ENDPOINT:-$ANTHROPIC_FOUNDRY_BASE_URL}" 2>/dev/null; then
            echo -e "  ${OK} AI endpoint        ${GREEN}Connected${NC}"
        else
            echo -e "  ${YELLOW}!${NC} AI endpoint        ${YELLOW}Not reachable${NC}"
        fi

        # Token health
        local token_resource="${TOKEN_RESOURCE:-https://cognitiveservices.azure.com}"
        local token_json
        token_json=$(az account get-access-token --resource "$token_resource" 2>/dev/null)
        if [ $? -eq 0 ]; then
            local expires_on
            expires_on=$(echo "$token_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('expiresOn',''))" 2>/dev/null)
            if [ -n "$expires_on" ]; then
                local expiry_epoch now_epoch remaining
                expiry_epoch=$(date -d "$expires_on" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$expires_on" +%s 2>/dev/null)
                now_epoch=$(date +%s)
                if [ -n "$expiry_epoch" ]; then
                    remaining=$(( (expiry_epoch - now_epoch) / 60 ))
                    echo -e "  ${OK} Token valid for    ${GREEN}${remaining} minutes${NC}"
                fi
            fi
        fi
    fi

    # --- Docker ---
    if docker info >/dev/null 2>&1; then
        echo -e "  ${OK} Docker             ${GREEN}Available${NC}"
    fi

    echo ""

    # Regenerate Claude Code settings with fresh token
    if [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ] || [ -n "$ENDPOINT" ]; then
        local claude_settings="/home/coder/.claude/settings.json"
        rm -f "$claude_settings" /home/coder/.claude/get-claude-token.sh
        "$SCRIPTS_DIR/configure-provider.sh" 2>/dev/null
    fi

    echo -e "  ${GREEN}You're all set!${NC} Type ${GREEN}claude${NC} to start Claude Code."
    echo -e "  Then type ${GREEN}/make-it${NC} to build your first app."
    echo ""
    # GitHub tip (optional, not required for Claude Code)
    if ! gh auth status &>/dev/null 2>&1; then
        echo -e "  ${DIM}Tip: To push code to GitHub later, run: gh auth login${NC}"
    fi
    echo ""
}

# ---------------------------------------------------------------------------
# Main: Run the 3-stage wizard
# ---------------------------------------------------------------------------
stage_preflight  || exit 1
stage_azure
stage_allset

# Mark first run complete (if this is the first time)
mkdir -p /home/coder/.claude
touch /home/coder/.claude/.first-run-done

exit 0
