#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Health Check (Docker HEALTHCHECK)
# Reads shared state from health-monitor. Falls back to basic curl if state
# file doesn't exist yet (startup grace period).
# =============================================================================

SH_STATE_FILE="/tmp/.health-state.json"

if [ -f "$SH_STATE_FILE" ]; then
    # Read status from the health monitor's shared state
    STATUS=$(python3 -c "import json; print(json.load(open('$SH_STATE_FILE')).get('status','unknown'))" 2>/dev/null || echo "unknown")

    case "$STATUS" in
        healthy|degraded)
            exit 0
            ;;
        unhealthy)
            exit 1
            ;;
        *)
            # Unknown state -- fall through to basic checks
            ;;
    esac
fi

# Fallback: health monitor hasn't written state yet (container just started)
curl -f -s http://127.0.0.1:7681/ > /dev/null 2>&1 || exit 1
curl -f -s http://127.0.0.1:8080/healthz > /dev/null 2>&1 || exit 1

exit 0
