#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Welcome Page Server
# Serves the landing page on port 3000 with a simple status API, plus the wiki
# at /wiki (rendered from the two markdown doc sets below).
# =============================================================================

export WELCOME_DIR="/opt/claude-code-docker/welcome"
export WELCOME_PORT="${WELCOME_PORT:-3000}"

# Wiki sources. The CCDW set is baked into the image; the make-it set is read
# live on every request so it tracks the skill updates applied at container start.
export WIKI_DOCS_DIR="${WIKI_DOCS_DIR:-/opt/claude-code-docker/docs/confluence}"
export WIKI_MAKEIT_DIR="${WIKI_MAKEIT_DIR:-/home/coder/.claude/make-it/confluence-docs}"

exec node /opt/claude-code-docker/scripts/welcome-server.js
