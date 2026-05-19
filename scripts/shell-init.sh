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
WORKSPACE="${PROJECTS_DIR:-/home/coder/Documents/GitHub}"
[ ! -d "$WORKSPACE" ] && WORKSPACE="/home/coder/Documents"
if [ -f "$WORKSPACE/.env" ]; then
    set -a
    source "$WORKSPACE/.env"
    set +a
fi

# ---------------------------------------------------------------------------
# Custom prompt
# ---------------------------------------------------------------------------
export PS1="\[\033[0;34m\]claude\[\033[0m\] \[\033[0;32m\]\W\[\033[0m\] \$ "

# Version is pinned in the Docker image — disable Claude Code auto-updater
export DISABLE_AUTOUPDATER=1

# ---------------------------------------------------------------------------
# Persistent shell history (survives container recreation)
# ---------------------------------------------------------------------------
SHELL_PERSIST="/home/coder/.shell-persist"
mkdir -p "$SHELL_PERSIST" 2>/dev/null
export HISTFILE="$SHELL_PERSIST/.bash_history"
export HISTSIZE=10000
export HISTFILESIZE=20000
shopt -s histappend

# ---------------------------------------------------------------------------
# Aliases
# ---------------------------------------------------------------------------
alias cc='/opt/claude-code-docker/scripts/claude-wrapper.sh'
alias doctor='/opt/claude-code-docker/scripts/doctor.sh'
alias backup='/opt/claude-code-docker/scripts/backup.sh'
alias restore='/opt/claude-code-docker/scripts/restore.sh'
alias login='/opt/claude-code-docker/scripts/login-wizard.sh --force'
alias setup='/opt/claude-code-docker/scripts/setup.sh'
alias mount-drive='/opt/claude-code-docker/scripts/mount-drive.sh'
alias drives='/opt/claude-code-docker/scripts/mount-drive.sh'

# ---------------------------------------------------------------------------
# Windows CLI aliases (familiar commands for business users)
# ---------------------------------------------------------------------------
alias dir='ls -la'
alias cls='clear'
alias copy='cp'
alias move='mv'
alias del='rm'
alias rd='rmdir'
alias md='mkdir -p'
alias ren='mv'
alias type='cat'
alias typeof='builtin type'
alias find-file='find . -name'
alias where='which'
alias start='open'
alias tree='find . -print | sed -e "s;[^/]*/;│   ;g;s;│   \([^│]\);├── \1;g"'
alias ipconfig='ip addr 2>/dev/null || ifconfig 2>/dev/null'
alias tasklist='ps aux'
alias systeminfo='uname -a && echo "" && cat /etc/os-release 2>/dev/null'
alias whoami='id -un'
alias hostname='cat /etc/hostname 2>/dev/null || /bin/hostname'
alias notepad='nano'
alias edit='nano'
alias explorer='ls -la'
alias attrib='ls -la'
alias more='less'
alias help='/opt/claude-code-docker/scripts/help.sh'

# Safer delete — move to trash instead of permanent delete
trash() {
    local TRASH_DIR="/home/coder/.local/share/Trash"
    mkdir -p "$TRASH_DIR"
    for f in "$@"; do
        mv "$f" "$TRASH_DIR/" 2>/dev/null && echo "Moved to trash: $f" || echo "Could not trash: $f"
    done
}
alias recycle='trash'

# Open = display file info or launch
open() {
    if [ -d "$1" ]; then
        ls -la "$1"
    elif [ -f "$1" ]; then
        file "$1"
        echo ""
        echo "To edit: nano $1"
        echo "To view: cat $1"
    else
        echo "Not found: $1"
    fi
}

# Send files to host Desktop (drag-and-drop equivalent)
send() {
    if [ $# -eq 0 ]; then
        echo -e "Usage: ${GREEN}send${NC} file1 file2 ..."
        echo "Copies files to your Desktop so you can access them on your computer."
        return 0
    fi
    local dest="/home/coder/Desktop"
    if [ ! -d "$dest" ]; then
        echo "Desktop folder not available."
        return 1
    fi
    for f in "$@"; do
        if [ -e "$f" ]; then
            cp -r "$f" "$dest/" && echo -e "${GREEN}✓${NC} Sent to Desktop: $(basename "$f")" || echo -e "${RED}✗${NC} Failed: $f"
        else
            echo -e "${RED}✗${NC} Not found: $f"
        fi
    done
}

# Fetch = copy from host Desktop/Downloads into current directory
fetch() {
    if [ $# -eq 0 ]; then
        echo -e "Usage: ${GREEN}fetch${NC} filename"
        echo ""
        echo "Looks for the file in your Desktop and Downloads folders."
        echo "Or specify a full path: fetch ~/Downloads/report.pdf"
        return 0
    fi
    for f in "$@"; do
        if [ -f "$f" ]; then
            cp "$f" . && echo -e "${GREEN}✓${NC} Copied: $(basename "$f")"
        elif [ -f "/home/coder/Desktop/$f" ]; then
            cp "/home/coder/Desktop/$f" . && echo -e "${GREEN}✓${NC} Copied from Desktop: $f"
        elif [ -f "/home/coder/Downloads/$f" ]; then
            cp "/home/coder/Downloads/$f" . && echo -e "${GREEN}✓${NC} Copied from Downloads: $f"
        else
            echo -e "${RED}✗${NC} Not found: $f"
            echo "  Checked: Desktop, Downloads"
        fi
    done
}

# ---------------------------------------------------------------------------
# Git config persistence: .gitconfig.d/ is a named volume that survives
# container recreation. Include it from .gitconfig and store user identity
# there so git user.name/email persist across restarts.
# ---------------------------------------------------------------------------
GITCONFIG_D="/home/coder/.gitconfig.d"
mkdir -p "$GITCONFIG_D"

# Include .gitconfig.d/*.conf from main .gitconfig (idempotent)
if ! git config --global --get-all include.path 2>/dev/null | grep -q '.gitconfig.d/'; then
    git config --global --add include.path "$GITCONFIG_D/user.conf" 2>/dev/null
    git config --global --add include.path "$GITCONFIG_D/local.conf" 2>/dev/null
fi

# Credential helper (written to main .gitconfig, recreated each start)
git config --global credential.https://github.com.helper '!/opt/claude-code-docker/scripts/gh-credential-helper.sh' 2>/dev/null

# Auto-configure git identity if not already in persistent config
# Priority: 1) GitHub API  2) Host ~/.gitconfig (mounted read-only)  3) manual
if [ ! -f "$GITCONFIG_D/user.conf" ] || ! grep -q '\[user\]' "$GITCONFIG_D/user.conf" 2>/dev/null; then
    GIT_ID_SET=false

    # Try GitHub API first
    if gh auth status &>/dev/null; then
        GH_NAME=$(gh api user -q .name 2>/dev/null)
        GH_EMAIL=$(gh api user -q .email 2>/dev/null)
        GH_LOGIN=$(gh api user -q .login 2>/dev/null)
        [ -z "$GH_EMAIL" ] || [ "$GH_EMAIL" = "null" ] && GH_EMAIL="${GH_LOGIN}@users.noreply.github.com"
        [ -z "$GH_NAME" ] || [ "$GH_NAME" = "null" ] && GH_NAME="$GH_LOGIN"
        if [ -n "$GH_NAME" ] && [ -n "$GH_EMAIL" ]; then
            cat > "$GITCONFIG_D/user.conf" <<GITEOF
[user]
	name = $GH_NAME
	email = $GH_EMAIL
GITEOF
            echo -e "  ${GREEN}✓${NC} Git identity: $GH_NAME <$GH_EMAIL>"
            GIT_ID_SET=true
        fi
    fi

    # Fall back to host gitconfig (mounted read-only at ~/.host-gitconfig)
    if [ "$GIT_ID_SET" = "false" ] && [ -f /home/coder/.host-gitconfig ]; then
        HOST_NAME=$(git config -f /home/coder/.host-gitconfig user.name 2>/dev/null)
        HOST_EMAIL=$(git config -f /home/coder/.host-gitconfig user.email 2>/dev/null)
        if [ -n "$HOST_NAME" ] && [ -n "$HOST_EMAIL" ]; then
            cat > "$GITCONFIG_D/user.conf" <<GITEOF
[user]
	name = $HOST_NAME
	email = $HOST_EMAIL
GITEOF
            echo -e "  ${GREEN}✓${NC} Git identity (from host): $HOST_NAME <$HOST_EMAIL>"
        fi
    fi
fi

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

        # Re-check status after wizard (wizard now handles GitHub too)
        az account show &>/dev/null 2>&1 && AZ_OK=1
        gh auth status &>/dev/null 2>&1 && GH_OK=1

        # If wizard completed, first-run marker is already set by the wizard
    else
        # AI provider already logged in — show status
        echo ""
        echo -e "${BLUE}  Welcome to Claude Code!${NC}"
        echo ""
        [ "$AI_OK" = "1" ] && echo -e "  ${CHECK_PASS} AI Provider  ${GREEN}${AI_LABEL}${NC}" || echo -e "  ${CHECK_FAIL} AI Provider"
        if [ -n "$ANTHROPIC_API_KEY" ]; then
            echo -e "  ${CHECK_PASS} Auth          ${GREEN}API Key (personal)${NC}"
        elif [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
            [ "$AZ_OK" = "1" ] && echo -e "  ${CHECK_PASS} Azure login" || echo -e "  ${CHECK_FAIL} Azure login"
        fi
        [ "$DOCKER_OK" = "1" ] && echo -e "  ${CHECK_PASS} System" || echo -e "  ${CHECK_FAIL} System"
        if [ "$GH_OK" = "1" ]; then
            GH_USER=$(gh api user -q .login 2>/dev/null || echo "authenticated")
            echo -e "  ${CHECK_PASS} GitHub        ${GREEN}${GH_USER}${NC}"
        else
            echo -e "  ${CHECK_FAIL} GitHub        ${RED}Not signed in${NC}"
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
        # GitHub not authenticated — run wizard for GitHub only
        if [ "$GH_OK" = "0" ]; then
            "$SCRIPTS_DIR/login-wizard.sh" --github-only
            gh auth status &>/dev/null 2>&1 && GH_OK=1
        fi
        echo ""
        mkdir -p /home/coder/.claude
        touch "$FIRST_RUN_MARKER"

        # Auto-launch Claude after successful first-run setup
        if [ "$AI_OK" = "1" ] && [ "$AUTH_OK" = "1" ] && [ "${CLAUDE_AUTO_LAUNCH:-1}" = "1" ]; then
            clear
            claude
        else
            echo -e "  ${GREEN}You're all set!${NC} Type ${GREEN}claude${NC} to start."
            echo ""
        fi
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
        [ "$SH_FAILURE" = "github_token_expired" ] && GH_OK=0
    fi

    # Make sure correct subscription is set (verify access first)
    if [ "$AZ_OK" = "1" ] && [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
        SUB_ID=$(read_yaml "providers.azure-foundry.subscription_id")
        if [ -n "$SUB_ID" ]; then
            CURRENT_SUB=$(az account show --query id -o tsv 2>/dev/null)
            if [ "$CURRENT_SUB" != "$SUB_ID" ]; then
                if az account list --query "[?id=='$SUB_ID'].id" -o tsv 2>/dev/null | grep -q "$SUB_ID"; then
                    az account set --subscription "$SUB_ID" 2>/dev/null
                else
                    SUB_NAME=$(read_yaml "providers.azure-foundry.subscription_name")
                    echo -e "  ${YELLOW}!${NC} No access to Azure subscription: ${SUB_NAME:-$SUB_ID}"
                    echo -e "    ${DIM}Ask your manager to request access, then run: login${NC}"
                fi
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
        # Re-check after wizard (wizard now handles GitHub too)
        if [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
            az account show &>/dev/null 2>&1 && AUTH_OK=1 && NEEDS_REAUTH=0
        elif [ "${CLAUDE_CODE_USE_BEDROCK}" = "1" ]; then
            aws sts get-caller-identity --profile "${AWS_PROFILE:-sso-bedrock}" &>/dev/null 2>&1 && AUTH_OK=1 && NEEDS_REAUTH=0
        fi
        AZ_OK=$AUTH_OK
        gh auth status &>/dev/null 2>&1 && GH_OK=1
    fi

    # --- GitHub auth recovery (independent of AI provider) ---
    if [ "$GH_OK" = "0" ]; then
        "$SCRIPTS_DIR/login-wizard.sh" --github-only
        gh auth status &>/dev/null 2>&1 && GH_OK=1
    fi

    # --- Now show the status (post-recovery if wizard ran) ---
    echo ""
    echo -e "${BLUE}  Claude Code${NC}"
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
        echo -e "  ${CHECK_PASS} System"
    else
        echo -e "  ${CHECK_FAIL} System"
    fi

    if [ "$GH_OK" = "1" ]; then
        GH_USER=$(gh api user -q .login 2>/dev/null || echo "authenticated")
        echo -e "  ${CHECK_PASS} GitHub        ${GREEN}${GH_USER}${NC}"
    else
        echo -e "  ${CHECK_FAIL} GitHub        ${RED}Not signed in${NC}"
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

    if [ "$AI_OK" = "1" ] && [ "$AUTH_OK" = "1" ] && [ "${CLAUDE_AUTO_LAUNCH:-1}" = "1" ]; then
        clear
        claude
    elif [ "$AI_OK" = "1" ] && [ "$AUTH_OK" = "1" ]; then
        echo -e "  ${GREEN}Ready.${NC} Type ${GREEN}claude${NC} to start."
    elif [ "$NEEDS_REAUTH" = "1" ]; then
        echo -e "  Some items still need attention. Type ${GREEN}login${NC} to try again."
    fi
    echo ""
fi
