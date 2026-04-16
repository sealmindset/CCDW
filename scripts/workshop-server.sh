#!/bin/bash
# =============================================================================
# Workshop Server Launcher
# Starts the Workshop Business User IDE on WORKSHOP_PORT (default: 9200)
# =============================================================================

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSHOP_DIR="/opt/claude-code-docker/workshop"
PORT="${WORKSHOP_PORT:-9200}"

echo "$(date '+%Y-%m-%d %H:%M:%S') [workshop] Starting Workshop on port $PORT"

exec node "$WORKSHOP_DIR/server.js"
