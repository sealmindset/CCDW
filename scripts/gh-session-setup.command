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
# Install Playwright into the repo so the .mjs can `import 'playwright'`.
# (ESM resolves bare imports from the script's dir tree, NOT npx's temp
# node_modules — so `npx -p playwright node ...` fails with MODULE_NOT_FOUND.)
REPO_DIR="$(cd "$SELF_DIR/.." 2>/dev/null && pwd)"
if [ ! -d "$REPO_DIR/node_modules/playwright" ]; then
  ( cd "$REPO_DIR" && npm install playwright@1.61.1 >/dev/null 2>&1 )
fi
npx -y playwright install chromium >/dev/null 2>&1 || true

# Run the seeder; playwright resolves from $REPO_DIR/node_modules.
node "$SELF_DIR/gh-session-setup.mjs"
rc=$?

echo ""
[ "$rc" -eq 0 ] && echo "  Done — you can close this window." || echo "  Sign-in was not completed."
read -r -p "  Press Return to close... " _ || true
