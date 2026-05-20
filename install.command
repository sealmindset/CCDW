#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - macOS / Linux Installer
# Usage:
#   ./install.command --ai=foundry     Azure AI Foundry (default)
#   ./install.command --ai=bedrock     AWS Bedrock
#   ./install.command --ai=anthropic   Anthropic API key
#   ./install.command                  Interactive prompt or auto-detect
# Double-click this file in Finder to install with interactive provider selection.
# =============================================================================

cd "$(dirname "$0")" || exit 1

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Log file — append to existing (from setup-claude-mac) or create new
# ---------------------------------------------------------------------------
LOG_FILE="${CLAUDE_SETUP_LOG:-$HOME/Desktop/claude-setup.log}"
if [ -z "${CLAUDE_SETUP_LOG:-}" ]; then
    echo "=== Claude Code Install — $(date) ===" >> "$LOG_FILE"
    exec > >(tee -a "$LOG_FILE") 2>&1
fi

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
AI_PROVIDER=""
RUN_DOCTOR=0
for arg in "$@"; do
    case "$arg" in
        --ai=*) AI_PROVIDER="${arg#--ai=}" ;;
        --doctor) RUN_DOCTOR=1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Doctor mode: diagnostics without reinstalling
# ---------------------------------------------------------------------------
if [ "$RUN_DOCTOR" = "1" ]; then
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Claude Code — Doctor${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    # Docker
    if command -v docker &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Docker CLI found: $(which docker)"
        if docker info &>/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} Docker daemon running"
            DOCKER_VER=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
            echo -e "  ${BLUE}i${NC} Docker version: ${DOCKER_VER:-unknown}"
        else
            echo -e "  ${RED}✗${NC} Docker daemon not responding"
        fi
    else
        echo -e "  ${RED}✗${NC} Docker CLI not found"
    fi

    # Image
    if docker image inspect ghcr.io/sealmindset/claude-code-docker:latest &>/dev/null 2>&1; then
        IMG_CREATED=$(docker image inspect ghcr.io/sealmindset/claude-code-docker:latest --format '{{.Created}}' 2>/dev/null | cut -dT -f1)
        IMG_SIZE=$(docker image inspect ghcr.io/sealmindset/claude-code-docker:latest --format '{{.Size}}' 2>/dev/null)
        IMG_SIZE_MB=$(( ${IMG_SIZE:-0} / 1048576 ))
        echo -e "  ${GREEN}✓${NC} Image present (${IMG_SIZE_MB}MB, built ${IMG_CREATED:-unknown})"
    else
        echo -e "  ${RED}✗${NC} Image not found — run install.command to download"
    fi

    # Container
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^claude-code$'; then
        UPTIME=$(docker ps --format '{{.Status}}' --filter name=claude-code 2>/dev/null)
        echo -e "  ${GREEN}✓${NC} Container running ($UPTIME)"
        HEALTH=$(docker inspect --format '{{.State.Health.Status}}' claude-code 2>/dev/null)
        if [ -n "$HEALTH" ]; then
            if [ "$HEALTH" = "healthy" ]; then
                echo -e "  ${GREEN}✓${NC} Health: $HEALTH"
            else
                echo -e "  ${YELLOW}!${NC} Health: $HEALTH"
            fi
        fi
    elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^claude-code$'; then
        echo -e "  ${RED}✗${NC} Container exists but not running"
        echo -e "  ${DIM}  Last 10 log lines:${NC}"
        docker logs claude-code 2>&1 | tail -10 | sed 's/^/    /'
    else
        echo -e "  ${YELLOW}!${NC} No container found"
    fi

    # Ports
    echo ""
    for port in 3000 7681 7682 8080 3002 9200; do
        if curl -s -o /dev/null --connect-timeout 2 "http://localhost:$port" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Port $port responding"
        elif lsof -iTCP:"$port" -sTCP:LISTEN -P -n 2>/dev/null | grep -q LISTEN; then
            occupant=$(lsof -iTCP:"$port" -sTCP:LISTEN -P -n 2>/dev/null | awk 'NR==2{print $1}')
            echo -e "  ${YELLOW}!${NC} Port $port bound (by: $occupant) but not responding to HTTP"
        else
            echo -e "  ${DIM}  Port $port: not in use${NC}"
        fi
    done

    # Network
    echo ""
    if curl -s --connect-timeout 5 -o /dev/null https://github.com 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Internet connectivity"
    else
        echo -e "  ${RED}✗${NC} No internet"
    fi
    if curl -so /dev/null -w '%{http_code}' --connect-timeout 10 https://snapistg-scus.azure.sleepnumber.com 2>/dev/null | grep -qv '^000$'; then
        echo -e "  ${GREEN}✓${NC} Sleep Number network reachable"
    else
        echo -e "  ${RED}✗${NC} Sleep Number network not reachable (VPN?)"
    fi

    # Disk
    AVAIL_GB=$(df -g "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "$AVAIL_GB" ]; then
        if [ "$AVAIL_GB" -lt 4 ] 2>/dev/null; then
            echo -e "  ${RED}✗${NC} Disk space: ${AVAIL_GB}GB (low!)"
        else
            echo -e "  ${GREEN}✓${NC} Disk space: ${AVAIL_GB}GB available"
        fi
    fi

    # .env
    ENV_FILE="$(pwd)/.env"
    if [ -f "$ENV_FILE" ]; then
        PROVIDER="unknown"
        grep -q "^CLAUDE_CODE_USE_FOUNDRY=1" "$ENV_FILE" 2>/dev/null && PROVIDER="Azure AI Foundry"
        grep -q "^CLAUDE_CODE_USE_BEDROCK=1" "$ENV_FILE" 2>/dev/null && PROVIDER="AWS Bedrock"
        grep -q "^ANTHROPIC_API_KEY=sk-" "$ENV_FILE" 2>/dev/null && PROVIDER="Anthropic API"
        echo -e "  ${GREEN}✓${NC} .env configured (provider: $PROVIDER)"
    else
        echo -e "  ${RED}✗${NC} No .env file"
    fi

    echo ""
    echo -e "  ${DIM}Log file: $LOG_FILE${NC}"
    echo ""
    exit 0
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Claude Code — Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "  This will set up your AI development environment."
echo -e "  It takes about 2-3 minutes on a good connection."
echo ""

# Normalize provider name
case "$AI_PROVIDER" in
    foundry|azure-foundry|azure|"Foundry Claude") AI_PROVIDER="foundry" ;;
    bedrock|aws-bedrock|aws|"AWS Bedrock")        AI_PROVIDER="bedrock" ;;
    anthropic|api-key|apikey|"Anthropic API Key")  AI_PROVIDER="anthropic" ;;
    "") ;; # no argument -- will prompt or auto-detect
    *)
        echo -e "${RED}[ERROR]${NC} Unknown provider: $AI_PROVIDER"
        echo ""
        echo "  Valid options:"
        echo "    --ai=foundry     Azure AI Foundry"
        echo "    --ai=bedrock     AWS Bedrock"
        echo "    --ai=anthropic   Anthropic API key"
        echo ""
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Helper: read a value from a provider config JSON
# ---------------------------------------------------------------------------
read_config() {
    local file="$1" key="$2"
    python3 -c "
import json, sys
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
" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Helper: write env vars from config JSON to .env
# ---------------------------------------------------------------------------
write_env_from_config() {
    local config_file="$1"
    local env_file="$2"

    python3 -c "
import json, os, sys

with open('$config_file') as f:
    cfg = json.load(f)

def resolve(val, cfg):
    if not isinstance(val, str):
        return str(val)
    import re
    def replacer(m):
        keys = m.group(1).split('.')
        v = cfg
        for k in keys:
            if isinstance(v, dict) and k in v:
                v = v[k]
            else:
                return ''
        return str(v) if v is not None else ''
    return re.sub(r'\{([^}]+)\}', replacer, val)

# Read existing .env
env_path = '$env_file'
lines = []
existing_keys = set()
if os.path.exists(env_path):
    with open(env_path) as f:
        lines = f.read().splitlines()
    for line in lines:
        stripped = line.strip()
        if stripped and not stripped.startswith('#'):
            eq = stripped.find('=')
            if eq > 0:
                existing_keys.add(stripped[:eq].strip())

# Comment out old provider keys
comment_keys = [
    'ANTHROPIC_API_KEY', 'CLAUDE_CODE_USE_FOUNDRY', 'ANTHROPIC_FOUNDRY_BASE_URL',
    'ANTHROPIC_FOUNDRY_API_KEY', 'CLAUDE_CODE_USE_BEDROCK', 'AWS_PROFILE', 'AWS_REGION',
    'ANTHROPIC_DEFAULT_SONNET_MODEL', 'ANTHROPIC_DEFAULT_HAIKU_MODEL', 'ANTHROPIC_DEFAULT_OPUS_MODEL',
]
for i, line in enumerate(lines):
    stripped = line.strip()
    if stripped and not stripped.startswith('#'):
        eq = stripped.find('=')
        if eq > 0:
            key = stripped[:eq].strip()
            if key in comment_keys:
                lines[i] = '# ' + line

# Write env_vars
env_vars = cfg.get('env_vars', {})
env_vars_opt = cfg.get('env_vars_optional', {})

new_lines = []
for key, tmpl in {**env_vars, **env_vars_opt}.items():
    val = resolve(tmpl, cfg)
    if not val and key in env_vars_opt:
        continue
    found = False
    for i, line in enumerate(lines):
        raw = line.lstrip('# ').strip()
        eq = raw.find('=')
        if eq > 0 and raw[:eq].strip() == key:
            lines[i] = key + '=' + val
            found = True
            break
    if not found:
        new_lines.append(key + '=' + val)

with open(env_path, 'w') as f:
    f.write('\n'.join(lines + new_lines) + '\n')
" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Helper: write AWS config from bedrock.json
# ---------------------------------------------------------------------------
write_aws_config() {
    local config_file="$1"
    python3 -c "
import json, os

with open('$config_file') as f:
    cfg = json.load(f)

aws_dir = os.path.expanduser('~/.aws')
os.makedirs(aws_dir, exist_ok=True)
config_path = os.path.join(aws_dir, 'config')

profile = cfg.get('profile_name', 'sso-bedrock')
session = cfg.get('aws_config', {}).get('sso_session', 'aws-sso')
sso_url = cfg.get('sso_start_url', '')
sso_region = cfg.get('sso_region', 'us-east-1')
account_id = cfg.get('account_id', '')
role_name = cfg.get('role_name', '')
region = cfg.get('region', 'us-east-1')

if not sso_url or not account_id or not role_name:
    print('SKIP')
    exit(0)

# Parse existing config, remove old session/profile
existing = ''
try:
    with open(config_path) as f:
        existing = f.read()
except FileNotFoundError:
    pass

sections = []
current = None
for line in existing.split('\n'):
    import re
    m = re.match(r'^\[(sso-session\s+|profile\s+)?(.+?)\]\s*$', line)
    if m:
        if current:
            sections.append(current)
        current = {'header': line, 'lines': [], 'name': m.group(2)}
    elif current:
        current['lines'].append(line)
if current:
    sections.append(current)

kept = [s for s in sections if s['name'] not in (session, profile)]
parts = [s['header'] + '\n' + '\n'.join(s['lines']) for s in kept]
parts = [p for p in parts if p.strip()]

parts.append(f'[sso-session {session}]\nsso_start_url = {sso_url}\nsso_region = {sso_region}\nsso_registration_scopes = sso:account:access')
parts.append(f'[profile {profile}]\nsso_session = {session}\nsso_account_id = {account_id}\nsso_role_name = {role_name}\nregion = {region}\noutput = json')

with open(config_path, 'w') as f:
    f.write('\n\n'.join(parts) + '\n')
print('OK')
" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Preflight checks: run provider-specific prereqs from config JSON
# ---------------------------------------------------------------------------
run_preflight() {
    local config_file="$1"
    local all_pass=1

    echo ""
    echo -e "${BOLD}  Checking Your Setup${NC}"
    echo ""

    # Run preflight checks once, capturing output and exit code
    local tmpfile
    tmpfile=$(mktemp)
    python3 -c "
import json, subprocess, sys

with open('$config_file') as f:
    cfg = json.load(f)

prereqs = cfg.get('prereqs', {}).get('host', [])
if not prereqs:
    sys.exit(0)

def resolve(val, cfg):
    import re
    def replacer(m):
        keys = m.group(1).split('.')
        v = cfg
        for k in keys:
            if isinstance(v, dict) and k in v:
                v = v[k]
            else:
                return ''
        return str(v) if v is not None else ''
    return re.sub(r'\{([^}]+)\}', replacer, str(val))

fail_count = 0
for p in prereqs:
    check = p.get('check', '')
    label = p.get('label', '')
    required = p.get('required', False)
    fail_msg = resolve(p.get('fail_message', ''), cfg)

    if check == 'manual':
        # Informational only -- user must verify
        print(f'INFO|{label}|{fail_msg}')
        continue
    elif check == 'info':
        print(f'NOTE|{label}|{fail_msg}')
        continue

    resolved_check = resolve(check, cfg)
    expect = p.get('expect', '')

    try:
        result = subprocess.run(resolved_check, shell=True, capture_output=True, text=True, timeout=15)
        if result.returncode == 0:
            if expect and expect not in result.stdout:
                print(f'FAIL|{label}|{fail_msg}')
                if required:
                    fail_count += 1
            else:
                print(f'PASS|{label}|')
        else:
            print(f'FAIL|{label}|{fail_msg}')
            if required:
                fail_count += 1
    except Exception as e:
        print(f'FAIL|{label}|{fail_msg}')
        if required:
            fail_count += 1

sys.exit(fail_count)
" > "$tmpfile" 2>/dev/null
    local preflight_result=$?

    # Display the saved output with colored formatting
    while IFS='|' read -r status label msg; do
        case "$status" in
            PASS)
                echo -e "  ${GREEN}✓${NC} $label"
                ;;
            FAIL)
                echo -e "  ${RED}✗${NC} $label"
                if [ -n "$msg" ]; then
                    echo -e "    ${YELLOW}$msg${NC}"
                fi
                all_pass=0
                ;;
            INFO)
                echo -e "  ${YELLOW}?${NC} $label ${DIM}(verify manually)${NC}"
                if [ -n "$msg" ]; then
                    echo -e "    ${YELLOW}$msg${NC}"
                fi
                ;;
            NOTE)
                echo -e "  ${BLUE}i${NC} $label"
                if [ -n "$msg" ]; then
                    echo -e "    ${DIM}$msg${NC}"
                fi
                ;;
        esac
    done < "$tmpfile"
    rm -f "$tmpfile"

    echo ""
    if [ $preflight_result -ne 0 ]; then
        echo -e "  ${RED}Some required checks failed.${NC} Fix the items above before continuing."
        echo ""
        read -p "  Press Enter to retry, or Ctrl+C to exit... " _
        run_preflight "$config_file"
        return $?
    fi

    echo -e "  ${GREEN}All checks passed.${NC}"
    echo ""
    return 0
}

# ---------------------------------------------------------------------------
# Check for Docker
# ---------------------------------------------------------------------------
docker_ready() {
    docker info &>/dev/null 2>&1 &
    local pid=$!
    ( sleep 10 && kill "$pid" 2>/dev/null ) &
    local watchdog=$!
    wait "$pid" 2>/dev/null
    local rc=$?
    kill "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null
    return $rc
}

# Spinner with elapsed time — replaces blind dot-printing for background ops
spin_wait() {
    local pid=$1 label=$2
    local start=$(date +%s)
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    while kill -0 "$pid" 2>/dev/null; do
        local elapsed=$(( $(date +%s) - start ))
        local i=$(( elapsed % ${#frames[@]} ))
        printf "\r  ${frames[$i]} %s %dm %02ds" "$label" $((elapsed/60)) $((elapsed%60))
        sleep 1
    done
    printf "\r%-70s\r" ""
}

if ! command -v docker &> /dev/null; then
    echo -e "${RED}[!]${NC} Docker needs to be installed first."
    echo ""
    echo "  Download and install one of these (both are free):"
    echo "    - Docker Desktop:   https://www.docker.com/products/docker-desktop/"
    echo "    - Rancher Desktop:  https://rancherdesktop.io/"
    echo ""
    echo "  Once installed, double-click this file again."
    echo ""
    read -p "Press Enter to close..."
    exit 1
fi

if ! docker_ready; then
    echo -e "${YELLOW}[...]${NC} Waiting for Docker to start..."
    for i in $(seq 1 15); do
        docker_ready && break
        printf "."
        sleep 2
    done
    echo ""
fi

if ! docker_ready; then
    echo -e "${RED}[!]${NC} Docker is installed but not running yet."
    echo ""
    echo "  Open Docker Desktop (or Rancher Desktop) from your Applications folder,"
    echo "  wait for it to finish loading, then double-click this file again."
    echo ""
    read -p "Press Enter to close..."
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Docker is running."

# ---------------------------------------------------------------------------
# Create required folders
# ---------------------------------------------------------------------------
PROJECTS_DIR="$HOME/Documents"
AZURE_DIR="$HOME/.azure"
AWS_DIR="$HOME/.aws"
KUBE_DIR="$HOME/.kube"
HOST_GITCONFIG="$HOME/.gitconfig"

[ ! -d "$PROJECTS_DIR" ] && mkdir -p "$PROJECTS_DIR"
echo -e "${GREEN}[OK]${NC} Projects folder: $PROJECTS_DIR"

mkdir -p "$AZURE_DIR"
mkdir -p "$AWS_DIR"
mkdir -p "$KUBE_DIR"

# Build host-access args: host networking, kube config, and git identity
HOST_ACCESS_ARGS=(--add-host host.docker.internal:host-gateway -v "$KUBE_DIR:/home/coder/.kube")
if [ -f "$HOST_GITCONFIG" ]; then
    HOST_ACCESS_ARGS+=(-v "$HOST_GITCONFIG:/home/coder/.host-gitconfig:ro")
fi

# ---------------------------------------------------------------------------
# Create .env from template if it doesn't exist
# ---------------------------------------------------------------------------
ENV_FILE="$(pwd)/.env"
if [ ! -f "$ENV_FILE" ] && [ -f ".env.example" ]; then
    echo -e "${YELLOW}[...]${NC} Creating .env from template..."
    cp .env.example "$ENV_FILE"
    echo -e "${GREEN}[OK]${NC} Created .env"
fi

# ---------------------------------------------------------------------------
# AI Provider Setup
# ---------------------------------------------------------------------------

# Check if a provider is already configured
HAS_PROVIDER=0
if [ -f "$ENV_FILE" ]; then
    grep -q "^ANTHROPIC_API_KEY=" "$ENV_FILE" 2>/dev/null && HAS_PROVIDER=1
    grep -q "^ANTHROPIC_FOUNDRY_BASE_URL=" "$ENV_FILE" 2>/dev/null && HAS_PROVIDER=1
    grep -q "^CLAUDE_CODE_USE_BEDROCK=1" "$ENV_FILE" 2>/dev/null && HAS_PROVIDER=1
fi

if [ "$HAS_PROVIDER" = "1" ] && [ -z "$AI_PROVIDER" ]; then
    echo -e "${GREEN}[OK]${NC} AI provider already configured in .env"
else
    # If no --ai= argument, prompt interactively
    if [ -z "$AI_PROVIDER" ]; then
        echo ""
        echo -e "${BOLD}  Choose your AI provider:${NC}"
        echo ""
        echo "    1. Azure AI Foundry  (Claude via Azure)"
        echo "    2. AWS Bedrock       (Claude via AWS)"
        echo "    3. Anthropic API     (direct API key)"
        echo "    4. Skip for now      (edit .env manually later)"
        echo ""
        read -p "  Enter choice [1-4]: " PROVIDER_CHOICE
        case "$PROVIDER_CHOICE" in
            1) AI_PROVIDER="foundry" ;;
            2) AI_PROVIDER="bedrock" ;;
            3) AI_PROVIDER="anthropic" ;;
            *) AI_PROVIDER="" ;;
        esac
    fi

    if [ -n "$AI_PROVIDER" ]; then
        CONFIG_FILE="config/${AI_PROVIDER}.json"
        if [ ! -f "$CONFIG_FILE" ]; then
            echo -e "${RED}[ERROR]${NC} Config file not found: $CONFIG_FILE"
            exit 1
        fi

        DISPLAY_NAME=$(read_config "$CONFIG_FILE" "display_name")
        echo ""
        echo -e "${YELLOW}[...]${NC} Configuring ${DISPLAY_NAME}..."

        # Run provider-specific preflight checks
        run_preflight "$CONFIG_FILE" || exit 1

        # Provider-specific prompts for missing values
        case "$AI_PROVIDER" in
            foundry)
                ENDPOINT=$(read_config "$CONFIG_FILE" "endpoint")
                if [ -z "$ENDPOINT" ]; then
                    read -p "  Foundry endpoint URL: " ENDPOINT
                    if [ -n "$ENDPOINT" ]; then
                        python3 -c "
import json
with open('$CONFIG_FILE') as f: cfg = json.load(f)
cfg['endpoint'] = '$ENDPOINT'
with open('$CONFIG_FILE', 'w') as f: json.dump(cfg, f, indent=2)
" 2>/dev/null
                    fi
                fi

                AUTH_MODE=$(read_config "$CONFIG_FILE" "auth_mode")
                if [ "$AUTH_MODE" = "apikey" ]; then
                    API_KEY=$(read_config "$CONFIG_FILE" "api_key")
                    if [ -z "$API_KEY" ]; then
                        read -sp "  API key: " API_KEY
                        echo ""
                        if [ -n "$API_KEY" ]; then
                            python3 -c "
import json
with open('$CONFIG_FILE') as f: cfg = json.load(f)
cfg['api_key'] = '$API_KEY'
with open('$CONFIG_FILE', 'w') as f: json.dump(cfg, f, indent=2)
" 2>/dev/null
                        fi
                    fi
                else
                    echo -e "  ${BLUE}Note:${NC} Azure SSO sign-in will happen after the container starts."
                fi
                ;;

            bedrock)
                SSO_URL=$(read_config "$CONFIG_FILE" "sso_start_url")
                if [ -z "$SSO_URL" ]; then
                    read -p "  AWS SSO Start URL (https://d-xxx.awsapps.com/start): " SSO_URL
                    read -p "  AWS Account ID: " ACCT_ID
                    read -p "  SSO Role Name: " ROLE_NAME
                    read -p "  Bedrock Region [us-east-1]: " BDR_REGION
                    BDR_REGION="${BDR_REGION:-us-east-1}"

                    python3 -c "
import json
with open('$CONFIG_FILE') as f: cfg = json.load(f)
cfg['sso_start_url'] = '$SSO_URL'
cfg['account_id'] = '$ACCT_ID'
cfg['role_name'] = '$ROLE_NAME'
cfg['region'] = '$BDR_REGION'
cfg['sso_region'] = '$BDR_REGION'
with open('$CONFIG_FILE', 'w') as f: json.dump(cfg, f, indent=2)
" 2>/dev/null
                fi

                AWS_RESULT=$(write_aws_config "$CONFIG_FILE")
                if [ "$AWS_RESULT" = "OK" ]; then
                    echo -e "  ${GREEN}[OK]${NC} AWS config written to ~/.aws/config"
                fi
                echo -e "  ${BLUE}Note:${NC} AWS SSO sign-in will happen after the container starts."
                ;;

            anthropic)
                API_KEY=$(read_config "$CONFIG_FILE" "api_key")
                if [ -z "$API_KEY" ]; then
                    read -sp "  Anthropic API key (sk-ant-...): " API_KEY
                    echo ""
                    if [ -n "$API_KEY" ]; then
                        python3 -c "
import json
with open('$CONFIG_FILE') as f: cfg = json.load(f)
cfg['api_key'] = '$API_KEY'
with open('$CONFIG_FILE', 'w') as f: json.dump(cfg, f, indent=2)
" 2>/dev/null
                    fi
                fi
                ;;
        esac

        # Write .env from the config JSON
        write_env_from_config "$CONFIG_FILE" "$ENV_FILE"
        echo -e "${GREEN}[OK]${NC} ${DISPLAY_NAME} configured in .env"
    else
        echo -e "${YELLOW}[...]${NC} Skipping provider setup -- edit .env later."
    fi
fi

# ---------------------------------------------------------------------------
# Azure CLI host pre-auth: if host is already signed in, container inherits tokens
# ---------------------------------------------------------------------------
if [ "${AI_PROVIDER:-}" = "foundry" ] && command -v az &>/dev/null; then
    if az account show &>/dev/null 2>&1; then
        AZ_USER=$(az account show --query user.name -o tsv 2>/dev/null)
        AZ_SUB=$(az account show --query name -o tsv 2>/dev/null)
        echo -e "${GREEN}[OK]${NC} Azure CLI signed in as ${AZ_USER:-unknown} (${AZ_SUB:-unknown})"
        echo -e "  ${DIM}Container will inherit your Azure session — no device-code login needed.${NC}"
    fi
fi

# ---------------------------------------------------------------------------
# Auto-extract SSL inspection proxy certificates (Zscaler, Netskope, etc.)
# Searches macOS Keychain and exports any proxy CA certs to certs/
# so Docker builds trust corporate HTTPS inspection.
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[...]${NC} Checking network security settings..."

CERTS_DIR="$(pwd)/certs"
mkdir -p "$CERTS_DIR"

PROXY_CERT_COUNT=0
for pattern in Zscaler Netskope "Palo Alto" GlobalProtect "Blue Coat" Forcepoint "Symantec Web" ContentKeeper; do
    while IFS= read -r cert_name; do
        [ -z "$cert_name" ] && continue
        safe_name=$(echo "$cert_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g' | sed 's/--*/-/g; s/^-//; s/-$//')
        out_path="${CERTS_DIR}/${safe_name}.crt"
        if [ ! -f "$out_path" ]; then
            security find-certificate -c "$cert_name" -p /Library/Keychains/System.keychain > "$out_path" 2>/dev/null \
                || security find-certificate -c "$cert_name" -p ~/Library/Keychains/login.keychain-db > "$out_path" 2>/dev/null
            if [ -s "$out_path" ]; then
                : # cert exported silently
                PROXY_CERT_COUNT=$((PROXY_CERT_COUNT + 1))
            else
                rm -f "$out_path"
            fi
        fi
    done < <(security find-certificate -a -c "$pattern" -p /Library/Keychains/System.keychain 2>/dev/null \
        | grep -o "subject=.*CN = [^,]*" | sed 's/.*CN = //' | sort -u; \
        security find-certificate -a -c "$pattern" ~/Library/Keychains/login.keychain-db 2>/dev/null \
        | awk -F'"' '/0x00000011/{getline; print $2}' | sort -u)
done

if [ "$PROXY_CERT_COUNT" -eq 0 ]; then
    echo -e "${GREEN}[OK]${NC} Network security: no special configuration needed"
else
    echo -e "${GREEN}[OK]${NC} Network security: configured for your environment"
fi

# ---------------------------------------------------------------------------
# Fix host-side VSCode certificate errors (NODE_EXTRA_CA_CERTS)
# Same proxy CAs that break Docker also break VSCode extensions (Claude, etc.)
# Sets NODE_EXTRA_CA_CERTS so Node.js trusts the proxy's re-signed certs.
# ---------------------------------------------------------------------------
if [ "$PROXY_CERT_COUNT" -gt 0 ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    if [ -f "$SCRIPT_DIR/scripts/fix-vscode-certs.sh" ]; then
        bash "$SCRIPT_DIR/scripts/fix-vscode-certs.sh" 2>/dev/null || true
    fi
fi

# ---------------------------------------------------------------------------
# ACR pull-through cache (bypasses Zscaler / SSL inspection entirely)
# If REGISTRY_MIRROR is set in .env, authenticate and use it for base images.
# ---------------------------------------------------------------------------
REGISTRY_MIRROR=""
if [ -f "$ENV_FILE" ]; then
    REGISTRY_MIRROR=$(grep -E "^REGISTRY_MIRROR=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-)
fi

if [ -n "$REGISTRY_MIRROR" ]; then
    REGISTRY_MIRROR="${REGISTRY_MIRROR%/}/"
    ACR_HOST="${REGISTRY_MIRROR%%/*}"
    ACR_NAME="${ACR_HOST%.azurecr.io}"

    # Authenticate to ACR (needed for both base images and app image pull)
    ACR_SUBSCRIPTION=$(grep -E "^ACR_SUBSCRIPTION=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-)
    ACR_LOGGED_IN=0
    if command -v az &>/dev/null; then
        ACR_LOGIN_ARGS="--name $ACR_NAME"
        [ -n "$ACR_SUBSCRIPTION" ] && ACR_LOGIN_ARGS="$ACR_LOGIN_ARGS --subscription $ACR_SUBSCRIPTION"
        if az acr login $ACR_LOGIN_ARGS &>/dev/null; then
            echo -e "${GREEN}[OK]${NC} Image registry authenticated."
            ACR_LOGGED_IN=1
        else
            echo -e "${YELLOW}[WARN]${NC} Image registry not authenticated. Will try public registries."
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Pre-pull disk space check
# ---------------------------------------------------------------------------
AVAIL_GB=$(df -g "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "$AVAIL_GB" ] && [ "$AVAIL_GB" -lt 4 ] 2>/dev/null; then
    echo -e "${YELLOW}[WARN]${NC} Low disk space: ${AVAIL_GB}GB free (4GB+ recommended for image download)."
    echo "  If the download fails, free up space and try again."
    echo ""
fi

# ---------------------------------------------------------------------------
# Auto-update: pull latest image
# ---------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[...]${NC} Downloading latest version..."

PULL_LOG="/tmp/claude-code-install-pull.log"

# Try 0: Load from local .tar file (pre-baked image distribution)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/claude-code-docker.tar" ]; then
    printf "  Loading from local file"
    if docker load -i "$SCRIPT_DIR/claude-code-docker.tar" >"$PULL_LOG" 2>&1; then
        echo ""
        echo -e "${GREEN}[OK]${NC} Loaded from local file."
        IMAGE_LOADED=1
    else
        echo ""
    fi
fi

if [ "${IMAGE_LOADED:-0}" = "1" ]; then
    : # Already loaded from .tar
else
    PULL_OK=0

    # Try 1: ACR pull (bypasses Zscaler — works on corporate network)
    if [ -n "$REGISTRY_MIRROR" ]; then
        ACR_IMAGE="${REGISTRY_MIRROR}claude-code-docker:latest"
        docker pull "$ACR_IMAGE" >"$PULL_LOG" 2>&1 &
        PULL_PID=$!
        spin_wait "$PULL_PID" "Downloading from internal registry..."
        wait "$PULL_PID" 2>/dev/null
        PULL_EXIT=$?
        if [ $PULL_EXIT -eq 0 ]; then
            docker tag "$ACR_IMAGE" ghcr.io/sealmindset/claude-code-docker:latest 2>/dev/null
            echo -e "${GREEN}[OK]${NC} Download complete."
            PULL_OK=1
        else
            echo -e "${YELLOW}[...]${NC} Internal registry unavailable, trying public..."
        fi
    fi

    # Try 2: GHCR pull (direct, may be blocked by Zscaler)
    if [ "$PULL_OK" = "0" ]; then
        docker pull ghcr.io/sealmindset/claude-code-docker:latest >"$PULL_LOG" 2>&1 &
        PULL_PID=$!
        spin_wait "$PULL_PID" "Downloading..."
        wait "$PULL_PID" 2>/dev/null
        PULL_EXIT=$?
        if [ $PULL_EXIT -eq 0 ]; then
            echo -e "${GREEN}[OK]${NC} Download complete."
            PULL_OK=1
        fi
    fi

    # Try 3: Cached image
    if [ "$PULL_OK" = "0" ] && docker image inspect ghcr.io/sealmindset/claude-code-docker:latest &>/dev/null; then
        echo -e "${GREEN}[OK]${NC} Using previously downloaded version."
        PULL_OK=1
    fi

    # Try 4: Local build (last resort)
    if [ "$PULL_OK" = "0" ]; then
        BUILD_ARGS=""
        [ -n "$REGISTRY_MIRROR" ] && BUILD_ARGS="--build-arg REGISTRY_MIRROR=${REGISTRY_MIRROR}"
        docker build $BUILD_ARGS -t ghcr.io/sealmindset/claude-code-docker:latest . >"$PULL_LOG" 2>&1 &
        BUILD_PID=$!
        spin_wait "$BUILD_PID" "Building locally..."
        wait "$BUILD_PID" 2>/dev/null
        BUILD_EXIT=$?

        if [ $BUILD_EXIT -ne 0 ]; then
            echo -e "${RED}[!]${NC} Setup could not download the required files."
            echo ""
            echo "  Check your internet connection and try again."
            echo "  If the problem persists, contact your IT team."
            echo ""
            read -p "Press Enter to close..."
            exit 1
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Stop existing container if running
# ---------------------------------------------------------------------------
if docker ps --format '{{.Names}}' | grep -q '^claude-code$'; then
    echo -e "${YELLOW}[...]${NC} Stopping existing Claude Code session..."
fi
docker rm -f claude-code &>/dev/null || true

# ---------------------------------------------------------------------------
# Detect Docker socket GID
# ---------------------------------------------------------------------------
DOCKER_GID=$(stat -f '%g' /var/run/docker.sock 2>/dev/null || stat -c '%g' /var/run/docker.sock 2>/dev/null || echo "0")

# ---------------------------------------------------------------------------
# Extra drive mounts (from EXTRA_MOUNTS in .env or mount-drive.command)
# ---------------------------------------------------------------------------
EXTRA_VOL_ARGS=()
if [ -f "$ENV_FILE" ]; then
    EXTRA_MOUNTS_RAW=$(grep '^EXTRA_MOUNTS=' "$ENV_FILE" 2>/dev/null | head -1 | sed 's/^EXTRA_MOUNTS=//')
    if [ -n "$EXTRA_MOUNTS_RAW" ]; then
        IFS='|' read -ra EXTRA_PATHS <<< "$EXTRA_MOUNTS_RAW"
        for epath in "${EXTRA_PATHS[@]}"; do
            if [ -d "$epath" ]; then
                ename=$(basename "$epath")
                EXTRA_VOL_ARGS+=(-v "$epath:/home/coder/Drives/$ename")
                echo -e "${GREEN}[OK]${NC} Extra mount: $ename"
            fi
        done
    fi
fi

# ---------------------------------------------------------------------------
# Pre-flight: check for port conflicts
# ---------------------------------------------------------------------------
PORT_CONFLICT=0
for port_pair in "WELCOME_PORT:3000" "TTYD_PORT:7681" "TTYD_NEW_PORT:7682" "CODE_SERVER_PORT:8080" "CHAT_PORT:3002" "WORKSHOP_PORT:9200"; do
    var_name="${port_pair%%:*}"
    default="${port_pair##*:}"
    port="${!var_name:-$default}"
    if lsof -iTCP:"$port" -sTCP:LISTEN -P -n 2>/dev/null | grep -q LISTEN; then
        occupant=$(lsof -iTCP:"$port" -sTCP:LISTEN -P -n 2>/dev/null | awk 'NR==2{print $1}')
        echo -e "${YELLOW}[WARN]${NC} Port $port is already in use (by: $occupant)"
        PORT_CONFLICT=1
    fi
done

if [ "$PORT_CONFLICT" = "1" ]; then
    echo ""
    echo -e "  ${YELLOW}Some ports Claude Code needs are occupied.${NC}"
    echo "  This can happen if Claude Code is already running,"
    echo "  or another app uses the same ports."
    echo ""
    echo "  Options:"
    echo "    1. Close the app using those ports"
    echo "    2. If Claude Code is already running, visit http://localhost:3000"
    echo ""
    read -p "  Press Enter to try anyway, or Ctrl+C to exit... " _
fi

# ---------------------------------------------------------------------------
# Start the container
# ---------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[...]${NC} Starting Claude Code..."
if ! docker run -d \
    --name claude-code \
    --restart unless-stopped \
    --group-add "$DOCKER_GID" \
    --env-file "$ENV_FILE" \
    -p "${WELCOME_PORT:-3000}:3000" \
    -p "${TTYD_PORT:-7681}:7681" \
    -p "${TTYD_NEW_PORT:-7682}:7682" \
    -p "${CODE_SERVER_PORT:-8080}:8080" \
    -p "${CHAT_PORT:-3002}:3002" \
    -p "${WORKSHOP_PORT:-9200}:9200" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$PROJECTS_DIR:/home/coder/Documents" \
    -v "$HOME/Downloads:/home/coder/Downloads" \
    -v "$HOME/Desktop:/home/coder/Desktop" \
    -v "$AZURE_DIR:/home/coder/.azure" \
    -v "$AWS_DIR:/home/coder/.aws" \
    -v claude-code-data:/home/coder/.claude \
    -v claude-code-gh:/home/coder/.config/gh \
    -v claude-code-git-config:/home/coder/.gitconfig.d \
    -v claude-code-local:/home/coder/.local \
    -v claude-code-continue:/home/coder/.continue \
    -v claude-code-npm:/home/coder/.npm \
    -v claude-code-bash-history:/home/coder/.shell-persist \
    "${HOST_ACCESS_ARGS[@]}" \
    "${EXTRA_VOL_ARGS[@]}" \
    ghcr.io/sealmindset/claude-code-docker:latest >/tmp/claude-code-start.log 2>&1; then

    # Auto-recover from stale image (OCI "file exists" error)
    if grep -q "file exists" /tmp/claude-code-start.log 2>/dev/null; then
        echo -e "${YELLOW}[...]${NC} Downloaded image is outdated. Rebuilding locally (one-time fix)..."
        docker rm -f claude-code &>/dev/null || true
        docker rmi ghcr.io/sealmindset/claude-code-docker:latest &>/dev/null || true
        BUILD_ARGS=""
        [ -n "$REGISTRY_MIRROR" ] && BUILD_ARGS="--build-arg REGISTRY_MIRROR=${REGISTRY_MIRROR}"
        docker build $BUILD_ARGS -t ghcr.io/sealmindset/claude-code-docker:latest . >/tmp/claude-code-build.log 2>&1 &
        BUILD_PID=$!
        spin_wait "$BUILD_PID" "Rebuilding..."
        wait "$BUILD_PID" 2>/dev/null
        BUILD_EXIT=$?

        if [ $BUILD_EXIT -eq 0 ]; then
            echo -e "${GREEN}[OK]${NC} Rebuild complete."
            echo ""
            echo -e "${YELLOW}[...]${NC} Starting Claude Code..."
            if docker run -d \
                --name claude-code \
                --restart unless-stopped \
                --group-add "$DOCKER_GID" \
                --env-file "$ENV_FILE" \
                -p "${WELCOME_PORT:-3000}:3000" \
                -p "${TTYD_PORT:-7681}:7681" \
                -p "${TTYD_NEW_PORT:-7682}:7682" \
                -p "${CODE_SERVER_PORT:-8080}:8080" \
                -p "${CHAT_PORT:-3002}:3002" \
                -p "${WORKSHOP_PORT:-9200}:9200" \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v "$PROJECTS_DIR:/home/coder/Documents" \
                -v "$HOME/Downloads:/home/coder/Downloads" \
                -v "$HOME/Desktop:/home/coder/Desktop" \
                -v "$AZURE_DIR:/home/coder/.azure" \
                -v "$AWS_DIR:/home/coder/.aws" \
                -v claude-code-data:/home/coder/.claude \
                -v claude-code-gh:/home/coder/.config/gh \
                -v claude-code-git-config:/home/coder/.gitconfig.d \
                -v claude-code-local:/home/coder/.local \
                -v claude-code-continue:/home/coder/.continue \
                -v claude-code-npm:/home/coder/.npm \
                -v claude-code-bash-history:/home/coder/.shell-persist \
                "${HOST_ACCESS_ARGS[@]}" \
                "${EXTRA_VOL_ARGS[@]}" \
                ghcr.io/sealmindset/claude-code-docker:latest >/tmp/claude-code-start.log 2>&1; then
                echo -e "${GREEN}[OK]${NC} Claude Code is running!"
                CONTAINER_STARTED=1
            fi
        fi

        if [ "${CONTAINER_STARTED:-0}" != "1" ]; then
            echo -e "${RED}[!]${NC} Rebuild did not fix the problem."
            if [ -f /tmp/claude-code-start.log ] && [ -s /tmp/claude-code-start.log ]; then
                echo "  Error details:"
                sed 's/^/    /' /tmp/claude-code-start.log | tail -20
                echo ""
            fi
            echo "  Try: restart Docker, then double-click this file again."
            echo ""
            read -p "Press Enter to close..."
            exit 1
        fi
    else
        echo -e "${RED}[!]${NC} Could not start Claude Code."
        echo ""
        # Show the actual error so users (or IT) can diagnose
        if [ -f /tmp/claude-code-start.log ] && [ -s /tmp/claude-code-start.log ]; then
            echo "  Error details:"
            sed 's/^/    /' /tmp/claude-code-start.log | tail -20
            echo ""
        fi
        echo "  Common causes:"
        echo "    - A port is already in use (3000, 7681, 8080, or 9200)"
        echo "    - Docker ran out of disk space"
        echo "    - The Docker engine needs to be restarted"
        echo ""
        echo "  Try: restart Docker, then double-click this file again."
        echo ""
        read -p "Press Enter to close..."
        exit 1
    fi
fi

if [ "${CONTAINER_STARTED:-0}" != "1" ]; then
    echo -e "${GREEN}[OK]${NC} Claude Code is running!"
fi

# ---------------------------------------------------------------------------
# Container crash detection — catch immediate exit
# ---------------------------------------------------------------------------
sleep 3
if ! docker ps --format '{{.Names}}' | grep -q '^claude-code$'; then
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}  Container started but crashed${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "  Container logs (last 20 lines):"
    docker logs claude-code 2>&1 | tail -20 | sed 's/^/    /'
    echo ""
    echo "  Common causes:"
    echo "    - Missing or invalid .env configuration"
    echo "    - Port already in use by another app"
    echo "    - Docker ran out of memory"
    echo ""
    echo "  Log file saved to: $LOG_FILE"
    echo ""
    read -p "Press Enter to close..."
    exit 1
fi

# ---------------------------------------------------------------------------
# Wait for dashboard
# ---------------------------------------------------------------------------
echo ""
printf "${YELLOW}[...]${NC} Getting everything ready"

for i in $(seq 1 45); do
    if curl -s -o /dev/null http://localhost:3000 2>/dev/null && \
       curl -s -o /dev/null http://localhost:7681 2>/dev/null; then
        break
    fi
    printf "."
    sleep 2
done
echo ""

echo -e "${GREEN}[OK]${NC} Ready!"
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "  Opening Claude Code in your browser..."
echo -e "${BLUE}========================================${NC}"
echo ""

open "http://localhost:3000" 2>/dev/null || xdg-open "http://localhost:3000" 2>/dev/null &

# ---------------------------------------------------------------------------
# Desktop shortcut (macOS .webloc) with Claude icon
# ---------------------------------------------------------------------------
DESKTOP_SHORTCUT="$HOME/Desktop/Claude Code.webloc"
OLD_SHORTCUT="$HOME/Desktop/Claude.webloc"
[ -f "$OLD_SHORTCUT" ] && rm -f "$OLD_SHORTCUT"

if [ ! -f "$DESKTOP_SHORTCUT" ]; then
    cat > "$DESKTOP_SHORTCUT" << 'WEBLOC'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>URL</key>
    <string>http://localhost:3000</string>
</dict>
</plist>
WEBLOC
    echo -e "${GREEN}[OK]${NC} Desktop shortcut created"
fi

# Set Claude icon on the shortcut
ICON_FILE="$(cd "$(dirname "$0")" && pwd)/assets/claude-icon.png"
if [ -f "$ICON_FILE" ] && [ -f "$DESKTOP_SHORTCUT" ]; then
    osascript -e "
use framework \"AppKit\"
set img to current application's NSImage's alloc()'s initWithContentsOfFile:\"$ICON_FILE\"
current application's NSWorkspace's sharedWorkspace()'s setIcon:img forFile:\"$DESKTOP_SHORTCUT\" options:0
" 2>/dev/null && echo -e "${GREEN}[OK]${NC} Claude icon set" || true
fi

echo ""
echo -e "  ${GREEN}http://localhost:3000${NC}"
echo ""
echo -e "  A desktop shortcut has been created so you can come back anytime."
echo -e "  To stop Claude Code: double-click ${BOLD}stop-claude.command${NC} or close Docker."
echo -e "  To diagnose issues:  ${DIM}./install.command --doctor${NC}"
echo ""
echo -e "  ${DIM}Setup log: $LOG_FILE${NC}"
echo ""
read -p "Press Enter to close..."
