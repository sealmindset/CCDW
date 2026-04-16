#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Self-Healing Library
# Stateless diagnostic functions, remediation actions, backoff logic,
# telemetry logging, and shared state management.
#
# All functions prefixed sh_ to avoid collisions.
# Sourced by health-monitor.sh (never executed directly).
# =============================================================================

# ---------------------------------------------------------------------------
# Paths & Constants
# ---------------------------------------------------------------------------
SH_STATE_FILE="/tmp/.health-state.json"
SH_TELEMETRY_FILE="/home/coder/.claude/health-telemetry.jsonl"
SH_LOCK_FILE="/tmp/.health-monitor.lock"
SH_SCRIPTS_DIR="/opt/claude-code-docker/scripts"
SH_CONFIG_FILE="/opt/claude-code-docker/config/providers.yml"

SH_BACKOFF_MIN=5
SH_BACKOFF_MAX=300
SH_HEALTHY_INTERVAL=30
SH_TELEMETRY_MAX_LINES=1000
SH_TELEMETRY_TRIM_TO=500

# Restart tracking: per-service arrays
# Format: "service_name:count:window_start"
declare -A SH_RESTART_COUNTS
declare -A SH_RESTART_WINDOW_START
SH_MAX_RESTARTS=5
SH_RESTART_WINDOW=600  # 10 minutes

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
sh_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [health] $1"
}

# ---------------------------------------------------------------------------
# Telemetry
# ---------------------------------------------------------------------------
sh_telemetry_log() {
    local event_type="$1"
    local action="$2"
    local result="$3"
    local detail="${4:-}"

    local ts
    ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    local entry="{\"ts\":\"${ts}\",\"type\":\"${event_type}\",\"action\":\"${action}\",\"result\":\"${result}\""
    if [ -n "$detail" ]; then
        entry="${entry},\"detail\":\"${detail}\""
    fi
    entry="${entry}}"

    mkdir -p "$(dirname "$SH_TELEMETRY_FILE")"
    echo "$entry" >> "$SH_TELEMETRY_FILE"

    # Rotate if too large
    if [ -f "$SH_TELEMETRY_FILE" ]; then
        local line_count
        line_count=$(wc -l < "$SH_TELEMETRY_FILE" 2>/dev/null || echo 0)
        if [ "$line_count" -gt "$SH_TELEMETRY_MAX_LINES" ]; then
            local tmp="${SH_TELEMETRY_FILE}.tmp"
            tail -n "$SH_TELEMETRY_TRIM_TO" "$SH_TELEMETRY_FILE" > "$tmp"
            mv "$tmp" "$SH_TELEMETRY_FILE"
        fi
    fi
}

# ---------------------------------------------------------------------------
# State file writer
# ---------------------------------------------------------------------------
sh_write_state() {
    local status="$1"       # healthy | degraded | unhealthy
    local failure_type="$2" # e.g. "vpn_down", "" if healthy
    local message="$3"
    local services_json="$4"  # e.g. {"ttyd":"ok","code_server":"ok","welcome_server":"ok"}

    local ts
    ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    # Count recent failures in the last hour from telemetry
    local recent_failures=0
    if [ -f "$SH_TELEMETRY_FILE" ]; then
        local one_hour_ago
        one_hour_ago=$(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
                       date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "")
        if [ -n "$one_hour_ago" ]; then
            recent_failures=$(awk -v cutoff="$one_hour_ago" -F'"' '
                /"result":"fail"/ || /"result":"skipped"/ {
                    for(i=1;i<=NF;i++) if($i=="ts") { if($(i+2) >= cutoff) count++ }
                }
                END { print count+0 }
            ' "$SH_TELEMETRY_FILE" 2>/dev/null || echo 0)
        fi
    fi

    cat > "$SH_STATE_FILE" <<EOF
{
  "status": "${status}",
  "failure_type": "${failure_type}",
  "message": "${message}",
  "last_check": "${ts}",
  "recent_failures_1h": ${recent_failures},
  "services": ${services_json}
}
EOF
}

# ---------------------------------------------------------------------------
# State file reader (for other scripts to source)
# ---------------------------------------------------------------------------
sh_read_state() {
    if [ -f "$SH_STATE_FILE" ]; then
        cat "$SH_STATE_FILE"
    else
        echo '{"status":"unknown","failure_type":"","message":"Health monitor not yet started","last_check":"","recent_failures_1h":0,"services":{}}'
    fi
}

sh_read_state_field() {
    local field="$1"
    if [ -f "$SH_STATE_FILE" ]; then
        python3 -c "import json; print(json.load(open('$SH_STATE_FILE')).get('$field',''))" 2>/dev/null
    fi
}

# ---------------------------------------------------------------------------
# Exponential backoff with jitter
# ---------------------------------------------------------------------------
sh_calc_backoff() {
    local current_interval="$1"

    if [ "$current_interval" -le 0 ]; then
        current_interval=$SH_BACKOFF_MIN
    fi

    # Double the interval
    local next=$(( current_interval * 2 ))
    if [ "$next" -gt "$SH_BACKOFF_MAX" ]; then
        next=$SH_BACKOFF_MAX
    fi

    # Add jitter: +/- 20%
    local jitter_range=$(( next / 5 ))
    if [ "$jitter_range" -gt 0 ]; then
        local jitter=$(( RANDOM % (jitter_range * 2 + 1) - jitter_range ))
        next=$(( next + jitter ))
    fi

    # Clamp
    [ "$next" -lt "$SH_BACKOFF_MIN" ] && next=$SH_BACKOFF_MIN
    [ "$next" -gt "$SH_BACKOFF_MAX" ] && next=$SH_BACKOFF_MAX

    echo "$next"
}

# ---------------------------------------------------------------------------
# Restart rate limiter
# ---------------------------------------------------------------------------
sh_can_restart() {
    local service="$1"
    local now
    now=$(date +%s)

    local count=${SH_RESTART_COUNTS[$service]:-0}
    local window_start=${SH_RESTART_WINDOW_START[$service]:-0}

    # Reset window if enough time passed
    if [ $(( now - window_start )) -gt "$SH_RESTART_WINDOW" ]; then
        SH_RESTART_COUNTS[$service]=0
        SH_RESTART_WINDOW_START[$service]=$now
        count=0
    fi

    if [ "$count" -ge "$SH_MAX_RESTARTS" ]; then
        return 1  # rate limited
    fi

    SH_RESTART_COUNTS[$service]=$(( count + 1 ))
    if [ "$window_start" -eq 0 ]; then
        SH_RESTART_WINDOW_START[$service]=$now
    fi

    return 0
}

# ===========================================================================
# DIAGNOSTIC FUNCTIONS
# Layer 1: Infrastructure  |  Layer 2: Network  |  Layer 3: Auth  |  Layer 4: Services
# ===========================================================================

# ---------------------------------------------------------------------------
# Layer 1: Infrastructure
# ---------------------------------------------------------------------------
sh_check_dns() {
    getent hosts www.google.com >/dev/null 2>&1
}

sh_check_internet() {
    curl -s --connect-timeout 5 -o /dev/null https://www.google.com 2>/dev/null
}

sh_check_disk() {
    local avail_kb
    avail_kb=$(df -k /home/coder 2>/dev/null | tail -1 | awk '{print $4}')
    [ -n "$avail_kb" ] && [ "$avail_kb" -gt 524288 ]  # > 512MB
}

sh_get_disk_free_mb() {
    local avail_kb
    avail_kb=$(df -k /home/coder 2>/dev/null | tail -1 | awk '{print $4}')
    echo $(( ${avail_kb:-0} / 1024 ))
}

# ---------------------------------------------------------------------------
# Layer 2: Network (requires internet to be up)
# ---------------------------------------------------------------------------
sh_check_endpoint() {
    local endpoint="$1"
    [ -z "$endpoint" ] && return 0
    curl -s --connect-timeout 8 -o /dev/null "$endpoint" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Layer 3: Auth
# ---------------------------------------------------------------------------
sh_check_azure_token() {
    # Only relevant for Azure token auth (not API key)
    [ -z "$ANTHROPIC_FOUNDRY_BASE_URL" ] && return 0
    [ -n "$ANTHROPIC_FOUNDRY_API_KEY" ] && return 0

    local token_json
    token_json=$(az account get-access-token --resource https://cognitiveservices.azure.com 2>/dev/null)
    [ $? -ne 0 ] && return 1

    local expires_on
    expires_on=$(echo "$token_json" | grep -o '"expiresOn"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"expiresOn"[[:space:]]*:[[:space:]]*"//' | sed 's/"//')
    [ -z "$expires_on" ] && return 0  # can't parse but token obtained

    local expiry_epoch now_epoch
    expiry_epoch=$(date -d "$expires_on" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$expires_on" +%s 2>/dev/null)
    now_epoch=$(date +%s)

    [ -z "$expiry_epoch" ] && return 0  # can't parse, assume ok

    local remaining=$(( (expiry_epoch - now_epoch) / 60 ))
    [ "$remaining" -le 5 ]  && return 1  # expired or expiring in < 5 min

    return 0
}

sh_check_api_key() {
    # Only relevant for API key auth
    [ -z "$ANTHROPIC_FOUNDRY_API_KEY" ] && [ -z "$ANTHROPIC_API_KEY" ] && return 0

    # We don't actually validate the key on every cycle (too expensive).
    # Just check it's non-empty. Real validation happens on first use.
    return 0
}

# ---------------------------------------------------------------------------
# Layer 4: Services
# ---------------------------------------------------------------------------
sh_check_service() {
    local port="$1"
    curl -s --connect-timeout 3 -o /dev/null "http://127.0.0.1:${port}/" 2>/dev/null
}

sh_check_docker_socket() {
    [ -S /var/run/docker.sock ] && docker info >/dev/null 2>&1
}

# ===========================================================================
# ROOT CAUSE CLASSIFICATION
# Walks the decision tree top-down, returns the first failure found.
# Output: failure_type (empty string = healthy)
# ===========================================================================
sh_classify() {
    local svc_ttyd="ok" svc_cs="ok" svc_welcome="ok" svc_workshop="ok"

    # --- Layer 1: Infrastructure ---
    if ! sh_check_dns; then
        echo "dns_failure"
        return
    fi

    if ! sh_check_internet; then
        echo "internet_down"
        return
    fi

    if ! sh_check_disk; then
        echo "disk_full"
        return
    fi

    # --- Layer 2: Network ---
    if [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
        if ! sh_check_endpoint "$ANTHROPIC_FOUNDRY_BASE_URL"; then
            # Internet works but endpoint doesn't => VPN/network issue
            echo "vpn_down"
            return
        fi
    elif [ -n "$ANTHROPIC_API_KEY" ]; then
        if ! sh_check_endpoint "https://api.anthropic.com"; then
            echo "endpoint_unreachable"
            return
        fi
    fi

    # --- Layer 3: Auth ---
    if [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ] && [ -z "$ANTHROPIC_FOUNDRY_API_KEY" ]; then
        if ! sh_check_azure_token; then
            echo "azure_token_expired"
            return
        fi
    fi

    # --- Layer 4: Services ---
    # Double-check on failure to avoid false positives
    if ! sh_check_service 7681; then
        sleep 2
        if ! sh_check_service 7681; then
            echo "service_crashed:ttyd"
            return
        fi
    fi

    if ! sh_check_service 8080; then
        sleep 2
        if ! sh_check_service 8080; then
            echo "service_crashed:code_server"
            return
        fi
    fi

    if ! sh_check_service "${WELCOME_PORT:-3000}"; then
        sleep 2
        if ! sh_check_service "${WELCOME_PORT:-3000}"; then
            echo "service_crashed:welcome_server"
            return
        fi
    fi

    if ! sh_check_service "${WORKSHOP_PORT:-9200}"; then
        sleep 2
        if ! sh_check_service "${WORKSHOP_PORT:-9200}"; then
            echo "service_crashed:workshop"
            return
        fi
    fi

    # Docker socket (non-critical, just track)
    if ! sh_check_docker_socket; then
        echo "docker_socket_lost"
        return
    fi

    # All clear
    echo ""
}

# ===========================================================================
# SERVICE STATUS SNAPSHOT
# Returns JSON object with service statuses
# ===========================================================================
sh_service_status() {
    local ttyd="ok" cs="ok" welcome="ok" workshop="ok"

    sh_check_service 7681  || ttyd="down"
    sh_check_service 8080  || cs="down"
    sh_check_service "${WELCOME_PORT:-3000}" || welcome="down"
    sh_check_service "${WORKSHOP_PORT:-9200}" || workshop="down"

    echo "{\"ttyd\":\"${ttyd}\",\"code_server\":\"${cs}\",\"welcome_server\":\"${welcome}\",\"workshop\":\"${workshop}\"}"
}

# ===========================================================================
# REMEDIATION ACTIONS
# Each returns 0 on success, 1 on failure
# ===========================================================================

sh_remediate_azure_token() {
    sh_log "Attempting silent Azure token refresh..."

    # Try silent refresh (uses cached refresh token)
    local token_json
    token_json=$(az account get-access-token --resource https://cognitiveservices.azure.com 2>/dev/null)
    if [ $? -eq 0 ]; then
        sh_log "Azure token refreshed successfully."
        sh_telemetry_log "azure_token_expired" "silent_refresh" "success"
        return 0
    fi

    # Silent refresh failed -- mark for user
    sh_log "Silent refresh failed. User must re-authenticate."
    sh_telemetry_log "azure_token_expired" "silent_refresh" "fail" "user_action_required"
    return 1
}

sh_remediate_code_server() {
    if ! sh_can_restart "code_server"; then
        sh_log "code-server restart rate limited (${SH_MAX_RESTARTS} restarts in ${SH_RESTART_WINDOW}s window)."
        sh_telemetry_log "service_crashed" "restart_code_server" "skipped" "restart_limit"
        return 1
    fi

    sh_log "Restarting code-server..."

    # Kill stale processes
    pkill -f "code-server.*--bind-addr" 2>/dev/null || true
    sleep 2

    export XDG_CONFIG_HOME=/tmp/.config
    mkdir -p /tmp/.config 2>/dev/null

    local cs_auth="${CODE_SERVER_AUTH:-none}"

    code-server \
        --bind-addr 0.0.0.0:8080 \
        --auth "$cs_auth" \
        --config /tmp/.config/code-server/config.yaml \
        --disable-telemetry \
        --disable-update-check \
        /home/coder/Documents/GitHub &

    sleep 3

    if sh_check_service 8080; then
        sh_log "code-server restarted successfully."
        sh_telemetry_log "service_crashed" "restart_code_server" "success"
        return 0
    else
        sh_log "code-server restart may still be starting..."
        sh_telemetry_log "service_crashed" "restart_code_server" "fail" "still_starting"
        return 1
    fi
}

sh_remediate_welcome_server() {
    if ! sh_can_restart "welcome_server"; then
        sh_log "welcome-server restart rate limited."
        sh_telemetry_log "service_crashed" "restart_welcome_server" "skipped" "restart_limit"
        return 1
    fi

    sh_log "Restarting welcome-server..."

    pkill -f "welcome-server" 2>/dev/null || true
    sleep 1

    "$SH_SCRIPTS_DIR/welcome-server.sh" &

    sleep 2

    if sh_check_service "${WELCOME_PORT:-3000}"; then
        sh_log "welcome-server restarted successfully."
        sh_telemetry_log "service_crashed" "restart_welcome_server" "success"
        return 0
    else
        sh_telemetry_log "service_crashed" "restart_welcome_server" "fail"
        return 1
    fi
}

sh_remediate_workshop() {
    if ! sh_can_restart "workshop"; then
        sh_log "workshop restart rate limited."
        sh_telemetry_log "service_crashed" "restart_workshop" "skipped" "restart_limit"
        return 1
    fi

    sh_log "Restarting workshop..."

    pkill -f "workshop/server.js" 2>/dev/null || true
    sleep 1

    "$SH_SCRIPTS_DIR/workshop-server.sh" &

    sleep 2

    if sh_check_service "${WORKSHOP_PORT:-9200}"; then
        sh_log "workshop restarted successfully."
        sh_telemetry_log "service_crashed" "restart_workshop" "success"
        return 0
    else
        sh_telemetry_log "service_crashed" "restart_workshop" "fail"
        return 1
    fi
}

sh_remediate_disk() {
    sh_log "Attempting disk cleanup..."
    local freed=0

    # npm cache
    npm cache clean --force 2>/dev/null && freed=1

    # Old JSONL telemetry/session files > 7 days
    find /home/coder/.claude -name "*.jsonl" -mtime +7 -delete 2>/dev/null && freed=1

    # /tmp files > 1 day (exclude our state/lock files)
    find /tmp -type f -mtime +1 \
        ! -name ".health-state.json" \
        ! -name ".health-monitor.lock" \
        -delete 2>/dev/null && freed=1

    if sh_check_disk; then
        sh_log "Disk cleanup freed enough space."
        sh_telemetry_log "disk_full" "cleanup" "success" "freed_space"
        return 0
    else
        sh_log "Disk still critically low after cleanup."
        sh_telemetry_log "disk_full" "cleanup" "fail" "still_low"
        return 1
    fi
}

# ===========================================================================
# MASTER REMEDIATION DISPATCHER
# Takes a failure_type, attempts auto-fix if possible.
# Returns 0 if fixed, 1 if user action needed.
# ===========================================================================
sh_remediate() {
    local failure_type="$1"

    case "$failure_type" in
        azure_token_expired)
            sh_remediate_azure_token
            return $?
            ;;
        service_crashed:code_server)
            sh_remediate_code_server
            return $?
            ;;
        service_crashed:welcome_server)
            sh_remediate_welcome_server
            return $?
            ;;
        service_crashed:workshop)
            sh_remediate_workshop
            return $?
            ;;
        disk_full)
            sh_remediate_disk
            return $?
            ;;
        service_crashed:ttyd)
            # ttyd is PID 1 -- can't restart from inside
            sh_log "ttyd is down. Container may need restart."
            sh_telemetry_log "service_crashed" "ttyd" "fail" "pid1_cannot_restart"
            return 1
            ;;
        *)
            # Not auto-fixable: dns_failure, internet_down, vpn_down,
            # endpoint_unreachable, api_key_invalid, docker_socket_lost
            sh_telemetry_log "$failure_type" "none" "fail" "user_action_required"
            return 1
            ;;
    esac
}

# ===========================================================================
# HUMAN-READABLE MESSAGES
# ===========================================================================
sh_failure_message() {
    local failure_type="$1"

    case "$failure_type" in
        dns_failure)
            echo "DNS resolution failed. Check network connection."
            ;;
        internet_down)
            echo "No internet connectivity. Check network or VPN."
            ;;
        disk_full)
            echo "Disk space critically low (< 512MB free)."
            ;;
        vpn_down)
            echo "VPN appears disconnected. Internet works but AI endpoint is unreachable."
            ;;
        endpoint_unreachable)
            echo "AI provider endpoint is unreachable."
            ;;
        azure_token_expired)
            echo "Azure token expired. Run 'login' to re-authenticate."
            ;;
        api_key_invalid)
            echo "API key is invalid or rejected."
            ;;
        service_crashed:ttyd)
            echo "Web terminal (ttyd) is not responding. Container may need restart."
            ;;
        service_crashed:code_server)
            echo "VS Code (code-server) crashed. Auto-restart attempted."
            ;;
        service_crashed:welcome_server)
            echo "Welcome page server crashed. Auto-restart attempted."
            ;;
        service_crashed:workshop)
            echo "Workshop server crashed. Auto-restart attempted."
            ;;
        docker_socket_lost)
            echo "Docker socket is not accessible."
            ;;
        "")
            echo "All systems operational."
            ;;
        *)
            echo "Unknown issue: ${failure_type}"
            ;;
    esac
}

# ===========================================================================
# STATUS CLASSIFICATION
# Maps failure types to overall status levels
# ===========================================================================
sh_failure_status() {
    local failure_type="$1"

    case "$failure_type" in
        "")
            echo "healthy"
            ;;
        docker_socket_lost|service_crashed:welcome_server|service_crashed:workshop)
            echo "degraded"
            ;;
        *)
            echo "unhealthy"
            ;;
    esac
}
