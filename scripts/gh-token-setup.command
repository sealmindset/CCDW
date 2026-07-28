#!/bin/bash
# =============================================================================
# gh-token-setup.command — store a GitHub Personal Access Token for CCDW.
#
# Zero-touch GitHub sign-in for orgs that enforce SAML SSO + MFA (which blocks
# headless device-flow auth). You create a token ONCE, SSO-authorize it for the
# org in the browser, paste it here. CCDW then logs in with no browser, and it
# survives restarts. Local-only single-user; the token is saved with 600 perms.
#
# Token creation (fine-grained or classic):
#   1. https://github.com/settings/tokens  -> Generate new token
#   2. Scopes: repo, read:org, gist  (classic) — or equivalent fine-grained perms
#   3. After creating, click "Configure SSO" / "Authorize" next to your org
#      so the token is SSO-authorized (REQUIRED, or gh will be denied org access)
# =============================================================================
set -uo pipefail

STATE_DIR="$HOME/Documents/.ccdw"
TOKEN_FILE="$STATE_DIR/gh-token"
mkdir -p "$STATE_DIR"

echo ""
echo "  Paste your GitHub Personal Access Token (input hidden), then press Return."
echo "  (Create one at https://github.com/settings/tokens — scopes: repo, read:org, gist —"
echo "   then click Configure SSO / Authorize next to your org.)"
echo ""
printf "  Token: "
# Hidden input.
stty -echo 2>/dev/null
read -r TOKEN
stty echo 2>/dev/null
echo ""

if [ -z "${TOKEN:-}" ]; then
  echo "  No token entered. Nothing saved."
  read -r -p "  Press Return to close... " _ || true
  exit 1
fi

# Basic sanity: GitHub tokens start with ghp_/github_pat_/gho_ and are long.
case "$TOKEN" in
  ghp_*|github_pat_*|gho_*|ghu_*|ghs_*) : ;;
  *) echo "  Warning: that doesn't look like a GitHub token, saving anyway." ;;
esac

printf '%s' "$TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"
echo "  ✓ Token saved to $TOKEN_FILE (readable only by you)."
echo "  CCDW will sign in to GitHub automatically — no browser needed."
echo ""
read -r -p "  Press Return to close... " _ || true
