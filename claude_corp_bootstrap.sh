#!/usr/bin/env bash
#
# ============================================================================
# claude_corp_bootstrap.sh — Claude Code for Sleep Number Macs
#
#   Installs Claude Code NATIVELY on macOS and connects it to the Sleep Number
#   Azure AI Foundry gateway. No Docker, no Rancher Desktop, no containers,
#   no VM — nothing in this script installs or touches a container runtime.
#
#   Run it from Terminal (the file usually lands in Downloads):
#     bash ~/Downloads/claude_corp_bootstrap.sh
#
#   What it does, in order. Every step skips itself when already done, so it
#   is safe to run again at any time:
#     1. Checks the Mac: macOS 13+, not root, Apple Silicon/Intel, disk space
#     2. Checks the network: internet, Zscaler certificate trust, the AI
#        gateway (needs the Sleep Number VPN)
#     3. Asks for the Mac password ONCE, only if something needs installing:
#        Apple Command Line Tools, Homebrew, jq, Azure CLI
#     4. Installs Claude Code (native: ~/.local/bin/claude)
#     5. Writes ~/.claude/get-claude-token.sh, ~/.local/bin/claude-login and
#        ~/.claude/settings.json, skips Claude Code's first-run screens, and
#        installs the /make-it skills (pinned; building apps with them needs
#        Docker, which this installer deliberately does not install)
#     6. Signs in to Microsoft/Azure (browser; falls back to a device code)
#     7. Proves it works: a real 1-token request to every model, then a reply
#        from 'claude -p'
#
#   Every run is logged to ~/Library/Logs/claude_corp_bootstrap/
#
#   Configurable via env vars (defaults are Sleep Number's working values):
#     FOUNDRY_BASE_URL  FOUNDRY_SONNET  FOUNDRY_HAIKU  FOUNDRY_OPUS
#     FOUNDRY_TOKEN_RESOURCE  FOUNDRY_TENANT_ID  FOUNDRY_DEFAULT_MODEL
#     FOUNDRY_TOKEN_TTL_MS
#     FORCE_TOKEN_HELPER=1   replace a hand-written ~/.claude/get-claude-token.sh
#                            (default: a helper this script did not write is kept)
#     SKIP_GATEWAY_TEST=1    skip the live requests at the end
#     SKIP_CORP_CHECKS=1     TESTING ONLY (e.g. a VM off the corporate network):
#                            skip the VPN check, Microsoft sign-in, token and
#                            gateway checks; everything else runs as normal
#     MAKEIT_REF=<commit|branch>  install that /make-it version instead of the
#                            pinned, tested one (also forces a reinstall)
#
#   Exit codes: 0 installed and proven working
#               1 unexpected error (line number printed)
#               2 stopped on purpose, with the reason and the fix printed
#               3 installed, but the final checks did not pass (reason printed)
# ============================================================================

# --- Must run under bash, not sh or zsh. Plain POSIX until bash is confirmed.
if [ -z "${BASH_VERSION:-}" ]; then
  if [ -f "$0" ]; then exec /bin/bash "$0" "$@"; fi
  echo "Please run this installer with bash:  bash claude_corp_bootstrap.sh" >&2
  exit 1
fi
# 'sh file' on macOS is bash in POSIX mode, which disables features used below.
set +o posix 2>/dev/null || true
# Apple Silicon Mac with Terminal running under Rosetta: re-run natively, or
# Homebrew would be installed for Intel in the wrong place.
if [ "$(/usr/sbin/sysctl -n sysctl.proc_translated 2>/dev/null)" = "1" ] && [ -f "$0" ]; then
  exec /usr/bin/arch -arm64 /bin/bash "$0" "$@"
fi

# NOTE ON 'set -E': errtrace is REQUIRED. Without it an ERR trap is not
# inherited by shell functions, and every step below is a function.
set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true   # macOS /bin/bash 3.2 lacks this; guard it
IFS=$'\n\t'                                     # safer word-splitting: drop the space
umask 022

# ----------------------------------------------------------------------------
# Foundry configuration — override via env; defaults are Sleep Number's
# working values (identical to a known-good ~/.claude/settings.json).
# ----------------------------------------------------------------------------
# The Sleep Number Anthropic gateway. It accepts Anthropic model ids directly
# (no 'cogdep-…' deployment names) and authenticates the bearer token that the
# apiKeyHelper supplies.
FOUNDRY_BASE_URL="${FOUNDRY_BASE_URL:-https://snapi-scus.azure.sleepnumber.com/anthropic}"
FOUNDRY_SONNET="${FOUNDRY_SONNET:-claude-sonnet-5}"
FOUNDRY_HAIKU="${FOUNDRY_HAIKU:-claude-haiku-4-5}"
FOUNDRY_OPUS="${FOUNDRY_OPUS:-claude-opus-5-5}"
FOUNDRY_TOKEN_RESOURCE="${FOUNDRY_TOKEN_RESOURCE:-https://cognitiveservices.azure.com}"
# Sleep Number Corporation Entra tenant. Signing in against it explicitly, with
# the Cognitive Services scope, satisfies Conditional Access (MFA) for the token
# audience up front; a bare 'az login' can leave every later token request
# failing with AADSTS50076.
FOUNDRY_TENANT_ID="${FOUNDRY_TENANT_ID:-ed8aabd5-14de-4982-9fb6-d6528851af5e}"
FOUNDRY_DEFAULT_MODEL="${FOUNDRY_DEFAULT_MODEL:-opus}"
# How often Claude Code re-runs the apiKeyHelper (CLAUDE_CODE_API_KEY_HELPER_TTL_MS).
# This is NOT the token lifetime: Entra access tokens live ~60 min. Setting this
# above the lifetime makes Claude Code keep serving an expired bearer (401s);
# 30 min always refreshes before expiry while keeping 'az' process starts rare.
FOUNDRY_TOKEN_TTL_MS="${FOUNDRY_TOKEN_TTL_MS:-1800000}"
if ! [[ "$FOUNDRY_TOKEN_TTL_MS" =~ ^[0-9]+$ ]]; then
  printf '[FAIL]  FOUNDRY_TOKEN_TTL_MS must be a whole number of milliseconds (got: %s)\n' \
    "$FOUNDRY_TOKEN_TTL_MS" >&2
  exit 1
fi

CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
TOKEN_HELPER="${CLAUDE_DIR}/get-claude-token.sh"
TOKEN_HELPER_TILDE="~/.claude/get-claude-token.sh"   # as stored in settings.json
LOCAL_BIN="${HOME}/.local/bin"
CLAUDE_BIN="${LOCAL_BIN}/claude"
LOGIN_CMD="${LOCAL_BIN}/claude-login"
CLAUDE_STATE="${HOME}/.claude.json"                  # Claude Code's own state file
# Where Claude Code starts. NOT the home folder: started there, Claude Code
# scans it and macOS asks Terminal for Downloads, Documents, Desktop and the
# Photo Library, one pop-up after another (seen on a fresh macOS 26 Mac).
WORKSPACE="${HOME}/Claude"
AZ_CA_BUNDLE="${CLAUDE_DIR}/azure-ca-bundle.pem"     # only created if az hits TLS inspection
GENERATED_MARKER="Auto-generated by claude_corp_bootstrap.sh"
SUPPORT_CONTACT="${SUPPORT_CONTACT:-the AI CoE team}"

LOG_DIR="${HOME}/Library/Logs/claude_corp_bootstrap"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
LOCK_DIR="${TMPDIR:-/tmp}/claude_corp_bootstrap.lock"

# Derive the Foundry hostname from the base URL for connectivity checks.
FOUNDRY_HOST="${FOUNDRY_BASE_URL#*://}"; FOUNDRY_HOST="${FOUNDRY_HOST%%/*}"; FOUNDRY_HOST="${FOUNDRY_HOST%%:*}"

# The one manual sign-in command (shown only if the automatic one can't run).
AZ_LOGIN_CMD="az login --tenant ${FOUNDRY_TENANT_ID} --scope ${FOUNDRY_TOKEN_RESOURCE}/.default --allow-no-subscriptions"

# Keys removed from an existing settings.json because they defeat Foundry mode:
#   - a first-party key/token or another provider flag reroutes or masks Foundry
#   - ANTHROPIC_FOUNDRY_API_KEY / _RESOURCE compete with the gateway + helper
#   - top-level 'apiKeyHelperTtlMs' was written by earlier versions of this
#     script; Claude Code has no such setting, so it never took effect.
STALE_ENV_KEYS_JSON='["ANTHROPIC_API_KEY","ANTHROPIC_AUTH_TOKEN","ANTHROPIC_FOUNDRY_API_KEY","ANTHROPIC_FOUNDRY_RESOURCE","CLAUDE_CODE_USE_BEDROCK","CLAUDE_CODE_USE_VERTEX"]'
# shellcheck disable=SC2016  # $stale is a jq variable, not a shell one
JQ_CLEAN_DEF='def clean:
  del(.apiKeyHelperTtlMs)
  | if (.env | type) == "object"
    then .env |= with_entries(select(.key as $k | any($stale[]; . == $k) | not))
    else . end;'

# ----------------------------------------------------------------------------
# Output. Colour is decided here, before output is copied into the log file.
# ----------------------------------------------------------------------------
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]] && command -v tput >/dev/null 2>&1 \
   && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[0;31m'; C_YEL=$'\033[1;33m'
  C_GRN=$'\033[0;32m'; C_BLU=$'\033[0;34m'; C_BOLD=$'\033[1m'
else
  C_RESET=''; C_RED=''; C_YEL=''; C_GRN=''; C_BLU=''; C_BOLD=''
fi

WARN_COUNT=0
# 'local IFS=" "': "$*" joins arguments with IFS's first character, which the
# script-wide IFS (newline) would turn into a line break.
step()    { local IFS=' '; printf '\n%s[STEP]%s %s\n'    "${C_BLU}" "${C_RESET}" "$*"; }
info()    { local IFS=' '; printf '%s[INFO]%s  %s\n'      "${C_BLU}" "${C_RESET}" "$*"; }
success() { local IFS=' '; printf '%s[ OK ]%s  %s\n'      "${C_GRN}" "${C_RESET}" "$*"; }
warn()    { local IFS=' '; printf '%s[WARN]%s  %s\n'      "${C_YEL}" "${C_RESET}" "$*" >&2; WARN_COUNT=$((WARN_COUNT+1)); }
error()   { local IFS=' '; printf '%s[FAIL]%s  %s\n'      "${C_RED}" "${C_RESET}" "$*" >&2; }

# Summary trackers.
SUMMARY_LINES=()
PROBLEMS=()
record()  { SUMMARY_LINES+=("$*"); }
problem() { PROBLEMS+=("$*"); }

ARCH_LABEL=""; BREW_PREFIX=""; MACOS_VER=""
HAVE_TTY="no"
SUDO_READY="no"; SUDO_KEEPALIVE_PID=""; CAFFEINATE_PID=""
NEED_ADMIN="no"; ADMIN_REASONS=""; OWNER_FIX=()
NEED_CLT="no"; NEED_BREW="no"
GATEWAY_REACHABLE="unknown"
VPN_PROBLEM="Connect to the Sleep Number VPN, then run this installer again to finish the final check."
CLAUDE_OK="no"; AZ_LOGGED_IN="no"; TOKEN_OK="no"; GATEWAY_OK="untested"; ENV_CONFLICTS="no"

# ----------------------------------------------------------------------------
# Stop on purpose: say what is wrong and exactly what to do. Exit 2.
# ----------------------------------------------------------------------------
fatal() {   # $1 = what went wrong; remaining args = what to do, one line each
  local what="$1" l; shift
  {
    printf '\n%s============================================================%s\n' "${C_RED}" "${C_RESET}"
    printf '%s  INSTALL STOPPED%s\n\n' "${C_RED}${C_BOLD}" "${C_RESET}"
    printf '  %s\n' "$what"
    if [[ $# -gt 0 ]]; then
      printf '\n  What to do:\n'
      for l in "$@"; do printf '    %s\n' "$l"; done
    fi
    printf '\n  Nothing is broken. Fix the item above, then run the same command again.\n'
    printf '  If you need help, send this log file to %s:\n' "$SUPPORT_CONTACT"
    printf '    %s\n' "$LOG_FILE"
    printf '%s============================================================%s\n' "${C_RED}" "${C_RESET}"
  } >&2
  exit 2
}

# Unexpected failure: print the failing line and command. Requires 'set -E'.
# Installed here for the top level and again inside main(), which runs in the
# subshell of the 'main | tee' pipeline at the bottom of the file.
#
# 'set -E' also copies the trap into every $(…) and ( … ). There it must stay
# silent: an expected failure inside a substitution (curl with the VPN off,
# xcode-select on a Mac without the tools) is handled by the caller. A real
# failure still surfaces once, at the caller's line, at main's own level.
ERR_TRAP_LEVEL=0
install_err_trap() {
  trap 'rc=$?; if [ "${BASH_SUBSHELL:-0}" -gt "${ERR_TRAP_LEVEL:-0}" ]; then exit "${rc}"; fi; \
        printf "\n%s[FAIL]%s Unexpected error on line %s: '\''%s'\'' (exit %s)\n" \
        "${C_RED}" "${C_RESET}" "${LINENO}" "${BASH_COMMAND}" "${rc}" >&2; \
        printf "       Running this installer again is safe. Log: %s\n" "${LOG_FILE}" >&2; \
        exit "${rc}"' ERR
}
install_err_trap

LOCK_OWNED="no"
cleanup() {
  [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
  [[ -n "$CAFFEINATE_PID" ]] && kill "$CAFFEINATE_PID" 2>/dev/null
  # Drop the cached admin password so it does not outlive the install.
  [[ "$SUDO_READY" == "yes" ]] && sudo -k 2>/dev/null
  [[ "$LOCK_OWNED" == "yes" ]] && rm -rf "$LOCK_DIR" 2>/dev/null
  return 0
}

# One installer at a time. The lock holds the PID of the installer that owns
# it; a lock whose PID is gone was left by a run that was killed.
take_lock() {
  local holder=""
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    holder="$(cat "${LOCK_DIR}/pid" 2>/dev/null || true)"
    if [[ "$holder" =~ ^[0-9]+$ ]] && [[ "$holder" != "$$" ]] && kill -0 "$holder" 2>/dev/null; then
      fatal "The installer is already running in another Terminal window." \
            "Let that one finish (or close it), then run this again if needed."
    fi
    rm -rf "$LOCK_DIR" 2>/dev/null
    mkdir "$LOCK_DIR" 2>/dev/null || fatal "Could not create ${LOCK_DIR}." "Contact ${SUPPORT_CONTACT}."
  fi
  printf '%s\n' "$$" > "${LOCK_DIR}/pid"
  LOCK_OWNED="yes"
}

# Return to continue; 's' (or no terminal) to decline. Reads the keyboard even
# when stdin is something else (e.g. 'curl | bash').
ask_enter() {
  [[ "$HAVE_TTY" == "yes" ]] || return 1
  local reply=""
  printf '%s' "$1"
  IFS= read -r reply </dev/tty || return 1
  case "$reply" in s|S|skip|SKIP|Skip) return 1 ;; esac
  return 0
}

# Append $1 to file $2 only if not already present (literal match).
# $3 (optional): what to show instead of the line itself.
ensure_line() {
  local line="$1" file="$2" label="${3:-$1}"
  if [[ -e "$file" && ! -w "$file" ]]; then
    warn "Cannot write $(basename "$file") (owned by another user) — skipped."
    problem "Fix ownership of ${file} (run the installer again; it repairs this with your password)."
    return 0
  fi
  touch "$file"
  if grep -qF -- "$line" "$file"; then
    info "Already in $(basename "$file")."
  else
    printf '\n%s\n' "$line" >> "$file"
    success "Added to $(basename "$file"): ${label}"
  fi
}

# Run a command with a hard time limit (seconds). perl is the only stock macOS
# tool that can do this; without it the command simply runs without a limit.
with_timeout() {
  local secs="$1"; shift
  if command -v perl >/dev/null 2>&1; then
    perl -e 'alarm shift; exec @ARGV' "$secs" "$@"
  else
    "$@"
  fi
}

# ----------------------------------------------------------------------------
# 1. The Mac
# ----------------------------------------------------------------------------
banner() {
  printf '%s' "${C_BLU}"
  cat <<EOF
============================================================
  Claude Code installer for Sleep Number Macs
  Connects to: Azure AI Foundry (${FOUNDRY_HOST})
============================================================
EOF
  printf '%s' "${C_RESET}"
  info "Takes about 5-15 minutes. Safe to run again at any time."
  info "You may be asked for your Mac password once, and to sign in to Microsoft"
  info "in your browser. Keep this window open until you see ALL SET."
  info "Log file: ${LOG_FILE}"
}

check_mac() {
  step "Checking this Mac"

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    fatal "This installer was started as root (with sudo)." \
          "Run it again WITHOUT 'sudo' in front:  bash ~/Downloads/claude_corp_bootstrap.sh"
  fi
  [[ "$(uname)" == "Darwin" ]] || fatal "This installer is for macOS only (found: $(uname))."
  command -v curl >/dev/null 2>&1 || fatal "The 'curl' tool is missing from this Mac." "Contact ${SUPPORT_CONTACT}."

  MACOS_VER="$(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
  local major="${MACOS_VER%%.*}"
  if [[ "$major" =~ ^[0-9]+$ ]] && (( major < 13 )); then
    fatal "Claude Code needs macOS 13 (Ventura) or newer. This Mac has macOS ${MACOS_VER}." \
          "Update macOS (Apple menu > System Settings > General > Software Update), then run this again."
  fi
  success "macOS ${MACOS_VER}"
  record "macOS         : ${MACOS_VER}"

  if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" == "1" ]]; then
    BREW_PREFIX="/opt/homebrew"; ARCH_LABEL="Apple Silicon"
    if [[ "$(/usr/sbin/sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" == "1" ]]; then
      fatal "Terminal is running in Intel (Rosetta) mode on this Apple Silicon Mac." \
            "Quit Terminal. In Finder open Applications > Utilities, select Terminal," \
            "choose File > Get Info, untick 'Open using Rosetta', reopen Terminal and run this again."
    fi
  else
    BREW_PREFIX="/usr/local"; ARCH_LABEL="Intel"
  fi
  success "Processor: ${ARCH_LABEL}"
  record "Processor     : ${ARCH_LABEL}"
}

# ----------------------------------------------------------------------------
# 2. The network. Probes are cheap and tell the user what to fix BEFORE any
# password prompt or download.
# ----------------------------------------------------------------------------
probe() {   # $1 = url ; sets PROBE_RC / PROBE_OUT (any HTTP status counts as reachable)
  PROBE_OUT="$(curl -sS -v -o /dev/null --max-time 20 "$1" 2>&1)" && PROBE_RC=0 || PROBE_RC=$?
}

is_tls_failure() {
  [[ "$PROBE_RC" -eq 60 ]] || printf '%s\n' "$PROBE_OUT" \
    | grep -qiE 'unable to get local issuer certificate|self.signed|SSL certificate problem'
}

print_it_notes() {
  cat <<EOF

  ---------------------------------------------------------------------------
  FOR IT: hosts this install needs (port 443)
    ${FOUNDRY_HOST}     Sleep Number AI gateway (internal - VPN)
    login.microsoftonline.com, login.microsoft.com     Microsoft sign-in
    claude.ai, downloads.claude.ai, storage.googleapis.com     Claude Code download/updates
    raw.githubusercontent.com, github.com, ghcr.io, formulae.brew.sh   Homebrew
  macOS tools trust the corporate root certificate from the System keychain
  (installed by MDM). Do not disable TLS verification.
  ---------------------------------------------------------------------------

EOF
}

check_network() {
  step "Checking the network"

  probe "https://claude.ai/"
  if [[ "$PROBE_RC" -ne 0 ]]; then
    if is_tls_failure; then
      print_it_notes
      fatal "Downloads are blocked: this Mac does not trust the security certificate on the network." \
            "Pause Zscaler for 15 minutes (Zscaler menu-bar icon; you have the 'Zscaler DevOps' access)," \
            "then run this installer again right away."
    fi
    fatal "This Mac cannot reach the internet (could not connect to claude.ai, error ${PROBE_RC})." \
          "Check Wi-Fi, then run this again."
  fi
  success "Internet and certificate trust OK."

  probe "https://login.microsoftonline.com/"
  if [[ "$PROBE_RC" -ne 0 ]]; then
    is_tls_failure && print_it_notes
    fatal "Cannot reach Microsoft sign-in (login.microsoftonline.com, error ${PROBE_RC})." \
          "Check the network (or pause Zscaler for 15 minutes), then run this again."
  fi
  success "Microsoft sign-in reachable."

  if [[ "${SKIP_CORP_CHECKS:-0}" == "1" ]]; then
    info "Test mode (SKIP_CORP_CHECKS=1): not checking the VPN / AI gateway."
    GATEWAY_REACHABLE="skipped"
    record "Test mode     : VPN, sign-in, token and gateway checks SKIPPED"
    return 0
  fi

  local attempt
  for ((attempt = 1; attempt <= 4; attempt++)); do
    probe "https://${FOUNDRY_HOST}/"
    if [[ "$PROBE_RC" -eq 0 ]]; then
      GATEWAY_REACHABLE="yes"
      success "Sleep Number AI gateway reachable (${FOUNDRY_HOST})."
      record "Network       : OK (internet, Microsoft sign-in, AI gateway)"
      return 0
    fi
    if is_tls_failure; then
      print_it_notes
      warn "The AI gateway's certificate is not trusted on this Mac (error ${PROBE_RC})."
      problem "This Mac does not trust the AI gateway's certificate. Send the log to ${SUPPORT_CONTACT} (for IT)."
      GATEWAY_REACHABLE="tls"
      record "Network       : AI gateway certificate NOT trusted"
      return 0
    fi
    warn "Cannot reach the Sleep Number AI gateway (${FOUNDRY_HOST}) — the VPN is probably not connected."
    if (( attempt == 4 )) || ! ask_enter "  Connect to the Sleep Number VPN, then press Return to check again (or type S and Return to continue without it): "; then
      break
    fi
  done
  # The problem is recorded at the end only if the gateway is still
  # unreachable then — the VPN may be connected while the install runs.
  GATEWAY_REACHABLE="no"
  info "Continuing the install. The final check needs the VPN."
  record "Network       : AI gateway not reachable at start (VPN)"
}

# ----------------------------------------------------------------------------
# 3. What needs installing, and therefore whether the Mac password is needed.
# ----------------------------------------------------------------------------
clt_present() {
  local p=""
  p="$(xcode-select -p 2>/dev/null || true)"
  [[ -n "$p" && -x "${p}/usr/bin/git" ]]
}

find_brew() {
  if command -v brew >/dev/null 2>&1; then command -v brew; return 0; fi
  [[ -x "${BREW_PREFIX}/bin/brew" ]] && { printf '%s\n' "${BREW_PREFIX}/bin/brew"; return 0; }
  return 1
}

add_admin_reason() { ADMIN_REASONS="${ADMIN_REASONS:+${ADMIN_REASONS}, }$1"; NEED_ADMIN="yes"; }

assess() {
  step "Checking what needs installing"

  clt_present && success "Apple Command Line Tools: present" \
              || { NEED_CLT="yes"; info "Apple Command Line Tools: will install"; add_admin_reason "Apple Command Line Tools"; }

  local brew_bin=""
  brew_bin="$(find_brew || true)"
  # Homebrew may be installed but not on this Terminal's PATH yet; load it so
  # tools it already installed (az, jq) are not mistaken for missing.
  [[ -n "$brew_bin" ]] && eval "$("$brew_bin" shellenv 2>/dev/null)"
  local az_ok="no" jq_ok="no"
  az version >/dev/null 2>&1 && az_ok="yes"
  command -v jq >/dev/null 2>&1 && jq_ok="yes"
  if [[ -z "$brew_bin" ]] && [[ "$az_ok" == "no" || "$jq_ok" == "no" ]]; then
    NEED_BREW="yes"; info "Homebrew: will install"; add_admin_reason "Homebrew"
  elif [[ -n "$brew_bin" ]]; then
    success "Homebrew: present"
  fi
  [[ "$az_ok" == "yes" ]] && success "Azure CLI: present" || info "Azure CLI: will install"
  [[ "$jq_ok" == "yes" ]] && success "jq: present" || info "jq: will install"
  [[ -x "$CLAUDE_BIN" ]] && success "Claude Code: present" || info "Claude Code: will install"

  # Files in the home folder that another account (usually root, after an
  # earlier 'sudo' install) owns. Installing into them would fail.
  local p
  # Checked: the folders themselves AND anything inside them (a single
  # root-owned file in ~/.claude also breaks Claude Code, which writes there).
  local uid stray
  uid="$(id -u)"
  for p in "$CLAUDE_DIR" "${HOME}/.local" "$CLAUDE_STATE" "${HOME}/.azure" \
           "${HOME}/.zshrc" "${HOME}/.zprofile" "${HOME}/.bash_profile"; do
    [[ -e "$p" ]] || continue
    stray=""
    if [[ ! -O "$p" ]]; then
      stray="$p"
    elif [[ -d "$p" ]]; then
      stray="$(find "$p" -maxdepth 4 ! -user "$uid" -print -quit 2>/dev/null || true)"
    fi
    if [[ -n "$stray" ]]; then
      OWNER_FIX+=("$p")
      info "${stray} is owned by another account: will repair ${p}"
    fi
  done
  [[ ${#OWNER_FIX[@]} -gt 0 ]] && add_admin_reason "repair file ownership in your home folder"

  # Room for the Command Line Tools (~3 GB) plus Homebrew and the Azure CLI.
  local free_kb need_kb=1572864
  [[ "$NEED_CLT" == "yes" || "$NEED_BREW" == "yes" ]] && need_kb=5242880
  free_kb="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')"
  if [[ "$free_kb" =~ ^[0-9]+$ ]] && (( free_kb < need_kb )); then
    fatal "Not enough free disk space: $((free_kb / 1048576)) GB free, $((need_kb / 1048576)) GB needed." \
          "Free up space (empty the Trash, remove large downloads), then run this again."
  fi
}

# ----------------------------------------------------------------------------
# Admin rights + the password, asked once. Everything that needs them runs
# right after this, so a temporary elevation that expires mid-way is harmless.
# ----------------------------------------------------------------------------
is_admin() { /usr/sbin/dseditgroup -o checkmember -m "$USER" admin >/dev/null 2>&1; }

ensure_admin() {
  if [[ "$NEED_ADMIN" != "yes" ]]; then
    record "Admin rights  : not needed"
    return 0
  fi
  step "Administrator rights (needed for: ${ADMIN_REASONS})"

  local tries=0
  until is_admin; do
    tries=$((tries + 1))
    warn "Your Mac account (${USER}) does not have administrator rights right now."
    info "Turn on your temporary admin access (the 'Local Admin' prerequisite), then come back here."
    if (( tries >= 4 )) || ! ask_enter "  Press Return to check again (or type S and Return to stop): "; then
      fatal "Administrator rights are needed to install: ${ADMIN_REASONS}." \
            "Turn on your temporary Local Admin access (or ask ${SUPPORT_CONTACT})," \
            "then run this installer again."
    fi
  done
  success "Your account has administrator rights."

  [[ "$HAVE_TTY" == "yes" ]] || fatal "The Mac password is needed, but this installer has no keyboard input." \
                                      "Open Terminal and run:  bash ~/Downloads/claude_corp_bootstrap.sh"
  info "Type your Mac login password and press Return. Nothing appears while you type — that is normal."
  local ok="no"
  for tries in 1 2 3; do
    if sudo -p "  Mac password for ${USER}: " -v </dev/tty; then ok="yes"; break; fi
    warn "That password was not accepted."
  done
  [[ "$ok" == "yes" ]] || fatal "The Mac password was not accepted." \
                                "Use the password you use to unlock this Mac, then run this again."
  SUDO_READY="yes"

  # Keep the password cached until the installs finish ($$ = this installer).
  # Output to /dev/null: an inherited copy of the log pipe would keep 'tee'
  # (and so the whole installer) waiting after main() has finished.
  ( while kill -0 "$$" 2>/dev/null; do sudo -n -v 2>/dev/null || exit 0; sleep 45; done ) \
    >/dev/null 2>&1 </dev/null &
  SUDO_KEEPALIVE_PID=$!; disown "$SUDO_KEEPALIVE_PID" 2>/dev/null || true   # no "Terminated" line when cleanup() kills it
  record "Admin rights  : used for ${ADMIN_REASONS}"

  if [[ ${#OWNER_FIX[@]} -gt 0 ]]; then
    local p grp
    grp="$(id -gn)"
    for p in "${OWNER_FIX[@]}"; do
      if sudo -n chown -R "${USER}:${grp}" "$p"; then
        success "Repaired ownership of ${p}"
      else
        fatal "Could not repair ownership of ${p}." "Contact ${SUPPORT_CONTACT}."
      fi
    done
  fi
}

# ----------------------------------------------------------------------------
# Apple Command Line Tools (git + build tools). Installed headlessly the same
# way Homebrew does it; the GUI installer is only the fallback.
# ----------------------------------------------------------------------------
ensure_clt() {
  [[ "$NEED_CLT" == "yes" ]] || { record "Command Line Tools: present"; return 0; }
  step "Installing Apple Command Line Tools (about 5-10 minutes)"

  local flag="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress" label=""
  sudo -n /usr/bin/touch "$flag" 2>/dev/null || touch "$flag" 2>/dev/null || true
  label="$(softwareupdate -l 2>/dev/null \
           | grep -B 1 -E 'Command Line Tools' \
           | awk -F'*' '/^ *\*/ {print $2}' \
           | sed -e 's/^ *Label: //' -e 's/^ *//' \
           | sort -V | tail -n 1 || true)"
  if [[ -n "$label" ]]; then
    info "Downloading and installing: ${label}"
    sudo -n /usr/sbin/softwareupdate -i "$label" </dev/null || warn "softwareupdate reported a problem."
    sudo -n /usr/bin/xcode-select --switch /Library/Developer/CommandLineTools 2>/dev/null || true
  fi
  sudo -n /bin/rm -f "$flag" 2>/dev/null || rm -f "$flag" 2>/dev/null || true

  if ! clt_present; then
    # Fallback: Apple's own installer window.
    xcode-select --install </dev/null >/dev/null 2>&1 || true
    info "A window titled 'Install Command Line Developer Tools' should appear."
    info "Click Install, then Agree. This installer waits and continues automatically."
    local waited=0
    until clt_present; do
      sleep 15; waited=$((waited + 15))
      (( waited % 120 == 0 )) && info "Still waiting for the Command Line Tools… (${waited}s)"
      if (( waited >= 2700 )); then
        fatal "The Apple Command Line Tools did not finish installing." \
              "Install them (they appear in System Settings > General > Software Update), then run this again."
      fi
    done
  fi
  success "Apple Command Line Tools installed."
  record "Command Line Tools: installed"
}

# ----------------------------------------------------------------------------
# Homebrew (the supported way to get the Azure CLI on macOS).
# ----------------------------------------------------------------------------
ensure_homebrew() {
  local brew_bin=""
  brew_bin="$(find_brew || true)"

  if [[ -z "$brew_bin" && "$NEED_BREW" == "yes" ]]; then
    step "Installing Homebrew"
    # Uses the password cached above (the installer runs 'sudo -n').
    if NONINTERACTIVE=1 /bin/bash -c \
         "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null; then
      success "Homebrew installed."
      info "Homebrew's 'Next steps' above are done for you on the next line — nothing to type."
      record "Homebrew      : installed"
    else
      fatal "The Homebrew installer failed (see the messages above)." \
            "If a certificate or download error is shown: pause Zscaler for 15 minutes and run this again."
    fi
    brew_bin="$(find_brew || true)"
    [[ -n "$brew_bin" ]] || fatal "Homebrew did not end up in ${BREW_PREFIX}." "Contact ${SUPPORT_CONTACT}."
  elif [[ -n "$brew_bin" ]]; then
    record "Homebrew      : present"
  else
    record "Homebrew      : not needed"
    return 0
  fi

  ensure_line "eval \"\$(${brew_bin} shellenv)\"" "${HOME}/.zprofile"
  eval "$("$brew_bin" shellenv)"
  export HOMEBREW_NO_ENV_HINTS=1
}

brew_install() {   # $1 = formula
  local prefix
  prefix="$(brew --prefix 2>/dev/null || echo "$BREW_PREFIX")"
  if [[ ! -w "${prefix}/bin" && -d "${prefix}/bin" ]]; then
    fatal "Homebrew on this Mac belongs to another user account, so '$1' cannot be installed." \
          "Ask ${SUPPORT_CONTACT} to install the Azure CLI for this account, then run this again."
  fi
  brew install "$1" </dev/null
}

ensure_jq() {
  if command -v jq >/dev/null 2>&1; then
    record "jq            : $(jq --version 2>/dev/null)"
    return 0
  fi
  step "Installing jq (used to edit settings safely)"
  if command -v brew >/dev/null 2>&1 && brew_install jq; then
    success "jq installed."
    record "jq            : installed"
  else
    warn "jq could not be installed. Settings are still written, but cannot be merged."
    record "jq            : MISSING"
  fi
}

ensure_azure_cli() {
  if az version >/dev/null 2>&1; then
    record "Azure CLI     : $(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo present)"
    return 0
  fi
  step "Installing the Azure CLI (used to sign in; a few minutes)"
  command -v brew >/dev/null 2>&1 || fatal "Homebrew is needed to install the Azure CLI but is missing." \
                                           "Run this installer again."
  if command -v az >/dev/null 2>&1 && brew list azure-cli >/dev/null 2>&1; then
    info "The Azure CLI is installed but not working — reinstalling it."
    brew reinstall azure-cli </dev/null || true
  else
    brew_install azure-cli || true
  fi
  az version >/dev/null 2>&1 || fatal "The Azure CLI did not install correctly (see the messages above)." \
                                      "If a download error is shown: pause Zscaler for 15 minutes and run this again."
  success "Azure CLI installed."
  record "Azure CLI     : installed"
}

# ----------------------------------------------------------------------------
# 4. Claude Code (native, self-contained binary — Node.js NOT required).
# ----------------------------------------------------------------------------
login_shell() { dscl . -read "/Users/${USER}" UserShell 2>/dev/null | awk '{print $2}' || true; }

ensure_path() {
  step "Making 'claude' and 'claude-login' available in Terminal"
  mkdir -p "$LOCAL_BIN"
  # BOTH zsh files: Terminal reads ~/.zprofile (login shell); the VS Code
  # terminal reads only ~/.zshrc.
  local line='export PATH="$HOME/.local/bin:$PATH"'
  ensure_line "$line" "${HOME}/.zprofile"
  ensure_line "$line" "${HOME}/.zshrc"
  # 'claude' typed in the home folder starts in ~/Claude instead (see
  # WORKSPACE); anywhere else it is untouched. 'function' form + unalias: an
  # old 'alias claude=…' would otherwise break or bypass the definition.
  local wrapper='unalias claude 2>/dev/null; function claude { if [ "$PWD" = "$HOME" ]; then (cd "$HOME/Claude" && command claude "$@"); else command claude "$@"; fi; }  # claude_corp_bootstrap.sh: start in ~/Claude, not the home folder'
  local wlabel="Claude Code starts in ~/Claude when run from your home folder"
  ensure_line "$wrapper" "${HOME}/.zshrc" "$wlabel"
  case "$(login_shell)" in
    */bash) ensure_line "$line" "${HOME}/.bash_profile"; ensure_line "$wrapper" "${HOME}/.bash_profile" "$wlabel" ;;
  esac
  case ":${PATH}:" in
    *":${LOCAL_BIN}:"*) : ;;
    *) export PATH="${LOCAL_BIN}:${PATH}" ;;
  esac
}

ensure_claude_code() {
  step "Claude Code"
  if [[ -x "$CLAUDE_BIN" ]] && "$CLAUDE_BIN" --version </dev/null >/dev/null 2>&1; then
    success "Claude Code already installed ($("$CLAUDE_BIN" --version </dev/null 2>/dev/null | head -1)). It updates itself."
    record "Claude Code   : present ($("$CLAUDE_BIN" --version </dev/null 2>/dev/null | head -1))"
    return 0
  fi

  local other=""
  other="$(command -v claude 2>/dev/null || true)"
  [[ -n "$other" ]] && info "Another Claude Code install was found at ${other}; installing the native one, which takes priority."

  # Never -k: TLS verification stays on (macOS trusts the corporate root).
  # The pipe IS bash's stdin here — do not add a '</dev/null' redirect.
  # Three attempts: a single dropped connection through the corporate proxy
  # (curl 35/56) must not end the install.
  local attempt
  for ((attempt = 1; attempt <= 3; attempt++)); do
    info "Downloading and installing Claude Code (attempt ${attempt} of 3)…"
    if curl -fsSL --retry 2 https://claude.ai/install.sh | bash \
       && [[ -x "$CLAUDE_BIN" ]] && "$CLAUDE_BIN" --version </dev/null >/dev/null 2>&1; then
      break
    fi
    warn "The Claude Code download did not complete."
    if (( attempt < 3 )); then sleep 5; fi
  done
  if [[ -x "$CLAUDE_BIN" ]] && "$CLAUDE_BIN" --version </dev/null >/dev/null 2>&1; then
    success "Claude Code installed ($("$CLAUDE_BIN" --version </dev/null 2>/dev/null | head -1))."
    record "Claude Code   : installed ($("$CLAUDE_BIN" --version </dev/null 2>/dev/null | head -1))"
  else
    fatal "Claude Code did not install (see the messages above)." \
          "If a certificate or download error is shown: pause Zscaler for 15 minutes and run this again."
  fi
}

# ----------------------------------------------------------------------------
# 5a. Token helper — ~/.claude/get-claude-token.sh (chmod 700).
#
# Lessons baked into the generated helper (each one was a real outage):
#   - It NEVER signs in by itself. Claude Code runs it with no terminal, so a
#     sign-in prompt would be invisible, and parallel sessions would each start
#     one (an MFA storm, AADSTS50076). Its error tells the person to run
#     'claude-login' — Claude Code shows that message verbatim.
#   - 'cd /' first. Claude Code runs the helper in the current project folder;
#     if that is unreadable, 'az' dies on getcwd and looks like a dead login.
#   - Homebrew on PATH: spawned processes can inherit a minimal PATH.
#   - '--tenant': the token comes from the Sleep Number tenant even if the
#     account is also a guest elsewhere, and works with no subscription.
#   - One 'az' call on the happy path (~1-2 s each), one retry for cache
#     contention. stdout is the bare token only, no trailing newline.
#
# A helper this script did NOT write (no marker line) is left alone unless
# FORCE_TOKEN_HELPER=1 — people with a hand-built refresh chain keep it.
# ----------------------------------------------------------------------------
ensure_token_helper() {
  step "Writing the Azure token helper (~/.claude/get-claude-token.sh)"
  mkdir -p "$CLAUDE_DIR"

  local desired=""
  # 'read -d ""' rather than "$(cat <<'EOF')": macOS bash 3.2 mis-parses quotes
  # and parentheses inside a heredoc nested in command substitution.
  IFS= read -r -d '' desired <<'HELPER' || true
#!/bin/bash
# Auto-generated by claude_corp_bootstrap.sh — Claude Code apiKeyHelper.
# Prints an Azure Entra access token for the Foundry gateway. Claude Code sends
# stdout as the bearer token, so stdout must be the bare token and nothing else.
#
# Requires CLAUDE_CODE_SKIP_FOUNDRY_AUTH=1 in ~/.claude/settings.json; without
# it Claude Code's Foundry client ignores this helper entirely.
#
# This helper never signs in. When it fails, Claude Code shows the message
# below, which tells the person to run 'claude-login'.

cd / 2>/dev/null
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"

RESOURCE="@@RESOURCE@@"
TENANT="@@TENANT@@"
LOG="${HOME}/.claude/azure-token-helper.log"
CA_BUNDLE="${HOME}/.claude/azure-ca-bundle.pem"
[ -s "$CA_BUNDLE" ] && export REQUESTS_CA_BUNDLE="$CA_BUNDLE"

if [ -f "$LOG" ] && [ "$(wc -c <"$LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    tail -n 200 "$LOG" >"$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
fi

get_token() {
    az account get-access-token --tenant "$TENANT" --resource "$RESOURCE" \
        --query accessToken -o tsv 2>>"$LOG"
}

if ! command -v az >/dev/null 2>&1; then
    echo "The Azure CLI is missing. Run the Claude Code installer again." >&2
    exit 1
fi

TOKEN="$(get_token)"
if [ -z "$TOKEN" ]; then
    sleep 2
    TOKEN="$(get_token)"
fi

if [ -z "$TOKEN" ]; then
    printf '%s token request failed (details above)\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" >>"$LOG"
    echo "Not signed in to Azure. Open a new Terminal window, type claude-login and press Return, then try again here." >&2
    exit 1
fi

printf '%s' "$TOKEN"
HELPER
  desired="${desired%$'\n'}"
  desired="${desired//@@RESOURCE@@/${FOUNDRY_TOKEN_RESOURCE}}"
  desired="${desired//@@TENANT@@/${FOUNDRY_TENANT_ID}}"

  write_generated "$TOKEN_HELPER" "$desired" "Token helper " "${FORCE_TOKEN_HELPER:-0}"
}

# Write a generated script: no-op if identical; never overwrite a file this
# script did not write unless forced; back up what it replaces.
write_generated() {   # $1 path  $2 content  $3 summary label  $4 force (1/0)
  local path="$1" content="$2" label="$3" force="${4:-0}"
  if [[ -f "$path" ]] && [[ "$(cat "$path")" == "$content" ]]; then
    chmod 700 "$path"
    success "$(basename "$path") is already current."
    record "${label} : current"
  elif [[ -f "$path" ]] && ! grep -qF "$GENERATED_MARKER" "$path" && [[ "$force" != "1" ]]; then
    warn "${path} was not written by this installer — leaving it untouched."
    record "${label} : kept existing custom file"
  else
    if [[ -f "$path" ]]; then
      local backup
      backup="${path}.$(date +%Y%m%d-%H%M%S).bak"
      cp -p "$path" "$backup"
      info "Previous version backed up to ${backup}."
    fi
    write_atomic "$path" 700 "$content"
    success "Wrote ${path}."
    record "${label} : written"
  fi
}

# Replace a file via temp file + rename in the same folder. A rename needs
# write access to the folder only, so this also replaces a file another
# account (e.g. root, after an earlier 'sudo' run) owns or made read-only —
# where '>' would fail and stop the installer.
write_atomic() {   # $1 path  $2 mode  $3 content
  local path="$1" mode="$2" tmp
  tmp="$(mktemp "${path}.XXXXXX")" || fatal "Cannot write in $(dirname "$path")." "Contact ${SUPPORT_CONTACT}."
  printf '%s\n' "$3" > "$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$path" || { rm -f "$tmp"; fatal "Cannot replace ${path}." "Contact ${SUPPORT_CONTACT}."; }
}

# ----------------------------------------------------------------------------
# 5b. claude-login — the one command a person needs when their Microsoft
# sign-in expires. The installer uses the same command for the first sign-in,
# so there is exactly one sign-in implementation.
#
#   Browser first (no code to copy; satisfies device-based Conditional Access),
#   device code as the fallback (code copied to the clipboard, page opened).
#   '--allow-no-subscriptions': most people have no Azure subscription, and
#   'az login' fails without it. The subscription picker is switched off for
#   this command only (environment variable, not a permanent az setting).
#   If az hits TLS inspection, it is given the macOS trust store and retried.
# ----------------------------------------------------------------------------
ensure_login_command() {
  step "Writing the sign-in command (~/.local/bin/claude-login)"
  mkdir -p "$LOCAL_BIN"

  local desired=""
  IFS= read -r -d '' desired <<'LOGIN' || true
#!/bin/bash
# Auto-generated by claude_corp_bootstrap.sh — signs you in to Microsoft/Azure
# so Claude Code can reach the Sleep Number AI gateway.
#
#   claude-login           sign in (browser first; a device code if that fails)
#   claude-login --check   exit 0 if Claude Code can get a token right now

set -uo pipefail
cd / 2>/dev/null
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"

TENANT="@@TENANT@@"
RESOURCE="@@RESOURCE@@"
CA_BUNDLE="${HOME}/.claude/azure-ca-bundle.pem"
LOG="${HOME}/.claude/azure-token-helper.log"

export AZURE_CORE_LOGIN_EXPERIENCE_V2=off
[ -s "$CA_BUNDLE" ] && export REQUESTS_CA_BUNDLE="$CA_BUNDLE"

if ! command -v az >/dev/null 2>&1; then
    echo "claude-login: the Azure CLI is missing. Run the Claude Code installer again." >&2
    exit 1
fi

WORK="$(mktemp -d -t claude-login)" || exit 1
AZ_PID=""
cleanup() { [ -n "$AZ_PID" ] && kill "$AZ_PID" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT
trap 'exit 130' INT TERM

have_token() {
    az account get-access-token --tenant "$TENANT" --resource "$RESOURCE" \
        --query accessToken -o tsv >/dev/null 2>"$WORK/token.err"
}

tls_problem() {
    grep -qiE 'CERTIFICATE_VERIFY_FAILED|certificate verify failed|SSLError|SSLCertVerificationError' "$@" 2>/dev/null
}

# Give az (Python) the macOS trust store, which holds the corporate root
# certificate. Only done after az actually hit a certificate error.
build_ca_bundle() {
    [ -s "$CA_BUNDLE" ] && return 1
    mkdir -p "$(dirname "$CA_BUNDLE")"
    security find-certificate -a -p \
        /System/Library/Keychains/SystemRootCertificates.keychain \
        /Library/Keychains/System.keychain >"$CA_BUNDLE.tmp" 2>/dev/null
    if [ -s "$CA_BUNDLE.tmp" ]; then
        mv "$CA_BUNDLE.tmp" "$CA_BUNDLE"
        export REQUESTS_CA_BUNDLE="$CA_BUNDLE"
        echo "  (Using the Mac's certificate store for Microsoft sign-in.)"
        return 0
    fi
    rm -f "$CA_BUNDLE.tmp"
    return 1
}

if [ "${1:-}" = "--check" ]; then
    have_token && exit 0
    tls_problem "$WORK/token.err" && build_ca_bundle && have_token && exit 0
    exit 1
fi

# Wait for the background az for up to $1 seconds; 124 on timeout.
wait_az() {
    local deadline=$(( $(date +%s) + $1 )) rc
    while kill -0 "$AZ_PID" 2>/dev/null; do
        if [ "$(date +%s)" -ge "$deadline" ]; then
            kill "$AZ_PID" 2>/dev/null; wait "$AZ_PID" 2>/dev/null; AZ_PID=""
            return 124
        fi
        sleep 1
    done
    wait "$AZ_PID"; rc=$?; AZ_PID=""
    return $rc
}

login_browser() {
    echo ""
    echo "  A browser window is opening. Sign in with your Sleep Number account"
    echo "  and approve the sign-in on your phone. Then come back to this window."
    echo ""
    az login --tenant "$TENANT" --scope "$RESOURCE/.default" --allow-no-subscriptions \
        --output none </dev/null >"$WORK/browser.log" 2>&1 &
    AZ_PID=$!
    wait_az 300
}

login_device() {
    az login --use-device-code --tenant "$TENANT" --scope "$RESOURCE/.default" \
        --allow-no-subscriptions --output none </dev/null >"$WORK/device.log" 2>&1 &
    AZ_PID=$!
    local code="" i=0
    while [ $i -lt 45 ]; do
        code="$(grep -oE 'enter the code [A-Z0-9]{6,12}' "$WORK/device.log" 2>/dev/null | tail -1 | awk '{print $4}')"
        [ -n "$code" ] && break
        kill -0 "$AZ_PID" 2>/dev/null || break
        sleep 1; i=$((i + 1))
    done
    if [ -z "$code" ]; then
        wait_az 5
        return 1
    fi
    printf '%s' "$code" | pbcopy 2>/dev/null
    open "https://microsoft.com/devicelogin" 2>/dev/null
    echo ""
    echo "  ------------------------------------------------------------------"
    echo "   A Microsoft page has opened in your browser."
    echo "   Your code is:   $code    (already copied - just paste it)"
    echo "   Paste the code, sign in, approve on your phone, then come back."
    echo "  ------------------------------------------------------------------"
    echo ""
    wait_az 900
}

done_ok() { echo "  Signed in. Claude Code is ready."; exit 0; }

if have_token; then echo "  Already signed in. Nothing to do."; exit 0; fi
tls_problem "$WORK/token.err" && build_ca_bundle && have_token && done_ok

echo "Signing in to Microsoft for Claude Code…"
if [ -z "${SSH_CONNECTION:-}" ]; then
    login_browser
    have_token && done_ok
    if tls_problem "$WORK/browser.log" && build_ca_bundle; then
        login_browser
        have_token && done_ok
    fi
    echo "  The browser sign-in did not finish. Trying with a sign-in code instead…"
fi
login_device
have_token && done_ok
if tls_problem "$WORK/device.log" && build_ca_bundle; then
    login_device
    have_token && done_ok
fi

for f in "$WORK"/*.log "$WORK/token.err"; do
    [ -s "$f" ] && { printf '%s claude-login %s:\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$(basename "$f")"; cat "$f"; } >>"$LOG" 2>/dev/null
done
reason="$(cat "$WORK"/*.log "$WORK/token.err" 2>/dev/null | grep -oE 'AADSTS[0-9]+[^.]*' | tail -1)"
echo ""
echo "  Sign-in did not complete."
[ -n "$reason" ] && echo "  Microsoft said: $reason"
case "$reason" in
    AADSTS50105*|AADSTS65001*|AADSTS500011*|AADSTS700016*)
        echo "  Your account may not have access yet (check the 'Azure Subscription' request)." ;;
    AADSTS53003*|AADSTS530003*)
        echo "  A sign-in policy blocked this device. Contact the AI CoE team." ;;
esac
echo "  Run claude-login to try again. Details: $LOG"
exit 1
LOGIN
  desired="${desired%$'\n'}"
  desired="${desired//@@RESOURCE@@/${FOUNDRY_TOKEN_RESOURCE}}"
  desired="${desired//@@TENANT@@/${FOUNDRY_TENANT_ID}}"

  write_generated "$LOGIN_CMD" "$desired" "claude-login " 0
}

# ----------------------------------------------------------------------------
# 5c. settings.json — safe, idempotent, atomic deep-merge of the Foundry keys.
# Uses jq '($base | clean) * $patch': patch wins; existing hooks, plugins,
# marketplaces and unrelated env keys are preserved; keys that defeat Foundry
# mode are removed and named. Backs up first, validates before replacing.
#
#   apiKeyHelper                       script whose stdout is the bearer token
#   model                              default model alias (opus)
#   CLAUDE_CODE_USE_FOUNDRY=1          route Claude Code to Microsoft Foundry
#   CLAUDE_CODE_SKIP_FOUNDRY_AUTH=1    skip the built-in Azure credential chain
#                                      so the apiKeyHelper token is what is sent
#                                      (without it the helper is IGNORED)
#   CLAUDE_CODE_API_KEY_HELPER_TTL_MS  how often the helper is re-run
#   ANTHROPIC_FOUNDRY_BASE_URL         the gateway
#   ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL  model id per alias
# ----------------------------------------------------------------------------
settings_json_literal() {
  cat <<EOF
{
  "apiKeyHelper": "${TOKEN_HELPER_TILDE}",
  "model": "${FOUNDRY_DEFAULT_MODEL}",
  "env": {
    "CLAUDE_CODE_USE_FOUNDRY": "1",
    "CLAUDE_CODE_SKIP_FOUNDRY_AUTH": "1",
    "CLAUDE_CODE_API_KEY_HELPER_TTL_MS": "${FOUNDRY_TOKEN_TTL_MS}",
    "ANTHROPIC_FOUNDRY_BASE_URL": "${FOUNDRY_BASE_URL}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "${FOUNDRY_SONNET}",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "${FOUNDRY_HAIKU}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "${FOUNDRY_OPUS}"
  }
}
EOF
}

ensure_settings() {
  step "Writing Claude Code settings (~/.claude/settings.json)"
  mkdir -p "$CLAUDE_DIR"

  # --- No jq: a fresh file can be written whole; an existing one is never
  # hand-merged in bash — the Foundry keys go to a sidecar instead.
  if ! command -v jq >/dev/null 2>&1; then
    if [[ ! -s "$SETTINGS_FILE" ]]; then
      write_atomic "$SETTINGS_FILE" 600 "$(settings_json_literal)"
      success "Wrote ${SETTINGS_FILE}."
      record "settings.json : written"
    else
      local sidecar="${CLAUDE_DIR}/settings.foundry.json"
      settings_json_literal > "$sidecar"
      chmod 600 "$sidecar"
      warn "jq is missing, so the existing settings.json was not changed. Foundry keys: ${sidecar}"
      problem "Install jq ('brew install jq') and run this installer again to finish the settings."
      record "settings.json : NOT merged (jq missing)"
    fi
    return 0
  fi

  local patch
  patch="$(jq -n \
    --arg helper "$TOKEN_HELPER_TILDE" --arg ttl "$FOUNDRY_TOKEN_TTL_MS" \
    --arg model "$FOUNDRY_DEFAULT_MODEL" --arg baseurl "$FOUNDRY_BASE_URL" \
    --arg sonnet "$FOUNDRY_SONNET" --arg haiku "$FOUNDRY_HAIKU" --arg opus "$FOUNDRY_OPUS" \
    '{
       apiKeyHelper: $helper,
       model: $model,
       env: {
         CLAUDE_CODE_USE_FOUNDRY: "1",
         CLAUDE_CODE_SKIP_FOUNDRY_AUTH: "1",
         CLAUDE_CODE_API_KEY_HELPER_TTL_MS: $ttl,
         ANTHROPIC_FOUNDRY_BASE_URL: $baseurl,
         ANTHROPIC_DEFAULT_SONNET_MODEL: $sonnet,
         ANTHROPIC_DEFAULT_HAIKU_MODEL: $haiku,
         ANTHROPIC_DEFAULT_OPUS_MODEL: $opus
       }
     }')"

  local base
  if [[ ! -s "$SETTINGS_FILE" ]]; then
    base='{}'
  elif ! jq -e 'type == "object"' "$SETTINGS_FILE" >/dev/null 2>&1; then
    local ibak
    ibak="${SETTINGS_FILE}.invalid.$(date +%Y%m%d-%H%M%S).bak"
    mv "$SETTINGS_FILE" "$ibak"
    warn "The existing settings.json was not valid JSON. Moved aside to ${ibak}; writing a fresh one."
    base='{}'
  else
    base="$(cat "$SETTINGS_FILE")"
  fi

  local merge_expr="${JQ_CLEAN_DEF} (\$base | clean) * \$patch"

  if [[ "$base" != '{}' ]] && \
     diff -q <(printf '%s' "$base" | jq -S .) \
             <(jq -n --argjson base "$base" --argjson patch "$patch" \
                     --argjson stale "$STALE_ENV_KEYS_JSON" "$merge_expr" | jq -S .) \
             >/dev/null 2>&1; then
    success "settings.json already has the Foundry configuration."
    record "settings.json : already up to date"
    return 0
  fi

  local removed
  removed="$(jq -rn --argjson b "$base" --argjson stale "$STALE_ENV_KEYS_JSON" '
    ( (if $b | has("apiKeyHelperTtlMs") then ["apiKeyHelperTtlMs"] else [] end)
    + (if ($b.env | type) == "object"
       then [ $stale[] as $k | select($b.env | has($k)) | "env." + $k ]
       else [] end) ) | join(", ")')"
  [[ -n "$removed" ]] && warn "Removing settings that defeat Foundry mode: ${removed} (kept in the backup)"

  if [[ "$base" != '{}' ]]; then
    local backup
    backup="${SETTINGS_FILE}.$(date +%Y%m%d-%H%M%S).bak"
    cp -p "$SETTINGS_FILE" "$backup"
    chmod 600 "$backup" 2>/dev/null || true
    info "Backup written to ${backup}."
  fi

  local tmp
  tmp="$(mktemp "${SETTINGS_FILE}.XXXXXX")"
  if ! jq -n --argjson base "$base" --argjson patch "$patch" \
        --argjson stale "$STALE_ENV_KEYS_JSON" "$merge_expr" > "$tmp" \
     || ! jq empty "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    fatal "Could not write ${SETTINGS_FILE} (the original is unchanged)." "Contact ${SUPPORT_CONTACT}."
  fi
  chmod 600 "$tmp"
  mv "$tmp" "$SETTINGS_FILE"
  success "Wrote the Foundry configuration into ${SETTINGS_FILE} (other settings kept)."
  record "settings.json : written"
}

# ----------------------------------------------------------------------------
# 5d. Skip Claude Code's first-run screens. On a new account Claude Code shows
# a theme picker, safety notes, then a folder-trust question whose DEFAULT
# answer is "No, exit" — pressing Return there quits Claude Code. Mark
# onboarding done and trust ~/Claude (WORKSPACE), where 'claude' starts; the
# per-action permission prompts are unaffected. Existing values are kept,
# except a declined trust for ~/Claude is turned on.
# ----------------------------------------------------------------------------
ensure_claude_state() {
  step "Preparing Claude Code's first start"
  mkdir -p "$WORKSPACE"
  local ws_real
  ws_real="$(cd "$WORKSPACE" && pwd -P)"

  if ! command -v jq >/dev/null 2>&1; then
    if [[ ! -e "$CLAUDE_STATE" ]]; then
      local h="${WORKSPACE//\\/\\\\}" state=""; h="${h//\"/\\\"}"
      printf -v state '{\n  "hasCompletedOnboarding": true,\n  "theme": "dark",\n  "projects": { "%s": { "hasTrustDialogAccepted": true } }\n}' "$h"
      write_atomic "$CLAUDE_STATE" 600 "$state"
      success "First-run screens skipped."
      record "First start   : prepared"
    else
      info "Skipped (jq missing). Claude Code will show its first-run questions."
      record "First start   : not prepared (jq missing)"
    fi
    return 0
  fi

  local base='{}'
  if [[ -s "$CLAUDE_STATE" ]]; then
    if ! jq -e 'type == "object"' "$CLAUDE_STATE" >/dev/null 2>&1; then
      info "Left ${CLAUDE_STATE} alone (not valid JSON). Claude Code will repair it."
      record "First start   : not prepared (state file unreadable)"
      return 0
    fi
    base="$(cat "$CLAUDE_STATE")"
  fi

  local desired
  desired="$(jq -n --argjson b "$base" --arg h "$WORKSPACE" --arg rp "$ws_real" '
    $b
    | .hasCompletedOnboarding = true
    | .theme = (.theme // "dark")
    | .projects = (.projects // {})
    | .projects[$h] = ((.projects[$h] // {}) + {hasTrustDialogAccepted: true})
    | .projects[$rp] = ((.projects[$rp] // {}) + {hasTrustDialogAccepted: true})')"

  if [[ "$(printf '%s' "$base" | jq -S .)" == "$(printf '%s' "$desired" | jq -S .)" ]]; then
    success "Claude Code's first start is already prepared."
    record "First start   : already prepared"
    return 0
  fi
  local tmp
  tmp="$(mktemp "${CLAUDE_STATE}.XXXXXX")"
  printf '%s\n' "$desired" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$CLAUDE_STATE"
  success "First-run screens skipped; Claude Code will start in ${WORKSPACE}."
  record "First start   : prepared"
}

# ----------------------------------------------------------------------------
# 5e. The /make-it skill suite (sealmindset/make-it): /make-it, /try-it,
# /resume-it, /wrap-it and friends, copied into ~/.claude/commands and
# ~/.claude/make-it. Files only — no sudo, settings.json untouched.
#
#   Pinned to the commit this installer was tested with (MAKEIT_REF overrides,
#   e.g. MAKEIT_REF=main). make-it's own install.sh always pulls 'main' when
#   piped from curl, so instead the pinned commit's archive is unpacked and its
#   install.sh is run from there (its "local source" mode).
#   Never downgrades: an existing install (e.g. after '/make-it update') is kept.
#   Not fatal: Claude Code works without it; a failure is listed at the end.
#
#   NOTE: building and running apps with /make-it needs Docker, which this
#   installer deliberately does not install. /make-it's own Preflight says so.
# ----------------------------------------------------------------------------
MAKEIT_REPO="sealmindset/make-it"
MAKEIT_PINNED="09e4791cfe341a01fceb7444f7430839788b798c"   # v1.52.0, tested 2026-11-11
MAKEIT_REF="${MAKEIT_REF:-}"

ensure_makeit() {
  step "Installing the /make-it skills"
  local installed=""
  installed="$(tr -d '[:space:]' 2>/dev/null < "${CLAUDE_DIR}/make-it/VERSION" || true)"
  if [[ -z "$MAKEIT_REF" && -n "$installed" && -f "${CLAUDE_DIR}/commands/make-it.md" ]]; then
    success "/make-it skills already installed (v${installed}). Update later with '/make-it update'."
    record "/make-it      : present (v${installed})"
    return 0
  fi

  local ref="${MAKEIT_REF:-$MAKEIT_PINNED}" work src="" out attempt
  work="$(mktemp -d -t make-it)"
  out="${work}/install-output.txt"
  for ((attempt = 1; attempt <= 3; attempt++)); do
    if curl -fsSL --retry 2 "https://github.com/${MAKEIT_REPO}/archive/${ref}.tar.gz" -o "${work}/src.tgz" \
       && tar -xzf "${work}/src.tgz" -C "$work" 2>/dev/null; then
      src="$(find "$work" -mindepth 1 -maxdepth 1 -type d -name 'make-it-*' | head -1)"
      [[ -n "$src" && -f "${src}/install.sh" ]] && break
    fi
    src=""
    if (( attempt < 3 )); then sleep 5; fi
  done

  if [[ -z "$src" ]]; then
    rm -rf "$work"
    warn "Could not download the /make-it skills."
    problem "The /make-it skills did not install (download failed). Run this installer again."
    record "/make-it      : NOT installed (download failed)"
    return 0
  fi

  # Run from a neutral folder; output goes to the log, not the screen.
  if (cd /tmp && bash "${src}/install.sh" </dev/null >"$out" 2>&1) \
     && [[ -f "${CLAUDE_DIR}/commands/make-it.md" ]]; then
    installed="$(tr -d '[:space:]' 2>/dev/null < "${CLAUDE_DIR}/make-it/VERSION" || echo '?')"
    { printf -- '--- make-it install.sh output ---\n'; cat "$out"; } >> "$LOG_FILE" 2>/dev/null || true
    success "/make-it skills installed (v${installed}, $(ls "${CLAUDE_DIR}/commands/"*-it.md 2>/dev/null | wc -l | tr -d ' ') skills)."
    record "/make-it      : installed (v${installed})"
  else
    warn "The /make-it skills installer reported a problem:"
    tail -n 15 "$out" 2>/dev/null | sed 's/^/    /' || true
    problem "The /make-it skills did not install (see the messages above). Run this installer again."
    record "/make-it      : NOT installed"
  fi
  rm -rf "$work"
  return 0
}

# ----------------------------------------------------------------------------
# 5f. Shell-level overrides. settings.json can only clean what it holds; a
# variable exported from a shell profile still reaches Claude Code and masks
# Foundry. Reports file, line and NAME only — never the value. Read-only.
# ----------------------------------------------------------------------------
check_env_conflicts() {
  step "Checking for settings that would override Foundry"

  local found="no" v f line hits
  local pattern='^[[:space:]]*(export[[:space:]]+)?(ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN|CLAUDE_CODE_USE_BEDROCK|CLAUDE_CODE_USE_VERTEX)='

  for v in ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX; do
    if [[ -n "${!v:-}" ]]; then
      warn "${v} is set in this Terminal and overrides Foundry."
      found="yes"
    fi
  done

  for f in "${HOME}/.zshenv" "${HOME}/.zprofile" "${HOME}/.zshrc" \
           "${HOME}/.bash_profile" "${HOME}/.bashrc" "${HOME}/.profile"; do
    [[ -f "$f" && -r "$f" ]] || continue
    hits="$(grep -nE "$pattern" "$f" 2>/dev/null \
            | sed -E 's/^([0-9]+):[[:space:]]*(export[[:space:]]+)?([A-Z_]+)=.*/line \1: \3/' || true)"
    [[ -n "$hits" ]] || continue
    while IFS= read -r line; do
      warn "${f} ${line} — delete or comment out that line."
      found="yes"
    done <<< "$hits"
  done

  if [[ "$found" == "yes" ]]; then
    ENV_CONFLICTS="yes"
    problem "Remove the ANTHROPIC_*/provider lines listed under 'override Foundry', then open a new Terminal window."
    record "Overrides     : FOUND (see warnings)"
  else
    success "None found."
    record "Overrides     : none"
  fi
}

# ----------------------------------------------------------------------------
# 6. Microsoft sign-in, using the same claude-login command people use later.
# ----------------------------------------------------------------------------
ensure_azure_login() {
  step "Signing in to Microsoft (Azure)"

  if [[ "${SKIP_CORP_CHECKS:-0}" == "1" ]]; then
    info "Skipped (SKIP_CORP_CHECKS=1)."
    record "Azure sign-in : skipped (test mode)"
    return 0
  fi

  if "$LOGIN_CMD" --check </dev/null >/dev/null 2>&1; then
    success "Already signed in to Azure."
    AZ_LOGGED_IN="yes"
    record "Azure sign-in : signed in"
    return 0
  fi

  if [[ "$HAVE_TTY" != "yes" ]]; then
    warn "Not signed in, and no keyboard available to sign in now."
    problem "Open Terminal, type claude-login and press Return."
    record "Azure sign-in : NOT signed in"
    return 0
  fi

  local attempt
  for ((attempt = 1; attempt <= 3; attempt++)); do
    if "$LOGIN_CMD" </dev/tty; then
      AZ_LOGGED_IN="yes"
      success "Signed in to Azure."
      record "Azure sign-in : signed in"
      return 0
    fi
    (( attempt == 3 )) && break
    ask_enter "  Press Return to try signing in again (or type S and Return to skip): " || break
  done
  warn "Azure sign-in did not complete."
  problem "Sign in: open Terminal, type claude-login and press Return."
  record "Azure sign-in : NOT signed in"
}

# ----------------------------------------------------------------------------
# 7. Proof. A token, a 1-token request per model through the gateway (token on
# curl's stdin, never on the command line), then Claude Code itself answering.
# ----------------------------------------------------------------------------
verify_token() {
  step "Checking the Azure token"
  if [[ "${SKIP_CORP_CHECKS:-0}" == "1" ]]; then
    TOKEN_OK="skipped"
    record "Token         : skipped (test mode)"
    return 0
  fi
  if [[ "$AZ_LOGGED_IN" != "yes" ]]; then
    record "Token         : skipped (not signed in)"
    return 0
  fi
  if [[ -n "$("$TOKEN_HELPER" </dev/null 2>/dev/null | head -c 16 || true)" ]]; then
    TOKEN_OK="yes"
    success "The token helper returned a token (not shown)."
    record "Token         : OK"
  else
    warn "The token helper returned no token. Details: ${CLAUDE_DIR}/azure-token-helper.log"
    problem "Type claude-login in Terminal to sign in again, then run this installer again."
    record "Token         : FAILED"
  fi
}

verify_gateway() {
  step "Testing the AI gateway (a 1-token request to each model)"

  if [[ "${SKIP_GATEWAY_TEST:-0}" == "1" || "${SKIP_CORP_CHECKS:-0}" == "1" ]]; then
    info "Skipped (test mode)."
    record "Gateway test  : skipped"
    return 0
  fi
  if [[ "$TOKEN_OK" != "yes" ]]; then
    info "Skipped — no Azure token yet."
    record "Gateway test  : skipped (no token)"
    [[ "$GATEWAY_REACHABLE" == "no" ]] && problem "$VPN_PROBLEM"
    return 0
  fi

  local token
  token="$("$TOKEN_HELPER" </dev/null 2>/dev/null || true)"
  [[ -n "$token" ]] || { warn "No token on this attempt — skipped."; record "Gateway test  : skipped"; return 0; }

  local url="${FOUNDRY_BASE_URL%/}/v1/messages"
  local respfile entry slot model req code rc msg pass=0 total=0 unreachable="no"
  respfile="$(mktemp -t claude-gw)"

  for entry in "opus|${FOUNDRY_OPUS}" "sonnet|${FOUNDRY_SONNET}" "haiku|${FOUNDRY_HAIKU}"; do
    slot="${entry%%|*}"; model="${entry#*|}"; total=$((total + 1))
    if command -v jq >/dev/null 2>&1; then
      req="$(jq -nc --arg m "$model" '{model: $m, max_tokens: 1, messages: [{role: "user", content: "ping"}]}')"
    else
      req="{\"model\":\"${model}\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}"
    fi
    : > "$respfile"
    code="$(printf 'Authorization: Bearer %s\n' "$token" \
            | curl -sS -o "$respfile" -w '%{http_code}' --max-time 60 \
                -H @- -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' \
                -d "$req" "$url" 2>/dev/null)" && rc=0 || rc=$?
    msg=""
    command -v jq >/dev/null 2>&1 && \
      msg="$(jq -r '.error.message // .message // empty' "$respfile" 2>/dev/null | head -c 200 || true)"

    [[ "$code" == "000" || -z "$code" ]] && [[ "$rc" -ne 60 ]] && unreachable="yes"
    case "$code" in
      200) success "${slot} (${model}): answered"; pass=$((pass + 1)) ;;
      401) warn "${slot} (${model}): 401 — the gateway rejected the sign-in. ${msg}" ;;
      403) warn "${slot} (${model}): 403 — signed in, but this account is not authorized on the gateway. ${msg}" ;;
      404) warn "${slot} (${model}): 404 — this model is not available on the gateway. ${msg}" ;;
      000|"")
        if [[ "$rc" -eq 60 ]]; then warn "${slot} (${model}): certificate not trusted (curl 60)."
        else warn "${slot} (${model}): gateway unreachable (curl ${rc}) — VPN?"; fi ;;
      *)   warn "${slot} (${model}): HTTP ${code}. ${msg}" ;;
    esac
  done
  rm -f "$respfile"
  token=""

  record "Gateway test  : ${pass}/${total} models answered"
  if [[ "$pass" -eq "$total" ]]; then
    GATEWAY_OK="yes"
    verify_claude_prompt
  else
    GATEWAY_OK="no"
    if [[ "$unreachable" == "yes" ]]; then
      problem "$VPN_PROBLEM"
    else
      problem "The AI gateway did not answer for every model (see the warnings above). Send the log to ${SUPPORT_CONTACT}."
    fi
  fi
  return 0
}

# Claude Code itself, reading ~/.claude/settings.json, answers a one-line
# prompt. Hard 90 s limit: with a token the gateway rejects, 'claude -p'
# retries for minutes instead of exiting.
verify_claude_prompt() {
  if ! command -v perl >/dev/null 2>&1; then
    info "Skipping the Claude Code test (no safe timeout available)."
    record "Claude test   : skipped"
    return 0
  fi
  info "Asking Claude Code for a one-word reply…"
  local out
  out="$(cd "$WORKSPACE" && with_timeout 90 "$CLAUDE_BIN" -p --no-session-persistence --model haiku \
           "Reply with exactly the word OK and nothing else." </dev/null 2>&1 || true)"
  # Whole-line match: a bare 'OK' substring would also match "invalid TOKEN".
  if printf '%s\n' "$out" | grep -qxE '[[:space:]]*OK\.?[[:space:]]*'; then
    success "Claude Code answered through Azure AI Foundry."
    record "Claude test   : OK"
  else
    GATEWAY_OK="no"
    warn "Claude Code did not answer within 90 seconds."
    [[ -n "$out" ]] && warn "It said: $(printf '%s' "$out" | head -c 300)"
    problem "Claude Code could not answer although the gateway did. Send the log to ${SUPPORT_CONTACT}."
    record "Claude test   : FAILED"
  fi
}

verify_binaries() {
  if "$CLAUDE_BIN" --version </dev/null >/dev/null 2>&1; then
    CLAUDE_OK="yes"
  else
    problem "Claude Code is installed but does not start. Send the log to ${SUPPORT_CONTACT}."
  fi
  local others
  others="$(which -a claude 2>/dev/null | grep -vxF "$CLAUDE_BIN" | tr '\n' ' ' || true)"
  [[ -n "$others" ]] && info "Other Claude Code copies on this Mac (the native one wins): ${others}"
  return 0
}

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
print_summary() {
  printf '\n%s------------------------- SUMMARY -------------------------%s\n' "${C_BLU}" "${C_RESET}"
  local line
  # ${arr[@]+"${arr[@]}"}: bash 3.2 treats an EMPTY array as unbound under 'set -u'.
  for line in ${SUMMARY_LINES[@]+"${SUMMARY_LINES[@]}"}; do printf '  %s\n' "$line"; done
  printf '%s-----------------------------------------------------------%s\n' "${C_BLU}" "${C_RESET}"

  # TOKEN_OK is "skipped" only with SKIP_CORP_CHECKS=1; the summary then shows
  # a "Test mode … SKIPPED" line, so a test ALL SET can't pass for a real one.
  if [[ ${#PROBLEMS[@]} -eq 0 && "$CLAUDE_OK" == "yes" && "$TOKEN_OK" != "no" \
        && ( "$GATEWAY_OK" == "yes" || "$GATEWAY_OK" == "untested" ) ]]; then
    printf '\n%s============================================================%s\n' "${C_GRN}" "${C_RESET}"
    printf '%s  ALL SET — Claude Code is installed and connected.%s\n\n' "${C_GRN}${C_BOLD}" "${C_RESET}"
    printf '  To start Claude Code:\n'
    printf '    1. Open a NEW Terminal window (press Command-N)\n'
    printf '    2. Type  claude  and press Return\n'
    printf '  It works in the Claude folder in your home folder (%s).\n\n' "$WORKSPACE"
    printf '  If Claude Code ever says "Not signed in to Azure":\n'
    printf '    type  claude-login  in Terminal and press Return.\n\n'
    printf '  Log of this install: %s\n' "$LOG_FILE"
    printf '%s============================================================%s\n' "${C_GRN}" "${C_RESET}"
    return 0
  fi

  printf '\n%s============================================================%s\n' "${C_YEL}" "${C_RESET}"
  printf '%s  ALMOST DONE — one or more things still need attention:%s\n\n' "${C_YEL}${C_BOLD}" "${C_RESET}"
  local n=0 p
  for p in ${PROBLEMS[@]+"${PROBLEMS[@]}"}; do
    n=$((n + 1)); printf '  %d. %s\n' "$n" "$p"
  done
  (( n == 0 )) && printf '  1. The final checks did not pass (see the warnings above).\n'
  printf '\n  Then run the same command again — it skips what is already done.\n'
  printf '  If you need help, send this log file to %s:\n    %s\n' "$SUPPORT_CONTACT" "$LOG_FILE"
  printf '%s============================================================%s\n' "${C_YEL}" "${C_RESET}"
  return 3
}

# ----------------------------------------------------------------------------
# main — defined as a function and invoked ONLY on the final lines, so a
# dropped download during 'curl | bash' can never run a partial script.
# ----------------------------------------------------------------------------
main() {
  # This runs in the pipeline's subshell; the top level turned errexit and the
  # ERR trap off around the pipeline, so turn them back on here.
  set -Eeuo pipefail
  ERR_TRAP_LEVEL="${BASH_SUBSHELL:-0}"
  install_err_trap
  # bash 3.2 runs this EXIT trap only on an explicit 'exit' in this subshell,
  # not when main() simply returns — so every path out of main() calls exit.
  trap cleanup EXIT

  cd "$HOME"
  if { : </dev/tty; } 2>/dev/null; then HAVE_TTY="yes"; fi
  take_lock

  # Keep the Mac awake while installing (released when the installer exits).
  if command -v caffeinate >/dev/null 2>&1; then
    caffeinate -i -m -s -w "$$" >/dev/null 2>&1 &
    CAFFEINATE_PID=$!; disown "$CAFFEINATE_PID" 2>/dev/null || true
  fi

  banner
  check_mac
  check_network
  assess
  ensure_admin            # the only password prompt; repairs file ownership
  ensure_clt              # headless; GUI fallback
  ensure_homebrew
  ensure_jq
  ensure_azure_cli
  ensure_path
  ensure_claude_code
  ensure_token_helper
  ensure_login_command
  ensure_settings
  ensure_claude_state
  ensure_makeit           # /make-it skills, pinned; files only
  check_env_conflicts
  ensure_azure_login
  verify_binaries
  verify_token
  verify_gateway
  local final=0
  print_summary || final=$?   # 3 = installed, final checks not passed
  exit "$final"               # explicit: runs the EXIT trap (cleanup) on bash 3.2
}

mkdir -p "$LOG_DIR" 2>/dev/null || LOG_FILE="/tmp/claude_corp_bootstrap-$(date +%Y%m%d-%H%M%S).log"
# A deliberate non-zero exit from main (2 = stopped, 3 = checks failed) must not
# trip the top-level ERR trap or errexit before its code is passed on.
trap - ERR
set +e
main "$@" 2>&1 | tee -a "$LOG_FILE"
exit "${PIPESTATUS[0]}"
