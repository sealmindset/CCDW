#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Welcome Page Server
# Serves the landing page on port 3000 with a simple status API.
# =============================================================================

export WELCOME_DIR="/opt/claude-code-docker/welcome"
export WELCOME_PORT="${WELCOME_PORT:-3000}"

exec node /opt/claude-code-docker/scripts/welcome-server.js
