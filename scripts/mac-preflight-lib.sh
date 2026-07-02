# shellcheck shell=bash
# =============================================================================
# mac-preflight-lib.sh — sourceable macOS host-side preflight library
#
# This library is meant to be SOURCED (not executed) by the .app launcher and
# by the installer so both share one implementation of the host-side checks.
# All user-facing UI is delivered via osascript dialogs/notifications so that
# nothing needs a visible Terminal window when invoked from a .app bundle.
#
# IMPORTANT (set -e safety):
#   Do NOT put 'set -e' in this file — it is sourced into other scripts.
#   Every function below guards commands that may fail (|| true, captured $?,
#   'if cmd; then', &>/dev/null) so a caller running 'set -euo pipefail' is
#   never killed by a nonzero exit from an internal probe. All variables are
#   quoted. The only intentional nonzero returns are the documented function
#   return codes (used by callers as booleans), never a stray command failure.
#
# Configuration (override before sourcing, or export in the caller):
#   CCDW_REPO_DIR   Absolute path to the CCDW repo (where .env / install.command
#                   live). Defaults to the parent dir of this library's dir.
#   CONTAINER_NAME  Name of the Docker container. Defaults to "claude-code".
#
# -----------------------------------------------------------------------------
# Functions provided:
#
#   UI helpers (osascript-based):
#     ui_notify TITLE MESSAGE
#         Non-blocking macOS notification banner. Always returns 0.
#     ui_info TITLE MESSAGE
#         Blocking dialog with a single "OK" button. Returns 0.
#     ui_block TITLE MESSAGE
#         Blocking dialog with buttons {"Quit","Retry"}, default "Retry".
#         Returns 0 if the user clicked Retry, 1 if the user clicked Quit
#         (or dismissed the dialog). Never propagates osascript's nonzero exit.
#
#   Preflight checks / actions (logic reused from setup-claude-mac.command
#   and install.command — see inline references):
#     check_vpn
#         0 if the Sleep Number corporate endpoint is reachable, else 1.
#     ensure_docker_engine
#         Detect Rancher Desktop / Docker Desktop / Colima, apply the Lima
#         long-username socket fix, launch the app if the daemon is down, and
#         poll 'docker info' until ready (~90s bound). 0 when ready, 1 on timeout.
#     ensure_container
#         Ensure the 'claude-code' container is running (start it if stopped,
#         'docker run' it from install.command's exact args if absent), then
#         poll the dashboard/ttyd/workshop ports until responding. 0/1.
#     provider_from_env
#         Echo the configured provider slug (foundry|bedrock|anthropic|claude)
#         read from CCDW_REPO_DIR/.env, or empty string if none configured.
#     check_provider_auth PROVIDER
#         0 if PROVIDER is already authenticated, 1 if the user must sign in.
#         Probes inside the running container via 'docker exec'.
#     last_project
#         Echo the last-worked project directory NAME (relative to ~/Documents),
#         or empty string if none can be determined.
# =============================================================================

# ---------------------------------------------------------------------------
# Resolve repo dir and container name (overridable by the caller)
# ---------------------------------------------------------------------------
if [ -z "${CCDW_REPO_DIR:-}" ]; then
    # Directory of this library file, then its parent (the repo root).
    _mpl_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
    CCDW_REPO_DIR="$(cd "${_mpl_lib_dir}/.." 2>/dev/null && pwd)"
    unset _mpl_lib_dir
fi
: "${CONTAINER_NAME:=claude-code}"

# Corporate reachability endpoint — copied verbatim from
# setup-claude-mac.command:198 (do not change without updating that file too).
: "${CCDW_VPN_URL:=https://snapistg-scus.azure.sleepnumber.com}"

# ---------------------------------------------------------------------------
# UI helpers (osascript). No Terminal window required.
# ---------------------------------------------------------------------------

# _mpl_esc STRING — escape a string for embedding inside an AppleScript
# double-quoted literal (backslash and double-quote).
_mpl_esc() {
    local s="${1:-}"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

# _mpl_tty — true when stdout is a real terminal (the .command runs in a visible
# Terminal window). In that case all UI is plain text + `read`, which is 100%
# reliable and visible — no osascript / GUI-dialog dependency. Only when there
# is NO terminal (e.g. a background .app) do we fall back to osascript.
_mpl_tty() { [ -t 1 ]; }

# ui_notify TITLE MESSAGE — non-blocking progress line. Always returns 0.
ui_notify() {
    if _mpl_tty; then
        printf '  %s\n' "${2:-}"
        return 0
    fi
    local title msg
    title="$(_mpl_esc "${1:-Claude Code}")"
    msg="$(_mpl_esc "${2:-}")"
    osascript -e "display notification \"${msg}\" with title \"${title}\"" >/dev/null 2>&1 || true
    return 0
}

# ui_info TITLE MESSAGE — informational message. Returns 0.
ui_info() {
    if _mpl_tty; then
        printf '\n  %s\n\n' "${2:-}"
        return 0
    fi
    local title msg
    title="$(_mpl_esc "${1:-Claude Code}")"
    msg="$(_mpl_esc "${2:-}")"
    osascript -e "display dialog \"${msg}\" with title \"${title}\" buttons {\"OK\"} default button \"OK\"" >/dev/null 2>&1 || true
    return 0
}

# ui_block TITLE MESSAGE — blocking "fix it, then continue" prompt.
# Returns 0 to RETRY the step, 1 to QUIT. In a terminal it prints the message
# and waits for Return (retry) or 'q' (quit); `read` is guarded so an EOF can't
# abort a 'set -e' caller. With no terminal it uses an osascript Quit/Retry
# dialog (status captured so cancel never kills the caller).
ui_block() {
    if _mpl_tty; then
        printf '\n  %s\n' "${2:-}"
        local ans=""
        read -r -p "  Press Return to try again, or type q + Return to quit: " ans 2>/dev/null || ans="q"
        case "$ans" in
            q|Q|quit|Quit|QUIT) return 1 ;;
            *) return 0 ;;
        esac
    fi
    local title msg btn rc
    title="$(_mpl_esc "${1:-Claude Code}")"
    msg="$(_mpl_esc "${2:-}")"
    btn="$(osascript -e "button returned of (display dialog \"${msg}\" with title \"${title}\" buttons {\"Quit\",\"Retry\"} default button \"Retry\")" 2>/dev/null)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        return 1
    fi
    if [ "$btn" = "Retry" ]; then
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Internal: docker readiness probe with a 10s watchdog.
# Copied verbatim from setup-claude-mac.command:445-454 / install.command:469-478.
# ---------------------------------------------------------------------------
_mpl_docker_ready() {
    docker info &>/dev/null 2>&1 &
    local pid=$!
    ( sleep 10 && kill "$pid" 2>/dev/null ) &
    local watchdog=$!
    wait "$pid" 2>/dev/null
    local rc=$?
    kill "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null
    return "$rc"
}

# ---------------------------------------------------------------------------
# check_vpn — 0 if the corporate endpoint is reachable, else 1.
# Reachable == HTTP status code is not "000" (any response = reachable),
# matching setup-claude-mac.command:198.
# ---------------------------------------------------------------------------
check_vpn() {
    local code
    code=$(curl -so /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 15 "$CCDW_VPN_URL" 2>/dev/null || true)
    # Fail closed: empty output (curl missing/errored) or "000" (no response)
    # both mean unreachable. Any real HTTP status = reachable.
    case "$code" in
        ""|000) return 1 ;;
        *)      return 0 ;;
    esac
}

# ---------------------------------------------------------------------------
# _mpl_lima_fix — apply the Lima long-username socket-path fix.
# Copied from setup-claude-mac.command:98-134. Safe to call unconditionally:
# it only acts when the projected socket path would exceed UNIX_PATH_MAX (104)
# and the lima dir is not already a symlink. Returns 0 always.
# ---------------------------------------------------------------------------
_mpl_lima_fix() {
    local lima_original lima_short sock_test rcfile
    lima_original="$HOME/Library/Application Support/rancher-desktop/lima"
    lima_short="$HOME/.rd-lima"
    sock_test="$lima_original/0/ssh.sock.1234567890123456"

    if [ "${#sock_test}" -gt 104 ] && [ ! -L "$lima_original" ]; then
        if pgrep -q "Rancher Desktop"; then
            osascript -e 'quit app "Rancher Desktop"' 2>/dev/null || true
            sleep 3
        fi

        if [ -d "$lima_original" ]; then
            mv "$lima_original" "$lima_short" 2>/dev/null || true
        else
            mkdir -p "$lima_short" 2>/dev/null || true
            mkdir -p "$(dirname "$lima_original")" 2>/dev/null || true
        fi
        ln -s "$lima_short" "$lima_original" 2>/dev/null || true

        # Persist LIMA_HOME in shell profiles (idempotent).
        for rcfile in "$HOME/.zshrc" "$HOME/.bashrc"; do
            if [ -f "$rcfile" ] && grep -qF "LIMA_HOME" "$rcfile" 2>/dev/null; then
                continue
            fi
            {
                echo ''
                echo '# Fix Rancher Desktop Lima socket path length (UNIX_PATH_MAX=104)'
                echo 'export LIMA_HOME="$HOME/.rd-lima"'
            } >> "$rcfile" 2>/dev/null || true
        done

        export LIMA_HOME="$lima_short"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# _mpl_find_engine_app — echo the path to a launchable Docker-engine .app
# (Rancher Desktop or Docker Desktop). Empty if only Colima / CLI is present.
# Extends setup-claude-mac.command:241-245 (Rancher) with Docker Desktop.
# ---------------------------------------------------------------------------
_mpl_find_engine_app() {
    if [ -d "/Applications/Rancher Desktop.app" ]; then
        printf '%s' "/Applications/Rancher Desktop.app"
    elif [ -d "$HOME/Applications/Rancher Desktop.app" ]; then
        printf '%s' "$HOME/Applications/Rancher Desktop.app"
    elif [ -d "/Applications/Docker.app" ]; then
        printf '%s' "/Applications/Docker.app"
    elif [ -d "$HOME/Applications/Docker.app" ]; then
        printf '%s' "$HOME/Applications/Docker.app"
    fi
}

# ---------------------------------------------------------------------------
# ensure_docker_engine — make sure the Docker daemon is up.
# Detect engine, apply Lima fix, launch the app if down, poll ~90s.
# 0 when docker is ready, 1 on timeout / no engine found.
# ---------------------------------------------------------------------------
ensure_docker_engine() {
    # Rancher Desktop places the docker CLI in ~/.rd/bin (setup line 94-96).
    if [ -d "$HOME/.rd/bin" ]; then
        export PATH="$HOME/.rd/bin:$PATH"
    fi

    # Already up? Fast path.
    if command -v docker &>/dev/null && _mpl_docker_ready; then
        return 0
    fi

    # Apply the long-username Lima socket fix before launching Rancher.
    _mpl_lima_fix

    # Colima has no .app to open; try to start it via CLI if present.
    if ! _mpl_find_engine_app >/dev/null && command -v colima &>/dev/null; then
        colima start &>/dev/null || true
    fi

    local engine_app
    engine_app="$(_mpl_find_engine_app)"
    if [ -n "$engine_app" ] && ! _mpl_docker_ready; then
        # Remove quarantine if downloaded directly (setup line 461) then launch.
        xattr -r -d com.apple.quarantine "$engine_app" 2>/dev/null || true
        open -a "$engine_app" 2>/dev/null || true
    fi

    # Poll until docker responds. ~90s bound: 18 iterations x 5s.
    local i
    for i in $(seq 1 18); do
        if ! command -v docker &>/dev/null && [ -f "$HOME/.rd/bin/docker" ]; then
            export PATH="$HOME/.rd/bin:$PATH"
        fi
        if command -v docker &>/dev/null && _mpl_docker_ready; then
            return 0
        fi
        sleep 5
    done

    return 1
}

# ---------------------------------------------------------------------------
# _mpl_load_ports — populate WELCOME_PORT / TTYD_PORT / TTYD_NEW_PORT /
# CODE_SERVER_PORT / CHAT_PORT / WORKSHOP_PORT from .env (only if the caller
# has not already exported them), applying the same defaults the container
# publishes. This keeps the readiness probe, the docker run mapping, and the
# launcher's URLs all pointed at the ports the user actually configured
# (.env.example advertises these as editable on a port conflict).
# ---------------------------------------------------------------------------
_mpl_load_ports() {
    local env_file="$CCDW_REPO_DIR/.env" key val
    if [ -f "$env_file" ]; then
        for key in WELCOME_PORT TTYD_PORT TTYD_NEW_PORT CODE_SERVER_PORT CHAT_PORT WORKSHOP_PORT; do
            # Only fill in vars the caller has not already set.
            if [ -z "${!key:-}" ]; then
                val=$(grep -E "^${key}=" "$env_file" 2>/dev/null | head -1 | sed "s/^${key}=//" | tr -d '\r' || true)
                # if/then (not `[ ] && export`): under bash 3.2's strict set -e a
                # bare `false && cmd` aborts the whole (sourced) script.
                if [ -n "$val" ]; then export "$key=$val"; fi
            fi
        done
    fi
    : "${WELCOME_PORT:=3000}"
    : "${TTYD_PORT:=7681}"
    : "${TTYD_NEW_PORT:=7682}"
    : "${CODE_SERVER_PORT:=8080}"
    : "${CHAT_PORT:=3002}"
    : "${WORKSHOP_PORT:=9200}"
}

# ---------------------------------------------------------------------------
# _mpl_ports_ready — 0 if all dashboard ports respond over HTTP, else 1.
# Polls the SAME host ports _mpl_docker_run publishes (honoring .env overrides).
# ---------------------------------------------------------------------------
_mpl_ports_ready() {
    _mpl_load_ports
    local p
    for p in "$WELCOME_PORT" "$TTYD_PORT" "$WORKSHOP_PORT"; do
        curl -s -o /dev/null --connect-timeout 2 "http://localhost:$p" 2>/dev/null || return 1
    done
    return 0
}

# ---------------------------------------------------------------------------
# _mpl_image_ref — echo the canonical image reference used by install.command.
# ---------------------------------------------------------------------------
_mpl_image_ref() {
    printf 'ghcr.io/sealmindset/claude-code-docker:latest'
}

# ---------------------------------------------------------------------------
# _mpl_registry_mirror — echo the trimmed REGISTRY_MIRROR host from .env (no
# trailing slash), or empty string. Mirrors install.command:772-778.
# ---------------------------------------------------------------------------
_mpl_registry_mirror() {
    local env_file="$CCDW_REPO_DIR/.env" mirror=""
    if [ -f "$env_file" ]; then
        mirror=$(grep -E "^REGISTRY_MIRROR=" "$env_file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r' || true)
    fi
    # Strip any trailing slash so callers can compose "$mirror/image".
    mirror="${mirror%/}"
    printf '%s' "$mirror"
}

# ---------------------------------------------------------------------------
# _mpl_ensure_image — make sure the claude-code image is present locally.
# If it is already inspectable, returns 0 immediately. Otherwise attempts a
# tiered pull (mirrors install.command:831-862): first the ACR mirror if
# REGISTRY_MIRROR is set in .env, then the public GHCR image. Returns 0 if the
# image is present afterwards, nonzero if every attempt failed.
# ---------------------------------------------------------------------------
_mpl_ensure_image() {
    local image mirror acr_image
    image="$(_mpl_image_ref)"

    # Already present — nothing to do.
    if docker image inspect "$image" &>/dev/null; then
        return 0
    fi

    ui_notify "Claude Code" "Downloading the Claude Code image (first run may take a few minutes)..."

    # Tier 1: internal ACR mirror (bypasses Zscaler on the corporate network).
    mirror="$(_mpl_registry_mirror)"
    if [ -n "$mirror" ]; then
        acr_image="${mirror}/claude-code-docker:latest"
        if docker pull "$acr_image" &>/dev/null; then
            # Retag to the canonical name so the run args stay unchanged.
            docker tag "$acr_image" "$image" &>/dev/null || true
            if docker image inspect "$image" &>/dev/null; then
                return 0
            fi
        fi
    fi

    # Tier 2: public GHCR (direct; may be blocked by SSL inspection).
    if docker pull "$image" &>/dev/null; then
        if docker image inspect "$image" &>/dev/null; then
            return 0
        fi
    fi

    # Last check: maybe another process pulled it concurrently.
    if docker image inspect "$image" &>/dev/null; then
        return 0
    fi

    return 1
}

# ---------------------------------------------------------------------------
# _mpl_docker_run — start the claude-code container using EXACTLY the same
# image / ports / mounts / flags as install.command:955-981. Sourced from that
# file's argument list so the two stay in sync.
#
# Returns:
#   0  container started
#   2  port conflict ("already allocated"/"address already in use" in the log);
#      the partial container has been removed so a retry can recreate cleanly.
#   1  any other failure (image missing/unpullable, or generic docker error);
#      the partial container has been removed.
#
# Requires (built here to mirror install.command:532-549, 902, 907-920):
#   ENV_FILE, PROJECTS_DIR, AZURE_DIR, AWS_DIR, KUBE_DIR, HOST_GITCONFIG,
#   DOCKER_GID, HOST_ACCESS_ARGS[], EXTRA_VOL_ARGS[]
# ---------------------------------------------------------------------------
_mpl_docker_run() {
    local ENV_FILE PROJECTS_DIR AZURE_DIR AWS_DIR KUBE_DIR HOST_GITCONFIG DOCKER_GID
    ENV_FILE="$CCDW_REPO_DIR/.env"
    PROJECTS_DIR="$HOME/Documents"
    AZURE_DIR="$HOME/.azure"
    AWS_DIR="$HOME/.aws"
    KUBE_DIR="$HOME/.kube"
    HOST_GITCONFIG="$HOME/.gitconfig"

    mkdir -p "$PROJECTS_DIR" "$AZURE_DIR" "$AWS_DIR" "$KUBE_DIR" 2>/dev/null || true

    # Make sure the image exists locally (pull with ACR->GHCR fallback). If it
    # cannot be obtained, there is nothing to run — surface a generic failure.
    if ! _mpl_ensure_image; then
        # Nothing partial was created here, but be defensive for a retry.
        docker rm -f "$CONTAINER_NAME" &>/dev/null || true
        return 1
    fi

    # Resolve host ports from .env so the published mapping matches the probe.
    _mpl_load_ports

    # Docker socket GID (install.command:902).
    DOCKER_GID=$(stat -f '%g' /var/run/docker.sock 2>/dev/null || stat -c '%g' /var/run/docker.sock 2>/dev/null || echo "0")

    # Host-access args (install.command:545-549).
    local HOST_ACCESS_ARGS=(--add-host host.docker.internal:host-gateway -v "$KUBE_DIR:/home/coder/.kube")
    if [ -f "$HOST_GITCONFIG" ]; then
        HOST_ACCESS_ARGS+=(-v "$HOST_GITCONFIG:/home/coder/.host-gitconfig:ro")
    fi

    # Extra drive mounts from EXTRA_MOUNTS in .env (install.command:907-920).
    local EXTRA_VOL_ARGS=()
    if [ -f "$ENV_FILE" ]; then
        local extra_raw epath ename
        extra_raw=$(grep '^EXTRA_MOUNTS=' "$ENV_FILE" 2>/dev/null | head -1 | sed 's/^EXTRA_MOUNTS=//' || true)
        if [ -n "$extra_raw" ]; then
            local extra_paths
            IFS='|' read -ra extra_paths <<< "$extra_raw"
            for epath in ${extra_paths[@]+"${extra_paths[@]}"}; do
                if [ -d "$epath" ]; then
                    ename=$(basename "$epath")
                    EXTRA_VOL_ARGS+=(-v "$epath:/home/coder/Drives/$ename")
                fi
            done
        fi
    fi

    # Argument list byte-for-byte matching install.command:955-981.
    # Capture the exit status (do not let it abort a set -e caller).
    local run_rc=0
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        --group-add "$DOCKER_GID" \
        --env-file "$ENV_FILE" \
        -p "${WELCOME_PORT:-3000}:3000" \
        -p "${TTYD_PORT:-7681}:7681" \
        -p "${TTYD_NEW_PORT:-7682}:7682" \
        -p "${CODE_SERVER_PORT:-8080}:8080" \
        -p "${CHAT_PORT:-3002}:3002" \
        -p "${WORKSHOP_PORT:-9200}:9200" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "$PROJECTS_DIR:/home/coder/Documents" \
        -v "$HOME/Downloads:/home/coder/Downloads" \
        -v "$HOME/Desktop:/home/coder/Desktop" \
        -v "$AZURE_DIR:/home/coder/.azure" \
        -v "$AWS_DIR:/home/coder/.aws" \
        -v claude-code-data:/home/coder/.claude \
        -v claude-code-gh:/home/coder/.config/gh \
        -v claude-code-git-config:/home/coder/.gitconfig.d \
        -v claude-code-local:/home/coder/.local \
        -v claude-code-continue:/home/coder/.continue \
        -v claude-code-npm:/home/coder/.npm \
        -v claude-code-bash-history:/home/coder/.shell-persist \
        ${HOST_ACCESS_ARGS[@]+"${HOST_ACCESS_ARGS[@]}"} \
        ${EXTRA_VOL_ARGS[@]+"${EXTRA_VOL_ARGS[@]}"} \
        ghcr.io/sealmindset/claude-code-docker:latest >/tmp/claude-code-start.log 2>&1 || run_rc=$?

    if [ "$run_rc" -eq 0 ]; then
        return 0
    fi

    # docker run failed. Diagnose a port conflict from the captured log so the
    # caller can tell the user exactly which port to change in .env. grep is
    # guarded (|| true) so a no-match can never abort a set -e caller.
    local conflict=""
    if [ -f /tmp/claude-code-start.log ]; then
        conflict=$(grep -iE 'port is already allocated|address already in use|Bind for .* failed' /tmp/claude-code-start.log 2>/dev/null | head -1 || true)
    fi

    # Always remove the partially-created container so a Retry can recreate
    # cleanly (docker leaves a Created container behind on a bind failure).
    docker rm -f "$CONTAINER_NAME" &>/dev/null || true

    if [ -n "$conflict" ]; then
        return 2
    fi
    return 1
}

# ---------------------------------------------------------------------------
# _mpl_ports_match — 0 if the RUNNING container publishes the same three host
# ports we care about (WELCOME/TTYD/WORKSHOP) as the current .env, else 1.
# Guards every docker call so a probe failure can't abort a set -e caller; if
# the mapping cannot be read at all we conservatively report "match" (1 would
# force an unnecessary rebuild). Fix for stale-port containers.
# ---------------------------------------------------------------------------
_mpl_ports_match() {
    _mpl_load_ports
    local bindings p want got
    # {{json .HostConfig.PortBindings}} => e.g. {"3000/tcp":[{"HostIp":"","HostPort":"3000"}], ...}
    bindings=$(docker inspect -f '{{json .HostConfig.PortBindings}}' "$CONTAINER_NAME" 2>/dev/null || true)
    # If we couldn't read the bindings, don't force a rebuild on a guess.
    if [ -z "$bindings" ] || [ "$bindings" = "null" ]; then
        return 0
    fi
    # Container-side port -> desired host port (the run mapping above).
    for p in "3000:$WELCOME_PORT" "7681:$TTYD_PORT" "9200:$WORKSHOP_PORT"; do
        local cport="${p%%:*}"
        want="${p##*:}"
        # Pull the HostPort published for this container port out of the JSON.
        # A no-match leaves got empty; grep is guarded so pipefail can't abort.
        got=$(printf '%s' "$bindings" \
            | tr ',' '\n' \
            | grep -A2 "\"${cport}/tcp\"" 2>/dev/null \
            | grep -oE '"HostPort":"[0-9]+"' 2>/dev/null \
            | head -1 \
            | grep -oE '[0-9]+' 2>/dev/null || true)
        if [ -z "$got" ] || [ "$got" != "$want" ]; then
            return 1
        fi
    done
    return 0
}

# ---------------------------------------------------------------------------
# ensure_container — ensure the 'claude-code' container is running with the
# correct published ports, then poll the dashboard until it responds.
#
#   * running + ports match      -> poll ports.
#   * running + ports stale      -> rm -f, recreate, poll.
#   * exited/paused              -> docker start (rebuild on failure), poll.
#   * created/dead/other/absent  -> rm -f (if any), docker run, poll.
#
# If the poll never comes up, we distinguish a crash-loop (climbing RestartCount
# or unhealthy) and rebuild once rather than polling a doomed container.
#
# A rebuild (rm -f + recreate) is bounded to at most once per call. On a port
# conflict surfaced by _mpl_docker_run (status 2) we show a specific message
# naming the conflicting port and telling the user to change it in .env.
#
# Returns 0 when the dashboard ports respond, 1 otherwise.
# ---------------------------------------------------------------------------
ensure_container() {
    if ! command -v docker &>/dev/null; then
        return 1
    fi

    # _mpl_start_container: bring the container into a running state, choosing
    # start-vs-run from its actual state. Echoes nothing; returns:
    #   0 ok, 1 generic failure, 2 port conflict (message-worthy).
    local rebuilt=0

    _mpl_container_up() {
        local state rc=0
        state=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)
        case "$state" in
            running)
                # Already running: only trust it if the published ports match
                # the current .env. Otherwise rebuild so the URLs line up.
                if _mpl_ports_match; then
                    return 0
                fi
                ui_notify "Claude Code" "Reconfiguring Claude Code to use your current ports..."
                docker rm -f "$CONTAINER_NAME" &>/dev/null || true
                _mpl_docker_run; rc=$?
                return "$rc"
                ;;
            exited|paused)
                # A cleanly stopped/paused container can just be started.
                if docker start "$CONTAINER_NAME" &>/dev/null; then
                    return 0
                fi
                # Start failed (e.g. stale config) — rebuild from scratch.
                docker rm -f "$CONTAINER_NAME" &>/dev/null || true
                _mpl_docker_run; rc=$?
                return "$rc"
                ;;
            "")
                # No such container — create it.
                _mpl_docker_run; rc=$?
                return "$rc"
                ;;
            *)
                # created / dead / restarting / removing / anything else: a bare
                # 'docker start' can loop forever, so remove and recreate.
                docker rm -f "$CONTAINER_NAME" &>/dev/null || true
                _mpl_docker_run; rc=$?
                return "$rc"
                ;;
        esac
    }

    local rc
    _mpl_container_up; rc=$?
    if [ "$rc" -eq 2 ]; then
        ui_block "Port in use" "A required port is already used by another app. Open the .env file in the Claude Code folder, change the conflicting port (for example WELCOME_PORT, TTYD_PORT, or WORKSHOP_PORT), save it, then try again." || return 1
        # User chose Retry: fall through and poll (a fresh call will re-run).
        return 1
    elif [ "$rc" -ne 0 ]; then
        return 1
    fi
    # A recreate happened inside _mpl_container_up only for the stale-port and
    # non-startable states; treat any of those as our one allowed rebuild.
    case "$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)" in
        running) : ;;
        *) : ;;
    esac

    # Poll the dashboard until it responds. ~90s bound: 45 iterations x 2s
    # (matches install.command:1099-1106).
    local i
    for i in $(seq 1 45); do
        if _mpl_ports_ready; then
            return 0
        fi
        # Detect a crash-loop early: a container that keeps restarting (or is
        # marked unhealthy) will never serve the ports. Rebuild once, then keep
        # polling; if it still fails we fall out of the loop and return 1.
        if [ "$rebuilt" -eq 0 ]; then
            local restarts health
            restarts=$(docker inspect -f '{{.RestartCount}}' "$CONTAINER_NAME" 2>/dev/null || true)
            health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$CONTAINER_NAME" 2>/dev/null || true)
            if { [ -n "$restarts" ] && [ "$restarts" -gt 3 ] 2>/dev/null; } || [ "$health" = "unhealthy" ]; then
                ui_notify "Claude Code" "Restarting Claude Code..."
                docker rm -f "$CONTAINER_NAME" &>/dev/null || true
                rebuilt=1
                local rrc
                _mpl_docker_run; rrc=$?
                if [ "$rrc" -ne 0 ]; then
                    # Rebuild itself failed (port conflict or otherwise) — stop
                    # polling a container that no longer exists.
                    return 1
                fi
            fi
        fi
        sleep 2
    done

    return 1
}

# ---------------------------------------------------------------------------
# provider_from_env — echo foundry|bedrock|anthropic|claude, or "".
# Detection order/keys mirror install.command's doctor block (137-140) and the
# HAS_PROVIDER check (567-571).
# ---------------------------------------------------------------------------
provider_from_env() {
    local env_file="$CCDW_REPO_DIR/.env"
    [ -f "$env_file" ] || { printf ''; return 0; }

    # Explicit provider toggles first (mirrors install.command:137-140, which
    # keys Foundry off CLAUDE_CODE_USE_FOUNDRY=1 — NOT a bare base-URL line, so a
    # Bedrock/Anthropic user who left .env.example's pre-filled foundry base URL
    # in place is not mis-detected as foundry and trapped in an Azure sign-in loop).
    if grep -q "^CLAUDE_CODE_USE_BEDROCK=1" "$env_file" 2>/dev/null; then
        printf 'bedrock'
    elif grep -q "^CLAUDE_CODE_PROVIDER=claude" "$env_file" 2>/dev/null; then
        printf 'claude'
    elif grep -q "^CLAUDE_CODE_USE_FOUNDRY=1" "$env_file" 2>/dev/null; then
        printf 'foundry'
    elif _mpl_env_has_value "ANTHROPIC_API_KEY"; then
        printf 'anthropic'
    elif _mpl_env_has_value "ANTHROPIC_FOUNDRY_BASE_URL"; then
        # Last resort: a real base URL with no explicit toggle -> foundry.
        printf 'foundry'
    else
        printf ''
    fi
    return 0
}

# ---------------------------------------------------------------------------
# _mpl_env_has_value KEY — 0 if KEY has a non-empty value in .env, else 1.
# ---------------------------------------------------------------------------
_mpl_env_has_value() {
    local key="$1" env_file="$CCDW_REPO_DIR/.env" val
    [ -f "$env_file" ] || return 1
    val=$(grep -E "^${key}=" "$env_file" 2>/dev/null | head -1 | sed "s/^${key}=//" || true)
    [ -n "$val" ]
}

# ---------------------------------------------------------------------------
# check_provider_auth PROVIDER — 0 if authenticated, 1 if sign-in is required.
# Probes happen INSIDE the running container via 'docker exec', because that is
# where the credentials live (mounted ~/.azure, ~/.aws, and claude-code-data).
# ---------------------------------------------------------------------------
check_provider_auth() {
    local provider="${1:-}"

    case "$provider" in
        anthropic)
            # API-key only, no interactive login.
            return 0
            ;;
    esac

    if ! command -v docker &>/dev/null; then
        return 1
    fi
    # Auth probes require a running container.
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}\$"; then
        return 1
    fi

    case "$provider" in
        foundry)
            # A configured Foundry API key needs no interactive sign-in.
            if _mpl_env_has_value "ANTHROPIC_FOUNDRY_API_KEY"; then
                return 0
            fi
            # Consider authed only if az can actually MINT a Foundry token (a
            # bare 'az account show' can pass while the token is stale — which is
            # exactly what breaks the workspace). get-access-token also silently
            # refreshes from a cached refresh token, so no prompt when possible.
            if docker exec "$CONTAINER_NAME" az account get-access-token \
                --resource "${AZURE_FOUNDRY_RESOURCE:-https://cognitiveservices.azure.com}" &>/dev/null; then
                return 0
            fi
            return 1
            ;;
        bedrock)
            # Honor the user's configured AWS_PROFILE (.env / README advertise it
            # as editable); fall back to the default SSO profile name.
            local aws_profile
            aws_profile=$(grep -E "^AWS_PROFILE=" "$CCDW_REPO_DIR/.env" 2>/dev/null | head -1 | sed 's/^AWS_PROFILE=//' | tr -d '\r' || true)
            aws_profile="${aws_profile:-sso-bedrock-model-access}"
            if docker exec "$CONTAINER_NAME" aws sts get-caller-identity --profile "$aws_profile" &>/dev/null; then
                return 0
            fi
            return 1
            ;;
        claude)
            # 'claude auth status' prints loggedIn state; match true.
            if docker exec "$CONTAINER_NAME" claude auth status 2>/dev/null | grep -qi 'loggedIn.*true'; then
                return 0
            fi
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# last_project — echo the last-worked project dir NAME (relative to ~/Documents).
# Preference:
#   1. ~/Documents/.ccdw-last-project (if the referenced dir still exists)
#   2. newest ~/Documents/*/ containing .workshop-session.json
#   3. newest ~/Documents/*/ containing .make-it-state.md
# Echo empty string if nothing found. The workshop server writes the marker
# under the container's /home/coder/Documents, which maps to host ~/Documents.
# ---------------------------------------------------------------------------
last_project() {
    local docs="$HOME/Documents"
    local marker="$docs/.ccdw-last-project"
    [ -d "$docs" ] || { printf ''; return 0; }

    # 1. Explicit marker file.
    if [ -f "$marker" ]; then
        local saved
        saved=$(head -1 "$marker" 2>/dev/null | tr -d '\r\n')
        # Accept either a bare name or an absolute path; reduce to basename.
        saved="$(basename "$saved" 2>/dev/null)"
        if [ -n "$saved" ] && [ -d "$docs/$saved" ]; then
            printf '%s' "$saved"
            return 0
        fi
    fi

    # 2 & 3. Newest project by marker mtime. Prefer .workshop-session.json,
    # fall back to .make-it-state.md.
    local sentinel best best_mtime dir m mtime
    for sentinel in ".workshop-session.json" ".make-it-state.md"; do
        best=""
        best_mtime=0
        for dir in "$docs"/*/; do
            [ -d "$dir" ] || continue
            m="$dir$sentinel"
            [ -f "$m" ] || continue
            mtime=$(stat -f '%m' "$m" 2>/dev/null || stat -c '%Y' "$m" 2>/dev/null || echo 0)
            if [ "${mtime:-0}" -gt "$best_mtime" ] 2>/dev/null; then
                best_mtime="$mtime"
                best="$dir"
            fi
        done
        if [ -n "$best" ]; then
            best="${best%/}"
            printf '%s' "$(basename "$best")"
            return 0
        fi
    done

    printf ''
    return 0
}

# ---------------------------------------------------------------------------
# list_projects — echo the user's resumable project NAMES, one per line,
# NEWEST FIRST. A project is any dir under ~/Documents that has a
# .workshop-session.json or .make-it-state.md marker. Used to build the
# friendly "Keep working on: 1. X 2. Y ..." resume menu. Echoes nothing if
# there are no saved projects.
# ---------------------------------------------------------------------------
list_projects() {
    local docs="$HOME/Documents"
    [ -d "$docs" ] || return 0
    local dir name m mtime best_mtime
    local lines=()
    for dir in "$docs"/*/; do
        [ -d "$dir" ] || continue
        name="$(basename "${dir%/}")"
        best_mtime=0
        for m in "${dir}.workshop-session.json" "${dir}.make-it-state.md"; do
            [ -f "$m" ] || continue
            mtime=$(stat -f '%m' "$m" 2>/dev/null || stat -c '%Y' "$m" 2>/dev/null || echo 0)
            if [ "${mtime:-0}" -gt "$best_mtime" ] 2>/dev/null; then best_mtime="$mtime"; fi
        done
        [ "$best_mtime" -gt 0 ] 2>/dev/null || continue
        lines+=("$(printf '%s\t%s' "$best_mtime" "$name")")
    done
    [ "${#lines[@]}" -gt 0 ] 2>/dev/null || return 0
    # Sort by mtime desc, emit each unique name once, newest first.
    printf '%s\n' "${lines[@]}" | sort -rn -k1,1 | awk -F'\t' '!seen[$2]++ {print $2}'
    return 0
}
