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
NC='\033[0m'

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Claude Code Docker - Installer${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# ---------------------------------------------------------------------------
# Parse --ai= argument
# ---------------------------------------------------------------------------
AI_PROVIDER=""
for arg in "$@"; do
    case "$arg" in
        --ai=*) AI_PROVIDER="${arg#--ai=}" ;;
    esac
done

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
    echo -e "${BOLD}  Preflight Checks${NC}"
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
if ! command -v docker &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Docker is not installed."
    echo ""
    echo "  Please install one of the following:"
    echo "    - Docker Desktop:   https://www.docker.com/products/docker-desktop/"
    echo "    - Rancher Desktop:  https://rancherdesktop.io/"
    echo ""
    echo "  After installing, run this script again."
    echo ""
    read -p "Press Enter to close..."
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Docker is installed but not running."
    echo ""
    echo "  Please start Docker Desktop or Rancher Desktop,"
    echo "  wait for it to finish loading, then run this script again."
    echo ""
    read -p "Press Enter to close..."
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Docker is running."

# ---------------------------------------------------------------------------
# Create required folders
# ---------------------------------------------------------------------------
PROJECTS_DIR="$HOME/Documents/GitHub"
AZURE_DIR="$HOME/.azure"
AWS_DIR="$HOME/.aws"

[ ! -d "$PROJECTS_DIR" ] && mkdir -p "$PROJECTS_DIR"
echo -e "${GREEN}[OK]${NC} Projects folder: $PROJECTS_DIR"

mkdir -p "$AZURE_DIR"
mkdir -p "$AWS_DIR"

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
# Auto-extract SSL inspection proxy certificates (Zscaler, Netskope, etc.)
# Searches macOS Keychain and exports any proxy CA certs to certs/
# so Docker builds trust corporate HTTPS inspection.
# ---------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[...]${NC} Checking for SSL inspection proxy certificates..."

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
                echo -e "  ${GREEN}[OK]${NC} Exported: $cert_name"
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
    echo -e "${GREEN}[OK]${NC} No SSL proxy certs found (not behind an inspection proxy)"
else
    echo -e "${GREEN}[OK]${NC} Exported ${PROXY_CERT_COUNT} proxy certificate(s) to certs/"
fi

# ---------------------------------------------------------------------------
# Fix host-side VSCode certificate errors (NODE_EXTRA_CA_CERTS)
# Same proxy CAs that break Docker also break VSCode extensions (Claude, etc.)
# Sets NODE_EXTRA_CA_CERTS so Node.js trusts the proxy's re-signed certs.
# ---------------------------------------------------------------------------
if [ "$PROXY_CERT_COUNT" -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}[...]${NC} Configuring VSCode to trust proxy certificates..."
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    if [ -f "$SCRIPT_DIR/scripts/fix-vscode-certs.sh" ]; then
        bash "$SCRIPT_DIR/scripts/fix-vscode-certs.sh" 2>/dev/null && \
            echo -e "${GREEN}[OK]${NC} VSCode certificate fix applied" || \
            echo -e "${YELLOW}[WARN]${NC} VSCode cert fix had issues (non-fatal)"
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

    # Silently authenticate to ACR using existing Azure session
    if command -v az &>/dev/null; then
        if az acr login --name "$ACR_NAME" &>/dev/null; then
            echo -e "${GREEN}[OK]${NC} Image registry authenticated."
        else
            echo -e "${YELLOW}[WARN]${NC} Image registry not authenticated. Will use public Docker Hub instead."
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Auto-update: pull latest image
# ---------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[...]${NC} Checking for updates and downloading latest version..."

# Try 0: Load from local .tar file (pre-baked image distribution)
# Place claude-code-docker.tar next to this script to skip all network pulls.
# Create with: docker save ghcr.io/sealmindset/claude-code-docker:latest -o claude-code-docker.tar
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/claude-code-docker.tar" ]; then
    echo -e "${YELLOW}[...]${NC} Found local image file -- loading..."
    if docker load -i "$SCRIPT_DIR/claude-code-docker.tar"; then
        echo -e "${GREEN}[OK]${NC} Image loaded from local file."
        IMAGE_LOADED=1
    else
        echo -e "${YELLOW}[...]${NC} Local file load failed -- trying network..."
    fi
fi

if [ "${IMAGE_LOADED:-0}" = "1" ]; then
    : # Already loaded from .tar
elif docker pull ghcr.io/sealmindset/claude-code-docker:latest; then
    echo -e "${GREEN}[OK]${NC} Image is up to date."
else
    if docker image inspect ghcr.io/sealmindset/claude-code-docker:latest &>/dev/null; then
        echo -e "${YELLOW}[WARN]${NC} Could not check for updates. Using cached image."
    else
        echo -e "${YELLOW}[...]${NC} No cached image. Building locally..."
        BUILD_ARGS=""
        [ -n "$REGISTRY_MIRROR" ] && BUILD_ARGS="--build-arg REGISTRY_MIRROR=${REGISTRY_MIRROR}"
        if ! docker build $BUILD_ARGS -t ghcr.io/sealmindset/claude-code-docker:latest .; then
            echo -e "${RED}[ERROR]${NC} Build failed."
            if [ -n "$REGISTRY_MIRROR" ]; then
                echo ""
                echo "  The build could not download its base components from the"
                echo "  image registry. This can happen if:"
                echo "    - Your Azure sign-in expired -- try: az login"
                echo "    - The registry doesn't have the right cache rules set up"
                echo "      (ask the AI CoE team to verify the Docker Hub cache rule)"
                echo "    - Your network is blocking the connection"
            else
                echo ""
                echo "  The build could not download its base components."
                echo "  Check your internet connection and try again."
            fi
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
# Start the container
# ---------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[...]${NC} Starting Claude Code Docker..."
if ! docker run -d \
    --name claude-code \
    --restart unless-stopped \
    --group-add "$DOCKER_GID" \
    --env-file "$ENV_FILE" \
    -p "${WELCOME_PORT:-3000}:3000" \
    -p "${TTYD_PORT:-7681}:7681" \
    -p "${TTYD_NEW_PORT:-7682}:7682" \
    -p "${CODE_SERVER_PORT:-8080}:8080" \
    -p "${WORKSHOP_PORT:-9200}:9200" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$PROJECTS_DIR:/home/coder/Documents/GitHub" \
    -v "$AZURE_DIR:/home/coder/.azure" \
    -v "$AWS_DIR:/home/coder/.aws" \
    -v claude-code-data:/home/coder/.claude \
    -v claude-code-gh:/home/coder/.config/gh \
    -v claude-code-git-config:/home/coder/.gitconfig.d \
    ghcr.io/sealmindset/claude-code-docker:latest; then
    echo -e "${RED}[ERROR]${NC} Failed to start the container."
    echo ""
    echo "  Common fixes:"
    echo "    - Make sure ports 3000, 7681, 8080, 9200 are not in use"
    echo "    - Restart Docker and try again"
    echo ""
    read -p "Press Enter to close..."
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Claude Code Docker is running!"

# ---------------------------------------------------------------------------
# Wait for dashboard
# ---------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[...]${NC} Waiting for dashboard to start..."

for i in $(seq 1 30); do
    if curl -s -o /dev/null http://localhost:3000 2>/dev/null; then
        break
    fi
    sleep 2
done

echo -e "${GREEN}[OK]${NC} Dashboard is ready!"
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "  Opening Claude Code in your browser..."
echo -e "${BLUE}========================================${NC}"
echo ""

open "http://localhost:3000" 2>/dev/null || xdg-open "http://localhost:3000" 2>/dev/null &

# ---------------------------------------------------------------------------
# Desktop shortcut (macOS .webloc)
# ---------------------------------------------------------------------------
DESKTOP_SHORTCUT="$HOME/Desktop/Claude Code.webloc"
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

echo ""
echo -e "  Dashboard:     ${GREEN}http://localhost:3000${NC}"
echo -e "  Workshop:      ${GREEN}http://localhost:9200${NC}"
echo -e "  Web Terminal:  ${GREEN}http://localhost:7681${NC}"
echo -e "  VS Code:       ${GREEN}http://localhost:8080${NC}"
echo ""
echo "  To stop:    docker rm -f claude-code"
echo "  To restart: double-click this file or the desktop shortcut"
echo ""
read -p "Press Enter to close this window..."
