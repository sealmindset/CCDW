#!/usr/bin/env bash
# =============================================================================
# az-auto-login.sh — automate the Azure device-code sign-in for the CCDW
# container, driven from the host launcher.
#
# What it does:
#   1. Runs `az login --use-device-code` INSIDE the container (that's where the
#      token must land — the mounted ~/.azure file cache persists it).
#   2. Captures the device code + verification URL.
#   3. Opens the PRE-FILLED device-login page (…/devicelogin?otc=CODE) in the
#      user's default browser — the code is already entered, and the browser
#      reuses their existing Microsoft session (often just an MFA approval).
#      Also copies the code to the clipboard as a fallback.
#   4. Polls until the container is authenticated, then returns.
#
# The password / MFA step is the user's — corporate SSO with MFA cannot (and
# for security must not) be fully scripted. Everything else is automatic.
#
# Optional: CCDW_USE_PLAYWRIGHT=1 drives a scripted headed browser via
# scripts/az-login.mjs instead of the default browser (advances the page for
# the user); falls back to the default browser if Playwright/node is missing.
#
# Env: CONTAINER_NAME (default claude-code), CCDW_AZ_LOGIN_TIMEOUT secs (180).
# Exit: 0 when authenticated, 1 otherwise (caller keeps working; AI just waits).
# =============================================================================

# Not `set -e`: we handle every failure explicitly so the launcher never dies.
set -uo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-claude-code}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
CCDW_REPO_DIR="${CCDW_REPO_DIR:-$(cd "${SELF_DIR}/.." 2>/dev/null && pwd)}"
TIMEOUT="${CCDW_AZ_LOGIN_TIMEOUT:-180}"
# The token audience Azure AI Foundry needs.
FOUNDRY_RESOURCE="${AZURE_FOUNDRY_RESOURCE:-https://cognitiveservices.azure.com}"

log() { printf '  %s\n' "$*"; }
_env() { grep -E "^$1=" "$CCDW_REPO_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r' || true; }

command -v docker >/dev/null 2>&1 || { log "Docker isn't available."; exit 1; }

# -------------------------------------------------------------------------
# INVISIBLE paths first — the user should see nothing when any of these work.
# -------------------------------------------------------------------------

# (1) Silent: can az already mint a Foundry token? This is true when there is a
# valid session OR a cached refresh token that refreshes with NO prompt (i.e.
# the user signed in interactively once before). No browser, no MFA.
if docker exec "$CONTAINER_NAME" az account get-access-token \
    --resource "$FOUNDRY_RESOURCE" >/dev/null 2>&1; then
    exit 0
fi

# (2) Headless: a Service Principal (no user, no MFA) if configured in .env.
# AZURE_CLIENT_ID / AZURE_CLIENT_SECRET / AZURE_TENANT_ID. This is the proper
# zero-touch-forever path for shared/unattended use.
_sp_id="$(_env AZURE_CLIENT_ID)"
_sp_secret="$(_env AZURE_CLIENT_SECRET)"
_sp_tenant="$(_env AZURE_TENANT_ID)"
if [ -n "$_sp_id" ] && [ -n "$_sp_secret" ] && [ -n "$_sp_tenant" ]; then
    if docker exec "$CONTAINER_NAME" az login --service-principal \
        -u "$_sp_id" -p "$_sp_secret" --tenant "$_sp_tenant" >/dev/null 2>&1; then
        exit 0
    fi
fi

# -------------------------------------------------------------------------
# (3) Interactive — no cached session and no Service Principal. A ONE-TIME
# device-code login is required; MFA is the user's step and cannot be skipped.
# After this, path (1) keeps every future launch silent for ~90 days.
# -------------------------------------------------------------------------
log "Signing you in to Azure..."

outfile="$(mktemp -t ccdw-az-login 2>/dev/null || echo /tmp/ccdw-az-login.$$)"
# Run az login in the container; its output streams to a host temp file. The
# container az process stays alive waiting for the device authorization.
docker exec "$CONTAINER_NAME" az login --use-device-code >"$outfile" 2>&1 &
az_pid=$!

# Extract the device code + URL (same parsing login-wizard.sh uses).
code=""
url=""
i=0
while [ -z "$code" ] && [ "$i" -lt 60 ]; do
    sleep 0.5
    i=$((i + 1))
    code="$(sed -n 's/.*enter the code \([A-Z0-9]*\) to.*/\1/p' "$outfile" 2>/dev/null | head -1)"
    if [ -z "$url" ]; then
        url="$(sed -n 's#.*\(https://[a-zA-Z0-9./-]*devicelogin[a-zA-Z0-9./-]*\).*#\1#p' "$outfile" 2>/dev/null | head -1)"
    fi
done
url="${url:-https://microsoft.com/devicelogin}"

if [ -z "$code" ]; then
    log "Couldn't start Azure sign-in automatically."
    log "Open the Web Terminal (the >_ button) and run:  az login --use-device-code"
    kill "$az_pid" 2>/dev/null || true
    rm -f "$outfile" 2>/dev/null || true
    exit 1
fi

prefilled="${url}?otc=${code}"
printf '%s' "$code" | pbcopy 2>/dev/null || true

log "A browser is opening — the code ($code) is already filled in and copied."
log "Approve the sign-in / MFA prompt if asked. Waiting for you to finish..."

if [ "${CCDW_USE_PLAYWRIGHT:-0}" = "1" ] && command -v node >/dev/null 2>&1 \
    && [ -f "$SELF_DIR/az-login.mjs" ]; then
    node "$SELF_DIR/az-login.mjs" "$prefilled" >/dev/null 2>&1 &
else
    open "$prefilled" >/dev/null 2>&1 || true
fi

# Poll until the container is authenticated, or the az process exits, or timeout.
authed=0
waited=0
while [ "$waited" -lt "$TIMEOUT" ]; do
    if docker exec "$CONTAINER_NAME" az account show >/dev/null 2>&1; then
        authed=1
        break
    fi
    # If the az login process already exited, give it one last check then stop.
    if ! kill -0 "$az_pid" 2>/dev/null; then
        docker exec "$CONTAINER_NAME" az account show >/dev/null 2>&1 && authed=1
        break
    fi
    sleep 2
    waited=$((waited + 2))
done

kill "$az_pid" 2>/dev/null || true
rm -f "$outfile" 2>/dev/null || true

if [ "$authed" = "1" ]; then
    log "Signed in to Azure — AI is ready."
    exit 0
fi

log "Sign-in didn't finish in time. You can complete it in the Web Terminal:  az login --use-device-code"
exit 1
