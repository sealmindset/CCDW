#!/bin/bash
# =============================================================================
# gh-session-setup.command — one-time GitHub session seeder (macOS host).
# Double-click (or run) once. Provisions Playwright + Chromium, opens a visible
# browser, you sign in to GitHub, and the session is saved for the dashboard's
# auto-authorize. Local-only single-user.
# =============================================================================
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"

if ! command -v npx >/dev/null 2>&1; then
  echo "  Node.js (npx) is required. Install Node, then re-run."
  read -r -p "  Press Return to close... " _ || true
  exit 1
fi

echo "  Provisioning the sign-in helper (first run only, ~1 min)..."
npx -y playwright install chromium >/dev/null 2>&1 || true

# Run the seeder with Playwright made available via npx -p.
npx -y -p playwright node "$SELF_DIR/gh-session-setup.mjs"
rc=$?

echo ""
[ "$rc" -eq 0 ] && echo "  Done — you can close this window." || echo "  Sign-in was not completed."
read -r -p "  Press Return to close... " _ || true
