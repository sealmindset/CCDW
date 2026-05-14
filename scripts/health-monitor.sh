#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Health Monitor Daemon
# Central self-healing daemon that replaces watchdog.sh + token-monitor.sh.
#
# - Singleton (PID lock file)
# - Walks the root-cause classification tree each cycle
# - Auto-remediates fixable failures (token refresh, service restart, disk cleanup)
# - Writes shared state file read by welcome-server, shell-init, healthcheck
# - Logs telemetry to JSONL for doctor.sh and /api/health
# - Exponential backoff on failure, fixed 30s interval when healthy
# =============================================================================

# Note: no set -e -- daemon must be fault-tolerant and keep running
set -u

SCRIPTS_DIR="/opt/claude-code-docker/scripts"

# Source the self-healing library
source "$SCRIPTS_DIR/self-heal-lib.sh"

# ---------------------------------------------------------------------------
# Singleton lock
# ---------------------------------------------------------------------------
if [ -f "$SH_LOCK_FILE" ]; then
    EXISTING_PID=$(cat "$SH_LOCK_FILE" 2>/dev/null)
    if [ -n "$EXISTING_PID" ] && kill -0 "$EXISTING_PID" 2>/dev/null; then
        sh_log "Health monitor already running (PID $EXISTING_PID). Exiting."
        exit 0
    fi
    # Stale lock file -- remove it
    rm -f "$SH_LOCK_FILE"
fi

echo $$ > "$SH_LOCK_FILE"

cleanup() {
    rm -f "$SH_LOCK_FILE"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Initial state
# ---------------------------------------------------------------------------
CURRENT_INTERVAL=$SH_HEALTHY_INTERVAL
CONSECUTIVE_FAILURES=0
LAST_FAILURE_TYPE=""

sh_log "Health monitor started (PID $$). Checking every ${CURRENT_INTERVAL}s."

# Write initial state
SERVICES=$(sh_service_status)
sh_write_state "healthy" "" "Starting up..." "$SERVICES"

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
while true; do
    sleep "$CURRENT_INTERVAL"

    # --- Classify root cause ---
    FAILURE_TYPE=$(sh_classify)
    SERVICES=$(sh_service_status)

    if [ -z "$FAILURE_TYPE" ]; then
        # === HEALTHY ===
        if [ "$CONSECUTIVE_FAILURES" -gt 0 ]; then
            sh_log "Recovered after ${CONSECUTIVE_FAILURES} failure cycles. Back to healthy."
            sh_telemetry_log "recovery" "auto" "success" "after_${CONSECUTIVE_FAILURES}_cycles"
        fi

        CONSECUTIVE_FAILURES=0
        CURRENT_INTERVAL=$SH_HEALTHY_INTERVAL
        LAST_FAILURE_TYPE=""

        sh_write_state "healthy" "" "All systems operational." "$SERVICES"

        # Auto-backup .claude.json into the persistent volume (every healthy cycle)
        CLAUDE_JSON="/home/coder/.claude.json"
        BACKUP_DIR="/home/coder/.claude/backups"
        if [ -f "$CLAUDE_JSON" ]; then
            mkdir -p "$BACKUP_DIR"
            LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/.claude.json.backup.* 2>/dev/null | head -1)
            if [ -z "$LATEST_BACKUP" ] || ! diff -q "$CLAUDE_JSON" "$LATEST_BACKUP" &>/dev/null; then
                cp "$CLAUDE_JSON" "$BACKUP_DIR/.claude.json.backup.$(date +%Y%m%d-%H%M%S)"
                # Keep only last 5 backups
                ls -t "$BACKUP_DIR"/.claude.json.backup.* 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null
            fi
        fi
    else
        # === FAILURE DETECTED ===
        CONSECUTIVE_FAILURES=$(( CONSECUTIVE_FAILURES + 1 ))
        MESSAGE=$(sh_failure_message "$FAILURE_TYPE")
        STATUS=$(sh_failure_status "$FAILURE_TYPE")

        sh_log "Failure detected: ${FAILURE_TYPE} -- ${MESSAGE}"

        # Attempt remediation
        REMEDIATED=0
        if sh_remediate "$FAILURE_TYPE"; then
            REMEDIATED=1
            # Re-check after remediation
            sleep 2
            FAILURE_TYPE=$(sh_classify)
            SERVICES=$(sh_service_status)

            if [ -z "$FAILURE_TYPE" ]; then
                sh_log "Remediation successful. System recovered."
                sh_write_state "healthy" "" "All systems operational." "$SERVICES"
                CONSECUTIVE_FAILURES=0
                CURRENT_INTERVAL=$SH_HEALTHY_INTERVAL
                LAST_FAILURE_TYPE=""
                continue
            else
                # Remediation didn't fully fix it
                MESSAGE=$(sh_failure_message "$FAILURE_TYPE")
                STATUS=$(sh_failure_status "$FAILURE_TYPE")
                sh_log "Remediation attempted but issue persists: ${FAILURE_TYPE}"
            fi
        fi

        sh_write_state "$STATUS" "$FAILURE_TYPE" "$MESSAGE" "$SERVICES"

        # Only log telemetry on new failure type or first occurrence
        if [ "$FAILURE_TYPE" != "$LAST_FAILURE_TYPE" ]; then
            if [ "$REMEDIATED" -eq 0 ]; then
                sh_telemetry_log "$FAILURE_TYPE" "detected" "fail" "$MESSAGE"
            fi
        fi

        LAST_FAILURE_TYPE="$FAILURE_TYPE"

        # Exponential backoff
        CURRENT_INTERVAL=$(sh_calc_backoff "$CURRENT_INTERVAL")
        sh_log "Next check in ${CURRENT_INTERVAL}s (backoff, failure #${CONSECUTIVE_FAILURES})."
    fi
done
