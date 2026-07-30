#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Refresh discovered models
#
# Re-runs model discovery and regenerates ~/.claude/settings.json so the new
# model ids take effect. Run this after signing in to a provider (az login,
# aws sso login, claude login) -- at container start the credentials often
# aren't there yet, so discovery falls back to the baked config.
#
#   refresh-models.sh            discover + rewrite settings.json
#   refresh-models.sh --list     show what was discovered, change nothing
#   refresh-models.sh --yaml     print an updated providers.yml to stdout
#                                (redirect into config/providers.yml, commit it).
#                                Round-trips through PyYAML, so comments are
#                                dropped -- diff it before overwriting, or just
#                                copy the model ids across by hand.
# =============================================================================

set -e

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DISCOVER="$SCRIPTS_DIR/discover-models.py"
CACHE_FILE="${CCDW_MODELS_CACHE:-/home/coder/.claude/models-cache.json}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

case "${1:-}" in
    --yaml)
        exec python3 "$DISCOVER" --emit-yaml
        ;;
    --list)
        python3 "$DISCOVER" --print
        exit 0
        ;;
esac

echo -e "${YELLOW}[...]${NC} Discovering models from providers..."
python3 "$DISCOVER"

# Rebuild settings.json from the fresh cache. The force flag defeats the
# "already configured" early exit; plugin keys and the user's picked model are
# carried over by configure-provider.sh itself, so don't delete the file.
CCDW_FORCE_RECONFIGURE=1 "$SCRIPTS_DIR/configure-provider.sh"

if [ -f "$CACHE_FILE" ]; then
    python3 - "$CACHE_FILE" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for name, entry in data.get('providers', {}).items():
    src = entry.get('source', '?')
    note = '' if src != 'fallback' else ' (%s)' % entry.get('reason', 'unavailable')
    print('  %-14s %-14s %d models%s' % (name, src, len(entry.get('models', [])), note))
    for slot, mid in sorted((entry.get('slots') or {}).items()):
        print('      %-7s %s' % (slot, mid))
PY
fi

echo -e "${GREEN}[OK]${NC} Models refreshed. Restart Claude Code sessions to pick up the change."
