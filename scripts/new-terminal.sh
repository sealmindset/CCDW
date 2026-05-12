#!/usr/bin/env bash
# =============================================================================
# New Terminal — creates a new tmux window in the main session
# Used by the second ttyd instance (port 7682) so each browser tab
# gets its own independent terminal window.
# =============================================================================

SCRIPTS_DIR="/opt/claude-code-docker/scripts"
SESSION="main"
WINDOW_ID="t$(date +%s%N | cut -c1-13)"

# Ensure main session exists (race: user might open this before main ttyd starts)
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    exec tmux new-session -s "$SESSION" "bash --init-file $SCRIPTS_DIR/shell-init.sh"
fi

# Create a new window in the existing session and attach to it
tmux new-window -t "$SESSION" -n "$WINDOW_ID" "bash --init-file $SCRIPTS_DIR/shell-init.sh"
exec tmux attach-session -t "$SESSION"
