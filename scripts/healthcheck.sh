#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Health Check
# Verifies ttyd and code-server are responding
# =============================================================================

# Check ttyd
curl -f -s http://127.0.0.1:7681/ > /dev/null 2>&1 || exit 1

# Check code-server
curl -f -s http://127.0.0.1:8080/healthz > /dev/null 2>&1 || exit 1

exit 0
