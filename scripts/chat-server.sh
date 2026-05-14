#!/bin/bash
# =============================================================================
# Claude Chat Server Launcher
# Starts Claude Chat on CHAT_PORT (default: 3002)
# Auto-restarts on crash with backoff (max 5 retries in 60 seconds)
# =============================================================================

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
CHAT_DIR="/opt/claude-code-docker/chat"
PORT="${CHAT_PORT:-3002}"
MAX_RESTARTS=5
RESTART_WINDOW=60
RESTART_COUNT=0
WINDOW_START=$(date +%s)

while true; do
    echo "$(date '+%Y-%m-%d %H:%M:%S') [chat] Starting Claude Chat on port $PORT"
    node "$CHAT_DIR/server.js"
    EXIT_CODE=$?

    NOW=$(date +%s)
    ELAPSED=$(( NOW - WINDOW_START ))

    if [ "$ELAPSED" -ge "$RESTART_WINDOW" ]; then
        RESTART_COUNT=0
        WINDOW_START=$NOW
    fi

    RESTART_COUNT=$(( RESTART_COUNT + 1 ))

    if [ "$RESTART_COUNT" -ge "$MAX_RESTARTS" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [chat] Too many restarts ($RESTART_COUNT in ${ELAPSED}s). Giving up."
        break
    fi

    DELAY=$(( RESTART_COUNT * 2 ))
    echo "$(date '+%Y-%m-%d %H:%M:%S') [chat] Crashed (exit $EXIT_CODE). Restarting in ${DELAY}s... (attempt $RESTART_COUNT/$MAX_RESTARTS)"
    sleep "$DELAY"
done
