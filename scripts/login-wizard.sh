#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Login Wizard
# Guided authentication flow for business users.
# Detects the configured provider and runs the appropriate login flow:
#   - Azure AI Foundry: Azure device-code sign-in
#   - AWS Bedrock: AWS SSO login
#   - Anthropic API key: no login needed
#
# Usage:
#   login-wizard.sh              # Full wizard (first run)
#   login-wizard.sh --refresh    # Token refresh (returning user)
#   login-wizard.sh --force      # Force fresh login
#   login-wizard.sh --github-only # GitHub auth only (skip AI provider)
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
GH_PID=""
TMPFILE=""
cleanup() {
    [ -n "$AZ_PID" ] && kill "$AZ_PID" 2>/dev/null
    [ -n "$GH_PID" ] && kill "$GH_PID" 2>/dev/null
    [ -n "$TMPFILE" ] && rm -f "$TMPFILE"
    tput cnorm 2>/dev/null
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

# ---------------------------------------------------------------------------
# Read provider config from JSON (new config format)
# ---------------------------------------------------------------------------
read_json() {
    local file="$1" key="$2"
    python3 -c "
import json, sys
try:
    with open('$file') as f:
        cfg = json.load(f)
    keys = '$key'.split('.')
    val = cfg
    for k in keys:
        if isinstance(val, dict) and k in val:
            val = val[k]
        else:
            sys.exit(0)
    if val is not None and val != '':
        print(val)
except:
    pass
" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Detect active provider
# ---------------------------------------------------------------------------
PROVIDER=""
if [ -n "$ANTHROPIC_API_KEY" ]; then
    PROVIDER="anthropic"
elif [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
    PROVIDER="azure-foundry"
elif [ "${CLAUDE_CODE_USE_BEDROCK}" = "1" ]; then
    PROVIDER="bedrock"
else
    DEFAULT_PROVIDER=$(read_yaml "default_provider")
    if [ "$DEFAULT_PROVIDER" = "azure-foundry" ] || [ "$DEFAULT_PROVIDER" = "bedrock" ]; then
        PROVIDER="$DEFAULT_PROVIDER"
    fi
fi

# Load provider-specific config
ENDPOINT=""
SUB_ID=""
SUB_NAME=""
TOKEN_RESOURCE=""
AWS_SSO_PROFILE=""

if [ "$PROVIDER" = "azure-foundry" ]; then
    ENDPOINT="${ANTHROPIC_FOUNDRY_BASE_URL:-$(read_yaml "providers.azure-foundry.endpoint")}"
    SUB_ID=$(read_yaml "providers.azure-foundry.subscription_id")
    SUB_NAME=$(read_yaml "providers.azure-foundry.subscription_name")
    TOKEN_RESOURCE=$(read_yaml "providers.azure-foundry.token_resource")
elif [ "$PROVIDER" = "bedrock" ]; then
    AWS_SSO_PROFILE="${AWS_PROFILE:-$(read_yaml "providers.bedrock.profile_name")}"
    if [ -z "$AWS_SSO_PROFILE" ]; then
        # Try JSON config
        AWS_SSO_PROFILE=$(read_json "/opt/claude-code-docker/config/bedrock.json" "profile_name")
    fi
    AWS_SSO_PROFILE="${AWS_SSO_PROFILE:-sso-bedrock}"
fi

# ---------------------------------------------------------------------------
# Detect what needs to be done
# ---------------------------------------------------------------------------
NEED_LOGIN=0

if [ "$PROVIDER" = "anthropic" ]; then
    # API key auth -- no login needed
    NEED_LOGIN=0
elif [ "$PROVIDER" = "azure-foundry" ]; then
    if [ -n "$ANTHROPIC_FOUNDRY_API_KEY" ]; then
        NEED_LOGIN=0
    elif [ "$MODE" = "--force" ]; then
        NEED_LOGIN=1
        az logout &>/dev/null 2>&1
        az account clear &>/dev/null 2>&1
        rm -f /home/coder/.azure/msal_token_cache.json 2>/dev/null
    else
        az account show &>/dev/null 2>&1 || NEED_LOGIN=1
    fi
elif [ "$PROVIDER" = "bedrock" ]; then
    if [ "$MODE" = "--force" ]; then
        NEED_LOGIN=1
    else
        # Check if AWS SSO session is active
        aws sts get-caller-identity --profile "$AWS_SSO_PROFILE" &>/dev/null 2>&1 || NEED_LOGIN=1
    fi
fi

# Check GitHub auth status
GH_NEED_LOGIN=0
if [ "$MODE" = "--force" ]; then
    GH_NEED_LOGIN=1
elif [ "$MODE" = "--github-only" ]; then
    gh auth status &>/dev/null 2>&1 || GH_NEED_LOGIN=1
else
    gh auth status &>/dev/null 2>&1 || GH_NEED_LOGIN=1
fi

# If --github-only, skip AI provider checks entirely
if [ "$MODE" = "--github-only" ]; then
    NEED_LOGIN=0
fi

# If nothing is needed, exit early
if [ "$NEED_LOGIN" = "0" ] && [ "$GH_NEED_LOGIN" = "0" ]; then
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
    local total="$3"
    local step_label="Step ${stage}/${total}"
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
    local total=$2
    echo ""
    printf "  "
    for i in $(seq 1 $total); do
        if [ "$i" -lt "$current" ]; then
            printf "${GREEN}●${NC}"
        elif [ "$i" -eq "$current" ]; then
            printf "${BLUE}●${NC}"
        else
            printf "${DIM}○${NC}"
        fi
        if [ "$i" -lt "$total" ]; then
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
    tput civis 2>/dev/null
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${BLUE}%s${NC} %s" "${frames[$i]}" "$message"
        i=$(( (i + 1) % 4 ))
        sleep 0.25
    done
    wait "$pid" 2>/dev/null
    SPINNER_EXIT=$?
    tput cnorm 2>/dev/null
    printf "\r%*s\r" 60 ""
}

notify_browser() {
    local url="$1" code="$2" provider="$3"
    curl -s -X POST "http://127.0.0.1:${WELCOME_PORT:-3000}/auth/start" \
        -H "Content-Type: application/json" \
        -d "{\"url\":\"$url\",\"code\":\"$code\",\"provider\":\"$provider\"}" \
        2>/dev/null &
}

show_qr() {
    local url="$1"
    if command -v qrencode &>/dev/null; then
        echo -e "  ${DIM}Or scan with your phone:${NC}"
        echo ""
        qrencode -t ANSIUTF8 -m 1 "$url" 2>/dev/null | sed 's/^/    /'
        echo ""
    fi
}

# =============================================================================
# AZURE AI FOUNDRY LOGIN FLOW
# =============================================================================

azure_preflight() {
    clear
    draw_header "Preflight Checks" 1 3
    draw_progress 1 3

    local all_pass=1

    printf "  ${DIM}○${NC} Azure CLI"
    if command -v az &>/dev/null; then
        printf "\r  ${OK} Azure CLI\n"
    else
        printf "\r  ${FAIL} Azure CLI — not installed\n"
        all_pass=0
    fi

    printf "  ${DIM}○${NC} GitHub CLI"
    if command -v gh &>/dev/null; then
        printf "\r  ${OK} GitHub CLI\n"
    else
        printf "\r  ${FAIL} GitHub CLI — not installed\n"
        all_pass=0
    fi

    printf "  ${DIM}○${NC} Internet connection"
    if curl -s --connect-timeout 5 -o /dev/null https://www.microsoft.com 2>/dev/null; then
        printf "\r  ${OK} Internet connection\n"
    else
        printf "\r  ${FAIL} Internet connection — no network\n"
        all_pass=0
    fi

    printf "  ${DIM}○${NC} Microsoft login service"
    if curl -s --connect-timeout 5 -o /dev/null https://login.microsoftonline.com 2>/dev/null; then
        printf "\r  ${OK} Microsoft login service\n"
    else
        printf "\r  ${FAIL} Microsoft login — unreachable\n"
        all_pass=0
    fi

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
            azure_preflight
            return $?
        fi
    fi

    echo ""

    if [ "$all_pass" = "0" ]; then
        echo -e "  ${YELLOW}Some checks failed. Fix the items above and try again.${NC}"
        echo ""
        read -p "  Press Enter to retry, or Ctrl+C to exit... " _
        azure_preflight
        return $?
    fi

    echo -e "  ${GREEN}All checks passed.${NC}"
    sleep 1.5
    return 0
}

azure_signin() {
    clear
    draw_header "Azure Sign In" 2 3
    draw_progress 2 3

    if [ "$NEED_LOGIN" = "0" ]; then
        local az_user
        az_user=$(az account show --query user.name -o tsv 2>/dev/null || echo "authenticated")
        echo -e "  ${OK} Already signed in as ${GREEN}${az_user}${NC}"
        sleep 1.5
        return 0
    fi

    echo -e "  Starting Azure sign-in..."
    echo ""

    TMPFILE=$(mktemp /tmp/az-login-XXXXXX)
    az login --use-device-code >"$TMPFILE" 2>&1 &
    AZ_PID=$!

    local device_code=""
    local login_url=""
    local attempts=0
    while [ -z "$device_code" ] && [ $attempts -lt 60 ]; do
        sleep 0.5
        attempts=$((attempts + 1))
        device_code=$(sed -n 's/.*enter the code \([A-Z0-9]*\) to.*/\1/p' "$TMPFILE" 2>/dev/null)
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

    clear
    draw_header "Azure Sign In" 2 3
    draw_progress 2 3

    echo -e "  Enter this code at the Microsoft sign-in page:"
    draw_code_box "$device_code"
    echo -e "  ${BOLD}▸${NC} ${BOLD}${login_url}${NC}"
    echo -e "    ${DIM}(Auto-opening if the dashboard is open in your browser)${NC}"
    notify_browser "$login_url" "$device_code" "azure"
    show_qr "$login_url"

    spinner_wait "$AZ_PID" "Waiting for you to sign in..."
    local exit_code=$SPINNER_EXIT
    AZ_PID=""
    rm -f "$TMPFILE"
    TMPFILE=""

    if [ $exit_code -ne 0 ] && ! az account show &>/dev/null; then
        echo -e "  ${FAIL} Sign-in was not completed."
        echo ""
        echo -e "  ${DIM}This can happen if the code expired or login was cancelled.${NC}"
        echo -e "  ${DIM}The code is valid for about 15 minutes.${NC}"
        echo ""
        read -p "  Press Enter to try again, or Ctrl+C to exit... " _
        NEED_LOGIN=1
        azure_signin
        return $?
    fi

    if [ -n "$SUB_ID" ]; then
        az account set --subscription "$SUB_ID" 2>/dev/null
    fi

    echo -e "  ${OK} Azure sign-in successful!"
    NEED_LOGIN=0
    sleep 1.5
    return 0
}

azure_allset() {
    clear
    draw_header "All Set" 3 3
    draw_progress 3 3

    local az_user az_sub
    az_user=$(az account show --query user.name -o tsv 2>/dev/null || echo "unknown")
    az_sub=$(az account show --query name -o tsv 2>/dev/null || echo "unknown")

    echo -e "  ${OK} Signed in as       ${GREEN}${az_user}${NC}"
    echo -e "  ${OK} Subscription       ${GREEN}${az_sub}${NC}"

    if curl -s --connect-timeout 5 -o /dev/null "${ENDPOINT:-$ANTHROPIC_FOUNDRY_BASE_URL}" 2>/dev/null; then
        echo -e "  ${OK} AI endpoint        ${GREEN}Connected${NC}"
    else
        echo -e "  ${YELLOW}!${NC} AI endpoint        ${YELLOW}Not reachable${NC}"
    fi

    local token_resource="${TOKEN_RESOURCE:-https://cognitiveservices.azure.com}"
    if az account get-access-token --resource "$token_resource" &>/dev/null; then
        echo -e "  ${OK} Session            ${GREEN}Active${NC}"
    else
        echo -e "  ${YELLOW}!${NC} Session            ${YELLOW}Could not get token${NC}"
    fi

    if docker info >/dev/null 2>&1; then
        echo -e "  ${OK} Docker             ${GREEN}Available${NC}"
    fi

    echo ""

    # Regenerate Claude Code settings with fresh token
    local claude_settings="/home/coder/.claude/settings.json"
    rm -f "$claude_settings" /home/coder/.claude/get-claude-token.sh
    "$SCRIPTS_DIR/configure-provider.sh" 2>/dev/null

    echo -e "  ${GREEN}You're all set!${NC} Type ${GREEN}claude${NC} to start Claude Code."
    echo -e "  Then type ${GREEN}/make-it${NC} to build your first app."
    echo ""
}

# =============================================================================
# AWS BEDROCK LOGIN FLOW
# =============================================================================

bedrock_preflight() {
    clear
    draw_header "Preflight Checks" 1 3
    draw_progress 1 3

    local all_pass=1

    printf "  ${DIM}○${NC} AWS CLI"
    if command -v aws &>/dev/null; then
        local aws_ver
        aws_ver=$(aws --version 2>&1 | head -1)
        if echo "$aws_ver" | grep -q "aws-cli/2"; then
            printf "\r  ${OK} AWS CLI v2\n"
        else
            printf "\r  ${FAIL} AWS CLI — v2 required (found: $aws_ver)\n"
            all_pass=0
        fi
    else
        printf "\r  ${FAIL} AWS CLI — not installed\n"
        all_pass=0
    fi

    printf "  ${DIM}○${NC} GitHub CLI"
    if command -v gh &>/dev/null; then
        printf "\r  ${OK} GitHub CLI\n"
    else
        printf "\r  ${FAIL} GitHub CLI — not installed\n"
        all_pass=0
    fi

    printf "  ${DIM}○${NC} Internet connection"
    if curl -s --connect-timeout 5 -o /dev/null https://aws.amazon.com 2>/dev/null; then
        printf "\r  ${OK} Internet connection\n"
    else
        printf "\r  ${FAIL} Internet connection — no network\n"
        all_pass=0
    fi

    printf "  ${DIM}○${NC} AWS SSO profile"
    if grep -q "\[profile ${AWS_SSO_PROFILE}\]" /home/coder/.aws/config 2>/dev/null; then
        printf "\r  ${OK} AWS SSO profile (${AWS_SSO_PROFILE})\n"
    else
        printf "\r  ${FAIL} AWS SSO profile — ${AWS_SSO_PROFILE} not found in ~/.aws/config\n"
        echo ""
        echo -e "  ${YELLOW}The AWS SSO profile is not configured.${NC}"
        echo -e "  Re-run the installer with --ai=bedrock to set it up."
        all_pass=0
    fi

    # Check AWS SSO portal is reachable
    local sso_url
    sso_url=$(read_json "/opt/claude-code-docker/config/bedrock.json" "sso_start_url")
    if [ -n "$sso_url" ]; then
        local sso_domain
        sso_domain=$(echo "$sso_url" | sed 's|/start$||')
        printf "  ${DIM}○${NC} AWS SSO portal"
        if curl -s --connect-timeout 5 -o /dev/null "$sso_domain" 2>/dev/null; then
            printf "\r  ${OK} AWS SSO portal reachable\n"
        else
            printf "\r  ${FAIL} AWS SSO portal — unreachable\n"
            all_pass=0
        fi
    fi

    # Okta group reminder
    echo -e "  ${YELLOW}?${NC} Okta group: aws-bedrock-model-access ${DIM}(verify manually)${NC}"
    echo -e "    ${YELLOW}You must be in this Okta group. If not, create an EMB ticket.${NC}"

    echo ""

    if [ "$all_pass" = "0" ]; then
        echo -e "  ${YELLOW}Some checks failed. Fix the items above and try again.${NC}"
        echo ""
        read -p "  Press Enter to retry, or Ctrl+C to exit... " _
        bedrock_preflight
        return $?
    fi

    echo -e "  ${GREEN}All checks passed.${NC}"
    sleep 1.5
    return 0
}

bedrock_signin() {
    clear
    draw_header "AWS SSO Sign In" 2 3
    draw_progress 2 3

    if [ "$NEED_LOGIN" = "0" ]; then
        echo -e "  ${OK} Already signed in via AWS SSO."
        sleep 1.5
        return 0
    fi

    echo -e "  Starting AWS SSO login for profile ${GREEN}${AWS_SSO_PROFILE}${NC}..."
    echo ""

    TMPFILE=$(mktemp /tmp/aws-sso-XXXXXX)
    aws sso login --profile "$AWS_SSO_PROFILE" >"$TMPFILE" 2>&1 &
    AZ_PID=$!

    # Wait for the SSO URL + code to appear
    local sso_url=""
    local sso_code=""
    local attempts=0
    while [ -z "$sso_url" ] && [ $attempts -lt 60 ]; do
        sleep 0.5
        attempts=$((attempts + 1))
        # AWS SSO outputs: "...open the following URL: https://device.sso..."
        sso_url=$(grep -oP 'https://device\.sso\S+' "$TMPFILE" 2>/dev/null | head -1)
        if [ -z "$sso_url" ]; then
            sso_url=$(grep -oP 'https://\S*\.awsapps\.com\S*' "$TMPFILE" 2>/dev/null | head -1)
        fi
        # AWS SSO may also output a user code
        sso_code=$(grep -oP 'code:?\s*\K[A-Z]{4}-[A-Z]{4}' "$TMPFILE" 2>/dev/null | head -1)
        if [ -z "$sso_code" ]; then
            sso_code=$(grep -oP '[A-Z]{4}-[A-Z]{4}' "$TMPFILE" 2>/dev/null | head -1)
        fi
    done

    if [ -z "$sso_url" ]; then
        # Fallback: maybe AWS CLI opened the browser directly
        echo -e "  ${YELLOW}AWS SSO is starting...${NC}"
        echo -e "  ${DIM}If a browser window opened, complete the sign-in there.${NC}"
        echo -e "  ${DIM}If not, check the output below for a URL to open manually.${NC}"
        echo ""
        cat "$TMPFILE" 2>/dev/null
    else
        clear
        draw_header "AWS SSO Sign In" 2 3
        draw_progress 2 3

        if [ -n "$sso_code" ]; then
            echo -e "  Enter this code at the AWS sign-in page:"
            draw_code_box "$sso_code"
        fi
        echo -e "  ${BOLD}▸${NC} ${BOLD}${sso_url}${NC}"
        echo -e "    ${DIM}(Auto-opening if the dashboard is open in your browser)${NC}"
        notify_browser "$sso_url" "${sso_code:-}" "bedrock"
        show_qr "$sso_url"
    fi

    echo ""
    spinner_wait "$AZ_PID" "Waiting for you to sign in..."
    local exit_code=$SPINNER_EXIT
    AZ_PID=""
    rm -f "$TMPFILE"
    TMPFILE=""

    if [ $exit_code -ne 0 ]; then
        # Verify by testing STS
        if ! aws sts get-caller-identity --profile "$AWS_SSO_PROFILE" &>/dev/null 2>&1; then
            echo -e "  ${FAIL} Sign-in was not completed."
            echo ""
            echo -e "  ${DIM}The SSO session may have expired or login was cancelled.${NC}"
            echo ""
            read -p "  Press Enter to try again, or Ctrl+C to exit... " _
            NEED_LOGIN=1
            bedrock_signin
            return $?
        fi
    fi

    echo -e "  ${OK} AWS SSO sign-in successful!"
    NEED_LOGIN=0
    sleep 1.5
    return 0
}

bedrock_allset() {
    clear
    draw_header "All Set" 3 3
    draw_progress 3 3

    local caller_id
    caller_id=$(aws sts get-caller-identity --profile "$AWS_SSO_PROFILE" --output json 2>/dev/null)

    if [ -n "$caller_id" ]; then
        local account arn
        account=$(echo "$caller_id" | python3 -c "import json,sys; print(json.load(sys.stdin).get('Account','unknown'))" 2>/dev/null)
        arn=$(echo "$caller_id" | python3 -c "import json,sys; a=json.load(sys.stdin).get('Arn',''); print(a.split('/')[-1] if '/' in a else a)" 2>/dev/null)
        echo -e "  ${OK} Signed in as       ${GREEN}${arn}${NC}"
        echo -e "  ${OK} AWS Account        ${GREEN}${account}${NC}"
    else
        echo -e "  ${YELLOW}!${NC} Could not verify AWS identity"
    fi

    local region="${AWS_REGION:-us-east-1}"
    echo -e "  ${OK} Bedrock Region     ${GREEN}${region}${NC}"
    echo -e "  ${OK} AWS Profile        ${GREEN}${AWS_SSO_PROFILE}${NC}"

    if docker info >/dev/null 2>&1; then
        echo -e "  ${OK} Docker             ${GREEN}Available${NC}"
    fi

    echo ""

    # Regenerate Claude Code settings
    "$SCRIPTS_DIR/configure-provider.sh" 2>/dev/null

    echo -e "  ${GREEN}You're all set!${NC} Type ${GREEN}claude${NC} to start Claude Code."
    echo -e "  Then type ${GREEN}/make-it${NC} to build your first app."
    echo ""
}

# =============================================================================
# GITHUB CLI LOGIN FLOW
# =============================================================================

github_signin() {
    if gh auth status &>/dev/null 2>&1; then
        local gh_user
        gh_user=$(gh api user -q .login 2>/dev/null || echo "authenticated")
        echo -e "  ${OK} GitHub: signed in as ${GREEN}${gh_user}${NC}"
        return 0
    fi

    clear
    draw_header "GitHub Sign In" 1 1
    draw_progress 1 1

    echo -e "  Starting GitHub sign-in..."
    echo ""

    TMPFILE=$(mktemp /tmp/gh-login-XXXXXX)
    # Pipe Enter to satisfy "Press Enter to open github.com..." prompt
    # xdg-open shim is a no-op so gh prints URL and waits for browser auth
    echo "" | stdbuf -oL gh auth login -p https -h github.com -w >"$TMPFILE" 2>&1 &
    GH_PID=$!

    local device_code=""
    local attempts=0
    while [ -z "$device_code" ] && [ $attempts -lt 60 ]; do
        sleep 0.5
        attempts=$((attempts + 1))
        device_code=$(sed -n 's/.*one-time code: \([A-Z0-9]*-[A-Z0-9]*\).*/\1/p' "$TMPFILE" 2>/dev/null | head -1)
    done

    if [ -z "$device_code" ]; then
        echo -e "  ${FAIL} Could not start GitHub sign-in."
        echo ""
        echo -e "  Try running manually: ${GREEN}gh auth login${NC}"
        wait "$GH_PID" 2>/dev/null
        GH_PID=""
        rm -f "$TMPFILE"
        TMPFILE=""
        echo ""
        read -p "  Press Enter to continue... " _
        return 1
    fi

    clear
    draw_header "GitHub Sign In" 1 1
    draw_progress 1 1

    echo -e "  Enter this code at the GitHub sign-in page:"
    draw_code_box "$device_code"
    echo -e "  ${BOLD}▸${NC} ${BOLD}https://github.com/login/device${NC}"
    echo -e "    ${DIM}(Auto-opening if the dashboard is open in your browser)${NC}"
    notify_browser "https://github.com/login/device" "$device_code" "github"
    show_qr "https://github.com/login/device"

    spinner_wait "$GH_PID" "Waiting for you to sign in..."
    local exit_code=$SPINNER_EXIT
    GH_PID=""
    rm -f "$TMPFILE"
    TMPFILE=""

    if [ $exit_code -ne 0 ] && ! gh auth status &>/dev/null 2>&1; then
        echo -e "  ${FAIL} GitHub sign-in was not completed."
        echo ""
        echo -e "  ${DIM}This can happen if the code expired or login was cancelled.${NC}"
        echo ""
        read -p "  Press Enter to try again, or Ctrl+C to exit... " _
        github_signin
        return $?
    fi

    # Configure git to use gh for credentials
    gh auth setup-git 2>/dev/null

    local gh_user
    gh_user=$(gh api user -q .login 2>/dev/null || echo "unknown")
    echo -e "  ${OK} GitHub sign-in successful! Logged in as ${GREEN}${gh_user}${NC}"
    sleep 1.5
    return 0
}

# =============================================================================
# Main: Route to the correct login flow
# =============================================================================

# GitHub-only mode: skip AI provider, just do GitHub
if [ "$MODE" = "--github-only" ]; then
    github_signin
    exit $?
fi

if [ "$NEED_LOGIN" = "1" ]; then
    case "$PROVIDER" in
        azure-foundry)
            azure_preflight || exit 1
            azure_signin
            azure_allset
            ;;
        bedrock)
            bedrock_preflight || exit 1
            bedrock_signin
            bedrock_allset
            ;;
        anthropic)
            echo ""
            echo -e "  ${OK} Anthropic API key is configured. No sign-in needed."
            echo -e "  Type ${GREEN}claude${NC} to start Claude Code."
            echo ""
            ;;
        *)
            echo ""
            echo -e "  ${YELLOW}No AI provider configured.${NC}"
            echo -e "  Re-run the installer with --ai=foundry, --ai=bedrock, or --ai=anthropic"
            echo ""
            exit 1
            ;;
    esac
fi

# GitHub auth runs after AI provider (or standalone via --github-only above)
if [ "$GH_NEED_LOGIN" = "1" ]; then
    github_signin
fi

# Mark first run complete
mkdir -p /home/coder/.claude
touch /home/coder/.claude/.first-run-done

exit 0
