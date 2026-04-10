#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Service Watchdog
# Monitors ttyd and code-server, restarts them if they crash.
# Runs as a background process started from entrypoint.sh.
# =============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CHECK_INTERVAL=15    # seconds between checks
RESTART_DELAY=3      # seconds to wait before restarting a crashed service
MAX_RESTARTS=5       # max restarts per service before giving up
RESET_AFTER=300      # reset restart counter after this many seconds of stability

TTYD_RESTARTS=0
CS_RESTARTS=0
TTYD_LAST_RESTART=0
CS_LAST_RESTART=0

log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] $1"
}

restart_code_server() {
    NOW=$(date +%s)
    ELAPSED=$(( NOW - CS_LAST_RESTART ))

    # Reset counter if stable for a while
    if [ "$ELAPSED" -gt "$RESET_AFTER" ] && [ "$CS_RESTARTS" -gt 0 ]; then
        CS_RESTARTS=0
    fi

    if [ "$CS_RESTARTS" -ge "$MAX_RESTARTS" ]; then
        log "${RED}code-server has crashed $MAX_RESTARTS times. Giving up.${NC}"
        log "  Run 'docker restart claude-code' to try again."
        return 1
    fi

    CS_RESTARTS=$(( CS_RESTARTS + 1 ))
    CS_LAST_RESTART=$NOW

    log "${YELLOW}code-server is down. Restarting (attempt $CS_RESTARTS/$MAX_RESTARTS)...${NC}"
    sleep "$RESTART_DELAY"

    export XDG_CONFIG_HOME=/tmp/.config
    mkdir -p /tmp/.config

    CS_AUTH="${CODE_SERVER_AUTH:-none}"

    code-server \
        --bind-addr 0.0.0.0:8080 \
        --auth "$CS_AUTH" \
        --config /tmp/.config/code-server/config.yaml \
        --disable-telemetry \
        --disable-update-check \
        /home/coder/Documents/GitHub &

    sleep 3
    if curl -s -o /dev/null http://127.0.0.1:8080/ 2>/dev/null; then
        log "${GREEN}code-server restarted successfully.${NC}"
    else
        log "${YELLOW}code-server may still be starting up...${NC}"
    fi
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
log "Watchdog started. Checking services every ${CHECK_INTERVAL}s."

while true; do
    sleep "$CHECK_INTERVAL"

    # Check code-server
    if ! curl -s -o /dev/null http://127.0.0.1:8080/ 2>/dev/null; then
        # Double-check after a brief pause (avoid false positives)
        sleep 2
        if ! curl -s -o /dev/null http://127.0.0.1:8080/ 2>/dev/null; then
            restart_code_server
        fi
    fi

    # Note: ttyd is the foreground process (PID 1 via exec).
    # If ttyd dies, the container exits -- Docker restart policy handles that.
    # We just log a warning if it stops responding.
    if ! curl -s -o /dev/null http://127.0.0.1:7681/ 2>/dev/null; then
        sleep 2
        if ! curl -s -o /dev/null http://127.0.0.1:7681/ 2>/dev/null; then
            log "${RED}ttyd is not responding. The container may need a restart.${NC}"
            log "  Run: docker restart claude-code"
        fi
    fi
done
