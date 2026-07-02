#!/usr/bin/env bash
# =============================================================================
# launch-mac.sh — host-side launcher orchestrator for Claude Code on macOS.
#
# Run by the "Start Claude Code.command" launcher in a VISIBLE Terminal window.
# The sourced preflight library's UI helpers are terminal-aware: in a terminal
# they print plain text + read prompts (reliable, visible — nothing fails
# silently); with no terminal (background fallback) they use osascript dialogs.
#
# Sequence (each preflight step retries via ui_block on failure — the user can
# continue the step or quit the launcher cleanly):
#   1. check_vpn
#   2. ensure_docker_engine
#   3. ensure_container
#   4. provider auth (open the web login wizard, poll until authed)
#   5. open Workshop deep-link (last project) or the dashboard
#   6. spawn a detached background update check (never blocks steps 1-5)
#
# 'set -euo pipefail' is used, but the ui_block Quit path exits 0 cleanly (a
# Quit is a normal, user-requested exit, not an error).
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# The .app launches us via LaunchServices with a MINIMAL PATH
# (/usr/bin:/bin:/usr/sbin:/sbin), so docker / az / etc. are not found the way
# they are in a login shell. Prepend the usual locations for Rancher Desktop,
# Docker Desktop, and Homebrew before anything runs.
# ---------------------------------------------------------------------------
export PATH="$HOME/.rd/bin:/usr/local/bin:/opt/homebrew/bin:/Applications/Docker.app/Contents/Resources/bin:$PATH"

# ---------------------------------------------------------------------------
# Output visibility:
#   * Visible Terminal (the .command launcher) — leave stdout/stderr ON SCREEN
#     so the user watches progress and SEES any problem. This is the whole
#     point of the .command approach: nothing can fail silently.
#   * No terminal (background .app fallback) — redirect everything to a log so
#     a failure is never invisible. Plain redirection, NOT process substitution
#     (`> >(tee ...)`), which fails under the .app's minimal environment.
# ---------------------------------------------------------------------------
CCDW_LAUNCH_LOG="${CCDW_LAUNCH_LOG:-$HOME/ccdw-launcher.log}"
{ echo ""; echo "=== Claude Code launch $(date) ==="; } >>"$CCDW_LAUNCH_LOG" 2>/dev/null || true
if [ -t 1 ]; then
    printf '\n  Starting Claude Code — please keep this window open.\n\n'
else
    exec >>"$CCDW_LAUNCH_LOG" 2>&1
fi

# ---------------------------------------------------------------------------
# Locate ourselves and source the preflight library.
# ---------------------------------------------------------------------------
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"

# CCDW_REPO_DIR is the repo root (parent of scripts/). Export it before sourcing
# so the library resolves .env / container config against the same tree.
: "${CCDW_REPO_DIR:="$(cd "${_SELF_DIR}/.." 2>/dev/null && pwd)"}"
export CCDW_REPO_DIR
: "${CONTAINER_NAME:=claude-code}"
export CONTAINER_NAME

# The library is intentionally free of 'set -e' and guards every internal probe,
# so sourcing it under our 'set -euo pipefail' is safe.
# shellcheck source=/dev/null
. "${_SELF_DIR}/mac-preflight-lib.sh"

# ---------------------------------------------------------------------------
# Config: dashboard / workshop / login-wizard URLs.
# Derive the ports from .env (via the library) so a user who changed
# WELCOME_PORT / TTYD_PORT / WORKSHOP_PORT on a port conflict still gets live
# URLs instead of blank browser tabs.
# ---------------------------------------------------------------------------
_mpl_load_ports
: "${DASHBOARD_URL:=http://localhost:${WELCOME_PORT}}"
: "${WEB_TERMINAL_URL:=http://localhost:${TTYD_PORT}}"   # ttyd — runs login-wizard.sh
: "${WORKSHOP_BASE_URL:=http://localhost:${WORKSHOP_PORT}}"

# Log for the detached background update check.
: "${CCDW_UPDATE_LOG:=/tmp/ccdw-update-check.log}"

# ---------------------------------------------------------------------------
# provider_display_name SLUG — map a provider slug to a human-readable name
# for use in dialog copy.
# ---------------------------------------------------------------------------
provider_display_name() {
    case "${1:-}" in
        foundry)   printf 'Azure AI Foundry' ;;
        bedrock)   printf 'AWS Bedrock' ;;
        anthropic) printf 'Anthropic' ;;
        claude)    printf 'Claude Account' ;;
        *)         printf 'your provider' ;;
    esac
}

# ---------------------------------------------------------------------------
# quit_launcher — clean exit requested by the user via ui_block "Quit".
# Exits 0 so 'set -e' never reports this normal path as a failure.
# ---------------------------------------------------------------------------
quit_launcher() {
    exit 0
}

# ---------------------------------------------------------------------------
# run_step CHECK_FN BLOCK_TITLE BLOCK_MSG
#   Run CHECK_FN in a retry loop. On success return 0. On failure show a
#   blocking Retry/Quit dialog; Retry loops the step, Quit exits cleanly.
#
# CHECK_FN is invoked with no arguments and must return 0 on success. Because
# we run under 'set -e', the check is called inside an 'if' so a nonzero return
# is a normal branch, not a fatal error.
# ---------------------------------------------------------------------------
run_step() {
    local check_fn="$1" block_title="$2" block_msg="$3"
    while true; do
        if "$check_fn"; then
            return 0
        fi
        # Step failed — ask the user. ui_block returns 0 for Retry, 1 for Quit.
        if ui_block "$block_title" "$block_msg"; then
            continue    # Retry: loop the step.
        else
            quit_launcher   # Quit: clean exit 0.
        fi
    done
}

# ===========================================================================
# STEP 0 — Installed check
#   The container start needs the repo .env (created by the installer). If it's
#   missing, this Mac was never set up — say so clearly instead of attempting a
#   doomed 'docker run' that would only end in a confusing "not ready" loop.
# ===========================================================================
step_check_installed() {
    if [ ! -f "$CCDW_REPO_DIR/.env" ]; then
        ui_info "Setup needed" \
            "Claude Code isn't set up on this Mac yet. Please run the installer (setup-claude-mac.command) first, then use this launcher."
        open "$CCDW_REPO_DIR" 2>/dev/null || true
        exit 0
    fi
}

# ===========================================================================
# STEP 1 — VPN
# ===========================================================================
step_vpn() {
    run_step check_vpn \
        "Action needed" \
        "Please connect to VPN (GlobalProtect), then continue."
}

# ===========================================================================
# STEP 2 — Docker engine
# ===========================================================================
step_docker() {
    ui_notify "Claude Code" "Starting Docker..."
    run_step ensure_docker_engine \
        "Docker isn't ready yet" \
        "Docker (Rancher Desktop / Docker Desktop) is still starting or needs attention. Once it's running, continue."
}

# ===========================================================================
# STEP 3 — Container / workspace
# ===========================================================================
step_container() {
    ui_notify "Claude Code" "Starting your workspace..."
    run_step ensure_container \
        "Workspace isn't ready yet" \
        "Your Claude Code workspace is still starting up. give it a moment, then continue."
}

# ===========================================================================
# STEP 4 — Provider authentication
#   If the provider is already authenticated we return immediately. Otherwise
#   open the web terminal (which runs login-wizard.sh) and poll until the user
#   completes sign-in — or clicks Quit.
# ===========================================================================
step_provider_auth() {
    local provider display
    provider="$(provider_from_env || true)"

    # No provider configured -> nothing to check; first-run setup happens in the
    # container's login wizard.
    if [ -z "$provider" ]; then
        return 0
    fi

    # Already signed in -> nothing to do.
    if check_provider_auth "$provider"; then
        return 0
    fi

    # NON-BLOCKING nudge: sign-in is missing/expired. Open the web sign-in
    # terminal and tell the user what to do, but NEVER block reaching their
    # project — the workspace also surfaces the sign-in prompt, and the user can
    # keep working on things that don't need AI. (For Azure, the fix is a
    # one-time `az login --use-device-code` in that terminal.)
    display="$(provider_display_name "$provider")"
    local how=""
    if [ "$provider" = "foundry" ]; then
        how=" Run:  az login --use-device-code"
    fi
    ui_info "AI sign-in needed" \
        "Your ${display} sign-in has expired or isn't set up yet. A sign-in window is opening.${how}  You can still pick a project — AI features work once you're signed in."
    open "$WEB_TERMINAL_URL" 2>/dev/null || true
    return 0
}

# ===========================================================================
# STEP 5 — Open the workspace (Workshop deep-link or dashboard)
# ===========================================================================
_open_project() {
    open "${WORKSHOP_BASE_URL}/?project=$(_lm_urlencode "$1")&resume=1" 2>/dev/null || true
}

step_open_workspace() {
    # Headless (no terminal): silently resume the single most-recent project.
    if ! _mpl_tty; then
        local proj0
        proj0="$(last_project || true)"
        if [ -n "$proj0" ]; then _open_project "$proj0"; else open "$DASHBOARD_URL" 2>/dev/null || true; fi
        return 0
    fi

    # Terminal: friendly "Keep working on" resume menu.
    local projects=()
    local p
    while IFS= read -r p; do
        [ -n "$p" ] && projects+=("$p")
    done < <(list_projects)

    if [ "${#projects[@]}" -eq 0 ] 2>/dev/null; then
        printf '\n  Opening Claude Code — start something new.\n'
        open "$DASHBOARD_URL" 2>/dev/null || true
        return 0
    fi

    printf '\n  Welcome back! Keep working on:\n\n'
    local i=1
    for p in "${projects[@]}"; do
        printf '    %d. %s\n' "$i" "$p"
        i=$((i + 1))
    done
    printf '    n. Start something new\n\n'

    local choice=""
    read -r -p "  Pick a number (or press Return for #1): " choice 2>/dev/null || choice=""
    case "$choice" in
        n|N) open "$DASHBOARD_URL" 2>/dev/null || true; return 0 ;;
        "")  choice=1 ;;
    esac

    if printf '%s' "$choice" | grep -qE '^[0-9]+$' \
        && [ "$choice" -ge 1 ] 2>/dev/null \
        && [ "$choice" -le "${#projects[@]}" ] 2>/dev/null; then
        local sel="${projects[$((choice - 1))]}"
        printf '\n  Opening %s...\n' "$sel"
        _open_project "$sel"
    else
        printf '\n  Not sure which one — opening the dashboard.\n'
        open "$DASHBOARD_URL" 2>/dev/null || true
    fi
    return 0
}

# _lm_urlencode STRING — percent-encode a string for a URL query value.
# Iterates under LC_ALL=C so each ${s:i:1} is a single BYTE; multi-byte UTF-8
# characters (accented / CJK project names) are emitted as their %XX byte
# sequence rather than a mangled single code unit.
_lm_urlencode() {
    local s="${1:-}" out="" c i byte
    local LC_ALL=C
    for (( i = 0; i < ${#s}; i++ )); do
        c="${s:i:1}"
        case "$c" in
            [a-zA-Z0-9._~-]) out+="$c" ;;
            *)
                # Mask to a single byte: printf "'$c" sign-extends bytes >127
                # to a huge negative value, so AND with 0xff before %02X.
                printf -v byte '%d' "'$c"
                out+="$(printf '%%%02X' "$(( byte & 0xff ))")"
                ;;
        esac
    done
    printf '%s' "$out"
}

# ===========================================================================
# STEP 6 — Detached background update check.
#   Runs the container's skills auto-update plus an image-digest freshness
#   check. Fully disowned (nohup + &, output redirected) so it can NEVER delay
#   steps 1-5. Any repair the user actually needs is handled inline above; this
#   is purely opportunistic maintenance.
# ===========================================================================
spawn_background_update_check() {
    # Run in a subshell, disowned, with all fd's redirected to the log so the
    # parent can exit without waiting on it.
    nohup bash -c '
        set +e
        CONTAINER_NAME="'"$CONTAINER_NAME"'"
        IMAGE="ghcr.io/sealmindset/claude-code-docker:latest"

        echo "[$(date "+%Y-%m-%dT%H:%M:%S")] background update check starting"

        # --- 1. Skills auto-update inside the running container -------------
        if command -v docker >/dev/null 2>&1 \
            && docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${CONTAINER_NAME}\$"; then

            # Locate auto-update.sh inside the image (SCRIPTS_DIR is set by the
            # entrypoint; fall back to a find if the env var is not exported to
            # exec sessions).
            updater="$(docker exec "$CONTAINER_NAME" bash -lc \
                "printf %s \"\${SCRIPTS_DIR:-}\"" 2>/dev/null)/auto-update.sh"
            if ! docker exec "$CONTAINER_NAME" test -f "$updater" 2>/dev/null; then
                updater="$(docker exec "$CONTAINER_NAME" bash -lc \
                    "find /opt /usr/local /home/coder -maxdepth 4 -name auto-update.sh 2>/dev/null | head -1" 2>/dev/null)"
            fi
            if [ -n "$updater" ] && docker exec "$CONTAINER_NAME" test -f "$updater" 2>/dev/null; then
                echo "[skills] running $updater"
                docker exec -u coder "$CONTAINER_NAME" bash "$updater" 2>&1 \
                    || echo "[skills] auto-update returned nonzero (ignored)"
            else
                echo "[skills] auto-update.sh not found in container (skipped)"
            fi
        else
            echo "[skills] container not running (skipped)"
        fi

        # --- 2. Image-digest freshness check --------------------------------
        # Compare the local image digest against the registry. This only logs
        # whether a newer image exists; it does NOT pull or restart anything so
        # the running session is never disrupted.
        if command -v docker >/dev/null 2>&1; then
            local_digest="$(docker image inspect "$IMAGE" \
                --format "{{index .RepoDigests 0}}" 2>/dev/null)"
            remote_digest="$(docker manifest inspect "$IMAGE" 2>/dev/null \
                | grep -m1 "\"digest\"" | sed -E "s/.*\"(sha256:[a-f0-9]+)\".*/\1/")"
            echo "[image] local:  ${local_digest:-<none>}"
            echo "[image] remote: ${remote_digest:-<unavailable>}"
            if [ -n "$local_digest" ] && [ -n "$remote_digest" ]; then
                case "$local_digest" in
                    *"$remote_digest"*) echo "[image] up to date" ;;
                    *) echo "[image] a newer image is available (run the installer to update)" ;;
                esac
            fi
        fi

        echo "[$(date "+%Y-%m-%dT%H:%M:%S")] background update check finished"
    ' >"$CCDW_UPDATE_LOG" 2>&1 &

    # Disown so the process is fully detached from this shell's job table.
    disown 2>/dev/null || true
    return 0
}

# ===========================================================================
# main
# ===========================================================================
# _already_up — true when CCDW is already running and reachable (docker present,
# the container is up, and the dashboard/ttyd/workshop ports respond).
_already_up() {
    command -v docker >/dev/null 2>&1 || return 1
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}\$" || return 1
    _mpl_ports_ready
}

main() {
    # Kick off the opportunistic background update check FIRST so it runs
    # concurrently with — and never delays — the interactive steps below.
    spawn_background_update_check

    # Fast path: CCDW never shut down and is healthy. Skip the VPN/Docker/auth
    # preflight entirely and go STRAIGHT to the "Keep working on" resume menu so
    # the user just picks a project. (AI sign-in, if needed, is handled inside
    # the workspace — it must never block the picker.)
    if _already_up; then
        step_provider_auth   # non-blocking: nudge to sign in if AI token expired
        step_open_workspace
        exit 0
    fi

    step_check_installed # 0
    step_vpn            # 1
    step_docker         # 2
    step_container      # 3
    step_provider_auth  # 4
    step_open_workspace # 5

    exit 0
}

main "$@"
