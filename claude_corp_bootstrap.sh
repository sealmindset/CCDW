#!/usr/bin/env bash
#
# ============================================================================
# claude_corp_bootstrap.sh
#   Install every prerequisite to run Claude Code NATIVE on a corporate Mac
#   and wire it up to AZURE AI FOUNDRY (Azure Entra-token auth) instead of the
#   public claude.ai OAuth login. Installs Claude Code itself, installs the
#   Azure CLI, configures ~/.claude/settings.json + a token helper, then
#   verifies — surfacing corporate network/cert/VPN issues clearly instead of
#   dying cryptically.
#
#   In Foundry mode there is NO claude.ai browser OAuth: authentication is an
#   Azure access token minted by 'az' and handed to Claude Code via apiKeyHelper.
#
#   Usage (quick):
#     curl -fsSL https://raw.githubusercontent.com/<org>/<repo>/main/claude_corp_bootstrap.sh | bash
#
#   Usage (safer — inspect first, then run the SAME file you read):
#     curl -fsSL https://raw.githubusercontent.com/<org>/<repo>/main/claude_corp_bootstrap.sh -o /tmp/claude_corp_bootstrap.sh
#     less /tmp/claude_corp_bootstrap.sh
#     shasum -a 256 /tmp/claude_corp_bootstrap.sh    # compare to published checksum
#     bash /tmp/claude_corp_bootstrap.sh
#
#   Configurable via env vars (defaults are Sleep Number's working values):
#     FOUNDRY_BASE_URL  FOUNDRY_SONNET  FOUNDRY_HAIKU  FOUNDRY_OPUS
#     FOUNDRY_TOKEN_RESOURCE  FOUNDRY_DEFAULT_MODEL
#
#   Safe to re-run: every step is idempotent (skips if already present).
# ============================================================================
#
set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true   # macOS /bin/bash 3.2 lacks this; guard it
IFS=$'\n\t'                                     # safer word-splitting: drop the space

# ----------------------------------------------------------------------------
# Foundry configuration — override via env; defaults are Sleep Number's working
# values. These flow into ~/.claude/settings.json and the TLS/allowlist checks.
# ----------------------------------------------------------------------------
FOUNDRY_BASE_URL="${FOUNDRY_BASE_URL:-https://snapistg-scus.azure.sleepnumber.com/anthropic}"
FOUNDRY_SONNET="${FOUNDRY_SONNET:-claude-sonnet-4-6}"
FOUNDRY_HAIKU="${FOUNDRY_HAIKU:-claude-haiku-4-5}"
FOUNDRY_OPUS="${FOUNDRY_OPUS:-claude-opus-4-8}"
FOUNDRY_TOKEN_RESOURCE="${FOUNDRY_TOKEN_RESOURCE:-https://cognitiveservices.azure.com}"
FOUNDRY_DEFAULT_MODEL="${FOUNDRY_DEFAULT_MODEL:-opus}"

CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
TOKEN_HELPER="${CLAUDE_DIR}/get-claude-token.sh"
# apiKeyHelper as stored in settings.json (keep the literal ~ form the user runs).
TOKEN_HELPER_TILDE="~/.claude/get-claude-token.sh"

# Derive the Foundry hostname from the base URL for connectivity checks.
FOUNDRY_HOST="${FOUNDRY_BASE_URL#*://}"   # strip scheme
FOUNDRY_HOST="${FOUNDRY_HOST%%/*}"        # strip path
FOUNDRY_HOST="${FOUNDRY_HOST%%:*}"        # strip port

# ----------------------------------------------------------------------------
# Colored logging — degrades gracefully on non-TTY (no color when piped) and
# honors the NO_COLOR convention.
# ----------------------------------------------------------------------------
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]] && command -v tput >/dev/null 2>&1 \
   && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[0;31m'; C_YEL=$'\033[1;33m'
  C_GRN=$'\033[0;32m'; C_BLU=$'\033[0;34m'
else
  C_RESET=''; C_RED=''; C_YEL=''; C_GRN=''; C_BLU=''
fi

WARN_COUNT=0
step()    { printf '\n%s[STEP]%s %s\n'    "${C_BLU}" "${C_RESET}" "$*"; }
info()    { printf '%s[INFO]%s  %s\n'      "${C_BLU}" "${C_RESET}" "$*"; }
success() { printf '%s[ OK ]%s  %s\n'      "${C_GRN}" "${C_RESET}" "$*"; }
warn()    { printf '%s[WARN]%s  %s\n'      "${C_YEL}" "${C_RESET}" "$*" >&2; WARN_COUNT=$((WARN_COUNT+1)); }
error()   { printf '%s[FAIL]%s  %s\n'      "${C_RED}" "${C_RESET}" "$*" >&2; }

# ----------------------------------------------------------------------------
# ERR trap — print the failing line number + command and a friendly message.
# ----------------------------------------------------------------------------
trap 'rc=$?; printf "\n%s[FAIL]%s ERROR on line %s: '\''%s'\'' (exit %s)\n" \
      "${C_RED}" "${C_RESET}" "${LINENO}" "${BASH_COMMAND}" "${rc}" >&2; \
      printf "       See the output above. Re-running this script is safe — it is idempotent.\n" >&2; \
      exit "${rc}"' ERR

# Trackers for the final summary.
SUMMARY_LINES=()
ARCH_LABEL=""
BREW_PREFIX=""
MACOS_VER=""
CLAUDE_OK="no"
AZ_LOGGED_IN="no"
TOKEN_OK="no"
record() { SUMMARY_LINES+=("$*"); }

# ----------------------------------------------------------------------------
# Banner
# ----------------------------------------------------------------------------
banner() {
  printf '%s' "${C_BLU}"
  cat <<'EOF'
============================================================
  Claude Code — Corporate macOS Bootstrap
  Target: AZURE AI FOUNDRY (Azure-token auth)
============================================================
EOF
  printf '%s' "${C_RESET}"
  info "This installs prerequisites, Claude Code (native) + the Azure CLI,"
  info "configures Foundry auth, then verifies. Safe to re-run."
  info "No claude.ai browser login is used — auth is an Azure access token."
}

# ----------------------------------------------------------------------------
# Pre-flight: not root, macOS, curl present, arch + macOS version
# ----------------------------------------------------------------------------
preflight_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    error "You are running this script as root."
    warn  "Homebrew refuses to run as root and your dotfiles would land in /var/root."
    warn  "Re-run as your normal user, WITHOUT sudo. Aborting."
    exit 1
  fi
  # Elevate only specific commands later via $SUDO (CLT install may prompt a GUI).
  if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else SUDO=""; fi
}

detect_arch() {
  case "$(uname -m)" in
    arm64)  BREW_PREFIX="/opt/homebrew" ; ARCH_LABEL="Apple Silicon (arm64)" ;;
    x86_64) BREW_PREFIX="/usr/local"    ; ARCH_LABEL="Intel (x86_64)" ;;
    *)      error "Unsupported architecture: $(uname -m)"; exit 1 ;;
  esac
}

preflight() {
  step "Pre-flight checks"

  if [[ "$(uname)" != "Darwin" ]]; then
    error "This script only supports macOS (uname=$(uname)). Aborting."
    exit 1
  fi

  if ! command -v curl >/dev/null 2>&1; then
    error "curl is required but was not found on PATH. Aborting."
    exit 1
  fi

  MACOS_VER="$(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
  info "Detected architecture : ${ARCH_LABEL}"
  info "Homebrew prefix       : ${BREW_PREFIX}"
  info "macOS version         : ${MACOS_VER}"
  info "Foundry base URL      : ${FOUNDRY_BASE_URL}"
  info "Foundry host          : ${FOUNDRY_HOST}"
  info "Token audience        : ${FOUNDRY_TOKEN_RESOURCE}"

  # macOS 13.0+ is required by the current native Claude Code binary.
  local major
  major="${MACOS_VER%%.*}"
  if [[ "$major" =~ ^[0-9]+$ ]] && (( major < 13 )); then
    warn "Claude Code requires macOS 13.0+. You are on ${MACOS_VER}."
    warn "The native binary may fail with 'dyld: Symbol not found: _ubrk_clone' / 'Abort trap: 6'."
    warn "Consider upgrading macOS before relying on Claude Code."
    record "macOS version : ${MACOS_VER} (BELOW required 13.0 — Claude Code may not run)"
  else
    success "macOS ${MACOS_VER} meets the 13.0+ requirement."
    record "macOS version : ${MACOS_VER} (meets 13.0+ requirement)"
  fi
  record "Architecture  : ${ARCH_LABEL}"
}

# ----------------------------------------------------------------------------
# Corporate network pre-flight: TLS inspection / connectivity.
# Probes the FOUNDRY host and the Azure login endpoint (the hosts that actually
# matter for Foundry auth). Detects the "unable to get local issuer certificate"
# case and surfaces a clear, actionable WARNING — but DOES NOT hard-fail.
# ----------------------------------------------------------------------------
probe_host() {
  # $1 = url ; sets globals PROBE_RC / PROBE_OUT
  local url="$1"
  PROBE_OUT="$(curl -sS -v --max-time 20 "$url" 2>&1)" && PROBE_RC=0 || PROBE_RC=$?
}

check_corp_network() {
  step "Corporate network / TLS-inspection check"

  info "The Foundry host is internal and likely requires the corporate VPN."

  local any_tls_issue="no"
  local h url
  for h in "${FOUNDRY_HOST}" "login.microsoftonline.com"; do
    url="https://${h}/"
    probe_host "$url"

    if [[ "$PROBE_RC" -eq 0 ]]; then
      success "Reached ${h} with a trusted TLS chain."
      continue
    fi

    # curl exit 60 = CURLE_PEER_FAILED_VERIFICATION (TLS inspection / untrusted CA)
    if [[ "$PROBE_RC" -eq 60 ]] || printf '%s\n' "$PROBE_OUT" | grep -qiE 'unable to get local issuer certificate|self.signed|SSL certificate problem|SELF_SIGNED_CERT_IN_CHAIN'; then
      local issuer
      issuer="$(printf '%s\n' "$PROBE_OUT" | grep -i 'issuer:' | head -1)"
      error "TLS certificate verification to ${h} FAILED (curl exit ${PROBE_RC})."
      warn  "This almost always means a corporate TLS-inspection proxy is re-signing HTTPS"
      warn  "traffic with a corporate root CA that this machine does not yet trust"
      warn  "(e.g. Zscaler, Netskope, CrowdStrike Falcon, Palo Alto, Cisco Umbrella, Forcepoint)."
      [[ -n "$issuer" ]] && warn "Certificate issuer seen in the chain:${issuer#*issuer:}"
      any_tls_issue="yes"
      continue
    fi

    # Any other curl failure: DNS block, firewall, VPN-off, timeout, etc.
    error "Could not reach ${h} (curl exit ${PROBE_RC})."
    if printf '%s\n' "$PROBE_OUT" | grep -qi 'could not resolve host'; then
      warn "DNS could not resolve ${h} — likely DNS filtering or VPN is off."
      [[ "$h" == "${FOUNDRY_HOST}" ]] && warn "The Foundry host is internal — CONNECT THE CORPORATE VPN and re-run."
    else
      warn "Possible firewall block, VPN requirement, or timeout. Check connectivity/VPN."
    fi
  done

  cat >&2 <<EOF

  ---------------------------------------------------------------------------
  WHAT TO ASK YOUR IT / ENDPOINT TEAM FOR:
    1. The corporate ROOT CA as a .pem file (so tools can trust the proxy).
    2. Confirm you are on the CORPORATE VPN (the Foundry host is internal).
    3. Allowlist these hostnames on port 443 (egress):
         ${FOUNDRY_HOST}        (Azure AI Foundry endpoint — internal/VPN)
         login.microsoftonline.com   (Azure Entra ID auth)
         login.microsoft.com         (Azure Entra ID auth)
         management.azure.com        (Azure Resource Manager)
         cognitiveservices.azure.com (token audience / data plane)
         claude.ai                   (to DOWNLOAD the Claude Code installer)
         downloads.anthropic.com     (installer / auto-updater)
         raw.githubusercontent.com   (Homebrew install script)
         github.com                  (Homebrew / tooling)
    4. The HTTP/HTTPS proxy address, if an explicit proxy is required.

  HOW TO MAKE TOOLS TRUST THE CORPORATE CA (do NOT disable TLS verification):
    # For curl / Homebrew during install:
      export CURL_CA_BUNDLE=/path/to/corp-root-ca.pem
      export SSL_CERT_FILE=/path/to/corp-root-ca.pem
      export HOMEBREW_CA_BUNDLE=/path/to/corp-root-ca.pem
    # For Claude Code at runtime, EITHER:
      export NODE_EXTRA_CA_CERTS=/path/to/corp-root-ca.pem
    # OR trust the OS Keychain (where MDM usually installs the corp root):
      export CLAUDE_CODE_CERT_STORE=bundled,system   # this is the default
    # If you go through an explicit proxy:
      export HTTPS_PROXY=http://proxy.corp.example.com:8080
      export HTTP_PROXY=http://proxy.corp.example.com:8080

  Continuing anyway so tools still get installed.
  ---------------------------------------------------------------------------

EOF

  if [[ "$any_tls_issue" == "yes" ]]; then
    record "Network/TLS   : WARNING — TLS inspection / untrusted CA detected (see notes above)"
  else
    record "Network/TLS   : checked ${FOUNDRY_HOST} + login.microsoftonline.com (see notes)"
  fi
  return 0
}

# ----------------------------------------------------------------------------
# Xcode Command Line Tools (provides git + build tooling Claude often invokes)
# ----------------------------------------------------------------------------
ensure_clt() {
  step "Xcode Command Line Tools"

  if xcode-select -p >/dev/null 2>&1; then
    success "Command Line Tools already installed at: $(xcode-select -p)"
    record "Xcode CLT     : already installed"
    return 0
  fi

  info "Command Line Tools not found — launching the installer."
  warn "This opens a GUI dialog to confirm the download. Finish it, then re-run this script."
  # xcode-select --install pops a GUI confirm/download dialog; no fully silent
  # supported path exists. On managed fleets, MDM usually pushes the CLT instead.
  xcode-select --install 2>/dev/null || true
  warn "After the Command Line Tools finish installing, re-run this bootstrap script."
  record "Xcode CLT     : installer launched — finish the GUI dialog, then re-run"
}

# ----------------------------------------------------------------------------
# Homebrew (optional but the cleanest way to guarantee git + jq + az on managed
# Macs). Installs if missing, then idempotently wires shellenv into ~/.zprofile.
# ----------------------------------------------------------------------------
ensure_line() {
  # Append $1 to file $2 only if not already present (literal grep -F).
  local line="$1" file="${2:-${HOME}/.zprofile}"
  touch "$file"
  if grep -qF -- "$line" "$file"; then
    info "Already configured in $(basename "$file") — skipping append."
  else
    printf '\n%s\n' "$line" >> "$file"
    success "Added to $(basename "$file"): ${line}"
  fi
}

ensure_homebrew() {
  step "Homebrew"

  if command -v brew >/dev/null 2>&1; then
    success "Homebrew already installed ($(brew --version 2>/dev/null | head -1))"
    record "Homebrew      : already installed"
  elif [[ -x "${BREW_PREFIX}/bin/brew" ]]; then
    success "Homebrew found at ${BREW_PREFIX}/bin/brew (not yet on PATH)."
    record "Homebrew      : already installed (${BREW_PREFIX})"
  else
    info "Installing Homebrew (non-interactive)…"
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    record "Homebrew      : installed"
  fi

  # Wire shellenv into ~/.zprofile (the macOS-correct file) — grep-guarded so it
  # is never duplicated — then eval it for the current session.
  if [[ -x "${BREW_PREFIX}/bin/brew" ]]; then
    ensure_line "eval \"\$(${BREW_PREFIX}/bin/brew shellenv)\"" "${HOME}/.zprofile"
    eval "$("${BREW_PREFIX}/bin/brew" shellenv)"
    # Authoritative prefix once brew is on PATH (robust against Rosetta edge cases).
    BREW_PREFIX="$(brew --prefix 2>/dev/null || echo "$BREW_PREFIX")"
    success "Homebrew is on PATH for this session (prefix: ${BREW_PREFIX})."
  else
    warn "Homebrew binary not found at ${BREW_PREFIX}/bin/brew after install step."
    warn "If the install was blocked by TLS inspection, see the network notes above."
    record "Homebrew      : WARNING — not on PATH; see notes"
  fi
}

# ----------------------------------------------------------------------------
# git — should come with the CLT and/or Homebrew. Verify; install via brew if
# missing and brew is available.
# ----------------------------------------------------------------------------
ensure_git() {
  step "git"

  if command -v git >/dev/null 2>&1; then
    success "git available: $(git --version 2>/dev/null)"
    record "git           : $(git --version 2>/dev/null)"
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    info "git not found — installing via Homebrew…"
    brew install git
    success "git installed: $(git --version 2>/dev/null)"
    record "git           : installed via Homebrew"
  else
    warn "git not found and Homebrew unavailable. It normally ships with the Xcode CLT."
    warn "Finish the Command Line Tools install (above), then re-run this script."
    record "git           : MISSING — install Xcode CLT or Homebrew, then re-run"
  fi
}

# ----------------------------------------------------------------------------
# jq — required for the safe settings.json deep-merge. Install via brew if
# missing.
# ----------------------------------------------------------------------------
ensure_jq() {
  step "jq (needed for safe settings.json merge)"

  if command -v jq >/dev/null 2>&1; then
    success "jq available: $(jq --version 2>/dev/null)"
    record "jq            : $(jq --version 2>/dev/null)"
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    info "jq not found — installing via Homebrew…"
    brew install jq
    success "jq installed: $(jq --version 2>/dev/null)"
    record "jq            : installed via Homebrew"
  else
    warn "jq not found and Homebrew unavailable. The settings merge will fall back"
    warn "to writing a sidecar file you must merge by hand. Install Homebrew + jq."
    record "jq            : MISSING — settings merge will use a sidecar fallback"
  fi
}

# ----------------------------------------------------------------------------
# Azure CLI (az) — the token source for Foundry auth. Install via brew if
# missing (idempotent). Then check login state; DO NOT force an interactive
# login from the script — instruct the user instead.
# ----------------------------------------------------------------------------
ensure_azure_cli() {
  step "Azure CLI (az) — Foundry token source"

  if command -v az >/dev/null 2>&1; then
    success "Azure CLI already installed ($(az version --query '\"azure-cli\"' -o tsv 2>/dev/null || echo present))."
    record "Azure CLI     : already installed"
  elif command -v brew >/dev/null 2>&1; then
    info "Azure CLI not found — installing via Homebrew (this can take a few minutes)…"
    brew install azure-cli
    success "Azure CLI installed ($(az version --query '\"azure-cli\"' -o tsv 2>/dev/null || echo present))."
    record "Azure CLI     : installed via Homebrew"
  else
    warn "Azure CLI not found and Homebrew unavailable. Install Homebrew, then re-run."
    record "Azure CLI     : MISSING — install Homebrew then re-run"
    return 0
  fi

  # Login-state gate — exit-code on 'az account show'. Never auto-launch login.
  if az account show >/dev/null 2>&1; then
    success "Azure CLI is logged in."
    AZ_LOGGED_IN="yes"
    record "Azure login   : logged in"
  else
    warn "Azure CLI is NOT logged in. You must log in yourself (the script will not):"
    warn "    az login --use-device-code"
    warn "Device-code is recommended on corporate networks (avoids the loopback browser flow)."
    cat >&2 <<'EOF'

  CORPORATE-CA GOTCHA for 'az login':
    REQUESTS_CA_BUNDLE *REPLACES* the trust store — it does NOT augment it.
    Pointing it only at the corporate CA breaks validation of Microsoft endpoints.
    If 'az login' fails on certificate validation, build a COMBINED bundle:

      CERT_DIR="$HOME/.azure/certs"; mkdir -p "$CERT_DIR"
      CACERT=$(find "$(brew --prefix)/Cellar/azure-cli" -name cacert.pem | head -n1)
      cat "$CACERT" /path/to/corp-ca-chain.pem > "$CERT_DIR/combined-ca.pem"
      export REQUESTS_CA_BUNDLE="$CERT_DIR/combined-ca.pem"
      export SSL_CERT_FILE="$CERT_DIR/combined-ca.pem"   # set BOTH
    Rebuild the combined bundle after every 'az' upgrade (the certifi path moves).
    Note: the Foundry host is internal — connect the corporate VPN first.

EOF
    record "Azure login   : NOT logged in — run 'az login --use-device-code'"
  fi
}

# ----------------------------------------------------------------------------
# Token helper — ~/.claude/get-claude-token.sh (chmod 700). Fixed content, so
# overwrite is fine; but back up any pre-existing DIFFERENT file once.
# ----------------------------------------------------------------------------
ensure_token_helper() {
  step "Foundry token helper (~/.claude/get-claude-token.sh)"

  mkdir -p "$CLAUDE_DIR"

  # Built with the resolved token resource interpolated in. stdout of this helper
  # MUST be the bare token ONLY (Claude Code uses it as the bearer), so the login
  # fallback uses device-code and writes its prompt to stderr — never to stdout,
  # and never to /dev/null (so the user can see the code if a login is needed).
  local desired
  printf -v desired '%s\n' \
'#!/bin/bash' \
'# Auto-generated by claude_corp_bootstrap.sh — emits an Azure AD bearer token' \
'# for Claude Code (apiKeyHelper). stdout MUST be the bare token only.' \
"if ! az account get-access-token --resource \"${FOUNDRY_TOKEN_RESOURCE}\" > /dev/null 2>&1; then" \
'    az login --use-device-code 1>&2 || true' \
'fi' \
"az account get-access-token --resource \"${FOUNDRY_TOKEN_RESOURCE}\" --query accessToken -o tsv"
  desired="${desired%$'\n'}"   # drop the single trailing newline for clean idempotency match

  if [[ -f "$TOKEN_HELPER" ]] && [[ "$(cat "$TOKEN_HELPER")" == "$desired" ]]; then
    success "Token helper already present with the expected content."
  else
    if [[ -f "$TOKEN_HELPER" ]]; then
      local backup="${TOKEN_HELPER}.$(date +%Y%m%d-%H%M%S).bak"
      cp -p "$TOKEN_HELPER" "$backup"
      warn "Existing token helper differed — backed up to ${backup}."
    fi
    printf '%s\n' "$desired" > "$TOKEN_HELPER"
    success "Wrote ${TOKEN_HELPER}."
  fi

  chmod 700 "$TOKEN_HELPER"
  success "Token helper is chmod 700."
  record "Token helper  : ${TOKEN_HELPER} (chmod 700)"

  # Verify it runs (only meaningful if az is logged in). Never print the token.
  if [[ "$AZ_LOGGED_IN" == "yes" ]]; then
    if [[ -n "$("$TOKEN_HELPER" 2>/dev/null | head -c 16)" ]]; then
      success "Token helper emitted a non-empty token."
      TOKEN_OK="yes"
      record "Token check   : OK (non-empty Azure token emitted)"
    else
      warn "Token helper ran but emitted no token. Check 'az login' / VPN / RBAC role."
      record "Token check   : WARNING — helper produced no token"
    fi
  else
    warn "Skipping live token check — not logged in. Run 'az login --use-device-code' then re-run."
    record "Token check   : skipped (az not logged in)"
  fi
}

# ----------------------------------------------------------------------------
# settings.json — safe, idempotent, atomic deep-merge of the Foundry keys.
# Uses jq '$base * $patch' (patch wins; existing plugins/marketplaces/env keys
# preserved). Backs up first, validates result before replacing. Falls back to a
# sidecar file if jq is unavailable.
# ----------------------------------------------------------------------------
ensure_settings() {
  step "Merge Foundry config into ~/.claude/settings.json"

  mkdir -p "$CLAUDE_DIR"

  # Build the patch with jq so values are correctly JSON-encoded.
  local patch
  if command -v jq >/dev/null 2>&1; then
    patch="$(jq -n \
      --arg helper "$TOKEN_HELPER_TILDE" \
      --arg model  "$FOUNDRY_DEFAULT_MODEL" \
      --arg baseurl "$FOUNDRY_BASE_URL" \
      --arg sonnet "$FOUNDRY_SONNET" \
      --arg haiku  "$FOUNDRY_HAIKU" \
      --arg opus   "$FOUNDRY_OPUS" \
      '{
         apiKeyHelper: $helper,
         model: $model,
         env: {
           CLAUDE_CODE_USE_FOUNDRY: "1",
           ANTHROPIC_FOUNDRY_BASE_URL: $baseurl,
           ANTHROPIC_DEFAULT_SONNET_MODEL: $sonnet,
           ANTHROPIC_DEFAULT_HAIKU_MODEL: $haiku,
           ANTHROPIC_DEFAULT_OPUS_MODEL: $opus
         }
       }')"
  fi

  # --- jq unavailable: write a sidecar; never hand-merge JSON in bash. -------
  if ! command -v jq >/dev/null 2>&1; then
    local sidecar="${CLAUDE_DIR}/settings.foundry.json"
    cat > "$sidecar" <<EOF
{
  "apiKeyHelper": "${TOKEN_HELPER_TILDE}",
  "model": "${FOUNDRY_DEFAULT_MODEL}",
  "env": {
    "CLAUDE_CODE_USE_FOUNDRY": "1",
    "ANTHROPIC_FOUNDRY_BASE_URL": "${FOUNDRY_BASE_URL}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "${FOUNDRY_SONNET}",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "${FOUNDRY_HAIKU}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "${FOUNDRY_OPUS}"
  }
}
EOF
    chmod 600 "$sidecar" 2>/dev/null || true
    warn "jq not found — wrote Foundry keys to ${sidecar}."
    warn "Install jq ('brew install jq') and re-run to merge into ${SETTINGS_FILE}."
    record "settings.json : NOT merged — sidecar written (install jq, re-run)"
    return 0
  fi

  # --- Decide the BASE document. ---------------------------------------------
  local base
  if [[ ! -e "$SETTINGS_FILE" ]]; then
    info "${SETTINGS_FILE} does not exist; creating it from the Foundry patch."
    base='{}'
  elif [[ ! -s "$SETTINGS_FILE" ]]; then
    info "${SETTINGS_FILE} is empty; treating base as {}."
    base='{}'
  elif ! jq empty "$SETTINGS_FILE" >/dev/null 2>&1; then
    local ibak="${SETTINGS_FILE}.invalid.$(date +%Y%m%d-%H%M%S).bak"
    cp -p "$SETTINGS_FILE" "$ibak"
    error "${SETTINGS_FILE} exists but is NOT valid JSON. Backed up to ${ibak}."
    warn  "Refusing to merge. Fix or remove the file, then re-run."
    record "settings.json : ERROR — invalid JSON, backed up, not merged"
    return 0
  else
    base="$(cat "$SETTINGS_FILE")"
  fi

  # --- Idempotency: skip if the merged result already matches. ---------------
  if [[ "$base" != '{}' ]] && \
     diff -q <(printf '%s' "$base" | jq -S .) \
             <(jq -n --argjson b "$base" --argjson p "$patch" '$b * $p' | jq -S .) \
             >/dev/null 2>&1; then
    success "settings.json already contains the Foundry config — no change needed."
    record "settings.json : already up to date"
    return 0
  fi

  # --- Back up an existing readable file before touching it. -----------------
  if [[ -e "$SETTINGS_FILE" && -s "$SETTINGS_FILE" ]]; then
    local backup="${SETTINGS_FILE}.$(date +%Y%m%d-%H%M%S).bak"
    cp -p "$SETTINGS_FILE" "$backup"
    info "Backup written to ${backup}."
  fi

  # --- Deep-merge: base * patch (patch wins; nested env merged key-by-key). ---
  local tmp
  tmp="$(mktemp "${SETTINGS_FILE}.XXXXXX")"
  if ! jq -n --argjson base "$base" --argjson patch "$patch" \
        '$base * $patch' > "$tmp"; then
    rm -f "$tmp"
    error "jq merge failed. Original left intact."
    record "settings.json : ERROR — merge failed, original intact"
    return 0
  fi

  # --- Validate the result parses before replacing the original. -------------
  if ! jq empty "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    error "Merged result is not valid JSON. Original left intact."
    record "settings.json : ERROR — bad merge result, original intact"
    return 0
  fi

  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$SETTINGS_FILE"          # atomic rename within the same dir
  success "Merged Foundry keys into ${SETTINGS_FILE} (plugins/marketplaces preserved)."
  record "settings.json : merged Foundry config"
}

# ----------------------------------------------------------------------------
# Claude Code (native, self-contained binary — Node.js NOT required).
# Installs via the official installer, then puts ~/.local/bin on PATH.
# claude.ai is still needed to DOWNLOAD the installer.
# ----------------------------------------------------------------------------
ensure_claude_code() {
  step "Claude Code (native install)"

  local claude_bin="${HOME}/.local/bin/claude"

  if command -v claude >/dev/null 2>&1 || [[ -x "$claude_bin" ]]; then
    success "Claude Code already installed (binary present)."
    record "Claude Code   : already installed"
  else
    info "Installing Claude Code via the official native installer…"
    # -f fail on HTTP errors, -s silent, -S show errors, -L follow redirects.
    # Never -k: we do not disable TLS verification.
    if curl -fsSL https://claude.ai/install.sh | bash; then
      success "Claude Code installer completed."
      record "Claude Code   : installed (native)"
    else
      error "The Claude Code installer failed."
      warn  "If you saw a 403 / HTML / 'syntax error near unexpected token' or a TLS error,"
      warn  "that is a corporate proxy/cert/region block — see the network notes above."
      record "Claude Code   : INSTALL FAILED — see network notes"
    fi
  fi

  # The installer does NOT reliably edit your shell profile — add ~/.local/bin
  # to PATH ourselves (grep-guarded) and export for the current session.
  ensure_line 'export PATH="$HOME/.local/bin:$PATH"' "${HOME}/.zprofile"
  case ":${PATH}:" in
    *":${HOME}/.local/bin:"*) : ;;                      # already present
    *) export PATH="${HOME}/.local/bin:${PATH}" ;;
  esac
  success "~/.local/bin is on PATH for this session."
}

# ----------------------------------------------------------------------------
# Verification: claude --version, a Foundry-auth smoke test (token helper emits
# a non-empty token), and claude doctor. Never prints the token value.
# ----------------------------------------------------------------------------
verify_install() {
  step "Verification"

  local claude_bin="${HOME}/.local/bin/claude"
  local claude_cmd=""
  if command -v claude >/dev/null 2>&1; then
    claude_cmd="claude"
  elif [[ -x "$claude_bin" ]]; then
    claude_cmd="$claude_bin"
  fi

  if [[ -z "$claude_cmd" ]]; then
    error "'claude' not found on PATH and not at ${claude_bin}."
    warn  "If the install step failed (network/cert), fix that and re-run this script."
    record "Verify        : FAILED — claude binary not found"
  else
    if "$claude_cmd" --version >/dev/null 2>&1; then
      success "claude --version: $("$claude_cmd" --version 2>/dev/null | head -1)"
      CLAUDE_OK="yes"
      record "Verify        : claude --version OK"
    else
      warn "'claude --version' did not run cleanly. Open a NEW terminal and try again."
      record "Verify        : WARNING — 'claude --version' failed (likely PATH; new terminal needed)"
    fi
  fi

  # Foundry-auth smoke test — run the token helper; confirm a non-empty token.
  info "Foundry auth smoke test (token helper) — the token value is never printed…"
  if [[ "$AZ_LOGGED_IN" == "yes" ]]; then
    if [[ -n "$("$TOKEN_HELPER" 2>/dev/null | head -c 16)" ]]; then
      success "Foundry token helper emitted a non-empty Azure token."
      TOKEN_OK="yes"
    else
      warn "Token helper produced no token. Check VPN, 'az login', and your RBAC role"
      warn "(Cognitive Services User / Foundry User on the resource)."
    fi
  else
    warn "Skipping token smoke test — 'az' is not logged in. Run 'az login --use-device-code'."
  fi

  # claude doctor is a full install/config/auth diagnostic (non-fatal).
  if [[ -n "$claude_cmd" ]]; then
    info "Running 'claude doctor' (full diagnostic — non-fatal)…"
    if "$claude_cmd" doctor 2>/dev/null; then
      success "claude doctor completed."
    else
      warn "'claude doctor' reported issues or is unavailable. Review its output above."
    fi

    # Surface conflicting installs (native vs legacy vs npm-global).
    if command -v which >/dev/null 2>&1; then
      local found
      found="$(which -a claude 2>/dev/null | tr '\n' ' ' || true)"
      if [[ -n "$found" ]] && [[ "$(which -a claude 2>/dev/null | wc -l | tr -d ' ')" -gt 1 ]]; then
        warn "Multiple 'claude' binaries on PATH: ${found}"
        warn "Keep ONLY the native one (~/.local/bin/claude); remove legacy/npm copies."
      fi
    fi
  fi
}

# ----------------------------------------------------------------------------
# Final summary + the exact manual steps the user must do themselves (Foundry).
# ----------------------------------------------------------------------------
print_summary() {
  printf '\n%s======================== SUMMARY ========================%s\n' "${C_BLU}" "${C_RESET}"
  local line
  for line in "${SUMMARY_LINES[@]}"; do
    printf '  %s\n' "$line"
  done
  printf '  %-13s : %s\n' "Warnings" "${WARN_COUNT}"
  printf '%s========================================================%s\n' "${C_BLU}" "${C_RESET}"

  printf '\n%s>>> NEXT STEPS — YOU MUST DO THESE MANUALLY <<<%s\n' "${C_GRN}" "${C_RESET}"
  cat <<'EOF'

  This machine is configured for AZURE AI FOUNDRY. There is NO claude.ai
  browser login — Claude Code authenticates with an Azure access token that
  the apiKeyHelper (~/.claude/get-claude-token.sh) mints from your 'az' session.

  1. OPEN A NEW TERMINAL  (so the updated PATH from ~/.zprofile takes effect),
     or run:  source ~/.zprofile

  2. CONNECT THE CORPORATE VPN.
     The Foundry endpoint is an internal host and is unreachable off-VPN.

  3. LOG IN TO AZURE (device-code recommended on corporate networks):
          az login --use-device-code
     Verify:  az account show
     If 'az login' fails on certificates, see the REQUESTS_CA_BUNDLE combined-CA
     note printed in the Azure CLI step above (it REPLACES the trust store).

  4. RUN CLAUDE:
          claude
     It should start with NO browser OAuth. Confirm routing inside Claude Code:
          /status
     It should report  API provider: Microsoft Foundry  and your resource.

  5. GOTCHA — A STALE ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN OVERRIDES FOUNDRY:
     If either is exported in your shell (or left in ~/.zshrc by a prior setup),
     it can mask Foundry mode and cause confusing 401s. Fix:
          unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
          # and delete those export lines from ~/.zshrc / ~/.bashrc / ~/.profile
     (These are DISTINCT from ANTHROPIC_FOUNDRY_API_KEY, which does not conflict.)
     Keep CLAUDE_CODE_USE_FOUNDRY=1 set (it is, in ~/.claude/settings.json).

  6. TOKEN TTL — Azure access tokens last ~60-90 min and auto-refresh from your
     cached login. If Claude later errors with 401/403, your session expired or
     the refresh token was revoked:
          az login --use-device-code      # then re-run claude
     A 403 with a valid token usually means a missing RBAC role
     (Cognitive Services User / Foundry User) on the Foundry resource.

  7. IF YOU HIT TLS / PROXY ERRORS (see the network notes earlier):
     - Trust the corporate CA at runtime for Claude Code:
          export NODE_EXTRA_CA_CERTS=/path/to/corp-root-ca.pem
       or rely on the OS Keychain (default):
          export CLAUDE_CODE_CERT_STORE=bundled,system
     - For 'az', build a COMBINED bundle and set BOTH:
          export REQUESTS_CA_BUNDLE=/path/to/combined-ca.pem
          export SSL_CERT_FILE=/path/to/combined-ca.pem

EOF

  if [[ "$CLAUDE_OK" == "yes" && "$TOKEN_OK" == "yes" ]]; then
    success "Bootstrap complete. Open a new terminal, ensure VPN + 'az login', then run 'claude'."
  elif [[ "$CLAUDE_OK" == "yes" ]]; then
    warn "Claude Code is installed but the Azure token check did not pass."
    warn "Connect VPN, run 'az login --use-device-code', then run 'claude'."
  else
    warn "Bootstrap finished with issues. Review the warnings above, then re-run safely."
  fi
}

# ----------------------------------------------------------------------------
# main — defined as a function and invoked ONLY on the final line, so a dropped
# connection during 'curl | bash' can never execute a partially-downloaded body.
# ----------------------------------------------------------------------------
main() {
  banner
  preflight_root          # abort if root; set $SUDO
  detect_arch             # set BREW_PREFIX / ARCH_LABEL
  preflight               # macOS + curl + arch + macOS version
  check_corp_network      # TLS-inspection / connectivity to Foundry + Azure login
  ensure_clt              # Xcode Command Line Tools (git + build tooling)
  ensure_homebrew         # install if missing; wire shellenv into ~/.zprofile
  ensure_git              # verify / install git
  ensure_jq               # needed for the safe settings.json merge
  ensure_azure_cli        # install az; check login (never auto-login)
  ensure_token_helper     # write ~/.claude/get-claude-token.sh (chmod 700)
  ensure_settings         # deep-merge Foundry config into ~/.claude/settings.json
  ensure_claude_code      # native install; ~/.local/bin on PATH
  verify_install          # claude --version + token smoke test + claude doctor
  print_summary           # what happened + Foundry next steps
}

main "$@"
