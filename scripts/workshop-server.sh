#!/bin/bash
# =============================================================================
# Workshop Server Launcher
# Starts the Workshop Business User IDE on WORKSHOP_PORT (default: 9200)
# Auto-restarts on crash with backoff (max 5 retries in 60 seconds)
# =============================================================================

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSHOP_DIR="/opt/claude-code-docker/workshop"
PORT="${WORKSHOP_PORT:-9200}"
MAX_RESTARTS=5
RESTART_WINDOW=60
RESTART_COUNT=0
WINDOW_START=$(date +%s)

while true; do
    echo "$(date '+%Y-%m-%d %H:%M:%S') [workshop] Starting Workshop on port $PORT"
    node "$WORKSHOP_DIR/server.js"
    EXIT_CODE=$?

    NOW=$(date +%s)
    ELAPSED=$(( NOW - WINDOW_START ))

    # Reset counter if outside the restart window
    if [ "$ELAPSED" -ge "$RESTART_WINDOW" ]; then
        RESTART_COUNT=0
        WINDOW_START=$NOW
    fi

    RESTART_COUNT=$(( RESTART_COUNT + 1 ))

    if [ "$RESTART_COUNT" -ge "$MAX_RESTARTS" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [workshop] Too many restarts ($RESTART_COUNT in ${ELAPSED}s). Giving up."
        break
    fi

    DELAY=$(( RESTART_COUNT * 2 ))
    echo "$(date '+%Y-%m-%d %H:%M:%S') [workshop] Crashed (exit $EXIT_CODE). Restarting in ${DELAY}s... (attempt $RESTART_COUNT/$MAX_RESTARTS)"
    sleep "$DELAY"
done
