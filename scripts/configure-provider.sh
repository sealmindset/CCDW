#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Provider Configuration
# Reads config/providers.yml and generates:
#   - ~/.claude/settings.json  (Claude Code auth + model config)
#   - ~/.claude/get-claude-token.sh  (token helper for Azure)
#
# Environment variables override YAML values if set.
# =============================================================================

set -e

CONFIG_FILE="/opt/claude-code-docker/config/providers.yml"
CLAUDE_DIR="/home/coder/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
TOKEN_SCRIPT="${CLAUDE_DIR}/get-claude-token.sh"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Personal API key: wipe any existing settings.json unconditionally.
# The volume persists stale Azure token config across rebuilds/restarts.
# ANTHROPIC_API_KEY doesn't need settings.json -- Claude Code reads it
# directly from the environment variable.
# ---------------------------------------------------------------------------
if [ -n "$ANTHROPIC_API_KEY" ]; then
    rm -f "$SETTINGS_FILE" "$TOKEN_SCRIPT"
    echo -e "${GREEN}[OK]${NC} Using personal API key (no settings.json needed)"
    exit 0
fi

# ---------------------------------------------------------------------------
# Foundry API key: remove stale token-based settings if switching auth mode
# ---------------------------------------------------------------------------
if [ -n "$ANTHROPIC_FOUNDRY_API_KEY" ] && [ -f "$SETTINGS_FILE" ]; then
    if grep -q "apiKeyHelper" "$SETTINGS_FILE" 2>/dev/null; then
        rm -f "$SETTINGS_FILE" "$TOKEN_SCRIPT"
    fi
fi

# ---------------------------------------------------------------------------
# Skip if settings.json already exists (preserves user edits)
# ---------------------------------------------------------------------------
if [ -f "$SETTINGS_FILE" ]; then
    echo -e "${GREEN}[OK]${NC} Claude Code settings already configured"
    exit 0
fi

# ---------------------------------------------------------------------------
# Read YAML config using Python (already installed for Azure CLI)
# ---------------------------------------------------------------------------
read_yaml() {
    python3 -c "
import yaml, sys
with open('$CONFIG_FILE') as f:
    cfg = yaml.safe_load(f)
# Navigate the dotted path
val = cfg
for key in '$1'.split('.'):
    if isinstance(val, dict) and key in val:
        val = val[key]
    else:
        sys.exit(0)
print(val if val is not None else '')
" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Determine which provider to configure
# Priority: personal API key > Azure Foundry > Bedrock > YAML default
# ANTHROPIC_API_KEY wins over Foundry so personal devices work without VPN.
# ---------------------------------------------------------------------------
if [ -n "$ANTHROPIC_API_KEY" ]; then
    PROVIDER="api-key"
elif [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
    PROVIDER="azure-foundry"
elif [ "${CLAUDE_CODE_USE_BEDROCK}" = "1" ]; then
    PROVIDER="bedrock"
else
    PROVIDER=$(read_yaml "default_provider")
fi

if [ -z "$PROVIDER" ]; then
    echo -e "${YELLOW}[...]${NC} No provider configured"
    exit 0
fi

PROVIDER_NAME=$(read_yaml "providers.${PROVIDER}.name")
mkdir -p "$CLAUDE_DIR"

# ---------------------------------------------------------------------------
# Read common Claude settings from YAML
# ---------------------------------------------------------------------------
SKIP_DANGEROUS=$(read_yaml "claude_settings.skipDangerousModePermissionPrompt")

# ---------------------------------------------------------------------------
# Generate provider-specific configuration
# ---------------------------------------------------------------------------
case "$PROVIDER" in
    azure-foundry)
        # Read from YAML, allow env var overrides
        ENDPOINT="${ANTHROPIC_FOUNDRY_BASE_URL:-$(read_yaml "providers.azure-foundry.endpoint")}"
        TOKEN_RESOURCE=$(read_yaml "providers.azure-foundry.token_resource")
        MODEL_SONNET="${ANTHROPIC_DEFAULT_SONNET_MODEL:-$(read_yaml "providers.azure-foundry.models.sonnet")}"
        MODEL_HAIKU="${ANTHROPIC_DEFAULT_HAIKU_MODEL:-$(read_yaml "providers.azure-foundry.models.haiku")}"
        MODEL_OPUS="${ANTHROPIC_DEFAULT_OPUS_MODEL:-$(read_yaml "providers.azure-foundry.models.opus")}"
        DEFAULT_MODEL=$(read_yaml "providers.azure-foundry.default_model")

        # Export env vars for the current session
        export ANTHROPIC_FOUNDRY_BASE_URL="$ENDPOINT"
        export ANTHROPIC_DEFAULT_SONNET_MODEL="$MODEL_SONNET"
        export ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL_HAIKU"
        export ANTHROPIC_DEFAULT_OPUS_MODEL="$MODEL_OPUS"

        if [ -n "$ANTHROPIC_FOUNDRY_API_KEY" ]; then
            # --- API key auth: no token helper needed ---
            python3 -c "
import json
settings = {
    'env': {
        'CLAUDE_CODE_USE_FOUNDRY': '1',
        'ANTHROPIC_FOUNDRY_BASE_URL': '${ENDPOINT}',
        'ANTHROPIC_FOUNDRY_API_KEY': '${ANTHROPIC_FOUNDRY_API_KEY}',
        'ANTHROPIC_DEFAULT_SONNET_MODEL': '${MODEL_SONNET}',
        'ANTHROPIC_DEFAULT_HAIKU_MODEL': '${MODEL_HAIKU}',
        'ANTHROPIC_DEFAULT_OPUS_MODEL': '${MODEL_OPUS}'
    }
}
if '${DEFAULT_MODEL}':
    settings['model'] = '${DEFAULT_MODEL}'
if '${SKIP_DANGEROUS}' == 'True':
    settings['skipDangerousModePermissionPrompt'] = True
print(json.dumps(settings, indent=2))
" > "$SETTINGS_FILE"

        else
            # --- Token-based auth: generate Azure CLI token helper ---
            cat > "$TOKEN_SCRIPT" <<TOKENEOF
#!/bin/bash
if ! az account get-access-token > /dev/null 2>&1; then
    az login --use-device-code > /dev/null 2>&1
fi
az account get-access-token --resource "${TOKEN_RESOURCE}" --query accessToken -o tsv
TOKENEOF
            chmod +x "$TOKEN_SCRIPT"

            python3 -c "
import json
settings = {
    'apiKeyHelper': '${TOKEN_SCRIPT}',
    'env': {
        'CLAUDE_CODE_USE_FOUNDRY': '1',
        'ANTHROPIC_FOUNDRY_BASE_URL': '${ENDPOINT}',
        'ANTHROPIC_DEFAULT_SONNET_MODEL': '${MODEL_SONNET}',
        'ANTHROPIC_DEFAULT_HAIKU_MODEL': '${MODEL_HAIKU}',
        'ANTHROPIC_DEFAULT_OPUS_MODEL': '${MODEL_OPUS}'
    }
}
if '${DEFAULT_MODEL}':
    settings['model'] = '${DEFAULT_MODEL}'
if '${SKIP_DANGEROUS}' == 'True':
    settings['skipDangerousModePermissionPrompt'] = True
print(json.dumps(settings, indent=2))
" > "$SETTINGS_FILE"
        fi
        ;;

    bedrock)
        REGION="${AWS_REGION:-$(read_yaml "providers.bedrock.region")}"

        export CLAUDE_CODE_USE_BEDROCK=1
        export AWS_REGION="$REGION"

        python3 -c "
import json
settings = {
    'env': {
        'CLAUDE_CODE_USE_BEDROCK': '1',
        'AWS_REGION': '${REGION}'
    }
}
if '${SKIP_DANGEROUS}' == 'True':
    settings['skipDangerousModePermissionPrompt'] = True
print(json.dumps(settings, indent=2))
" > "$SETTINGS_FILE"
        ;;

    api-key)
        # API key comes from env var — no settings.json needed for auth,
        # but write one for common settings
        if [ "${SKIP_DANGEROUS}" = "True" ]; then
            echo '{ "skipDangerousModePermissionPrompt": true }' > "$SETTINGS_FILE"
        fi
        ;;
esac

# Fix ownership
chown coder:coder "$SETTINGS_FILE" 2>/dev/null || true
[ -f "$TOKEN_SCRIPT" ] && chown coder:coder "$TOKEN_SCRIPT" 2>/dev/null || true

echo -e "${GREEN}[OK]${NC} Claude Code configured for ${PROVIDER_NAME}"
