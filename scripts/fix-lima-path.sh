#!/bin/bash
# fix-lima-path.sh — Fix Rancher Desktop Lima socket path length issue
# For macOS users whose username creates paths exceeding UNIX_PATH_MAX (104 chars)
#
# Usage: Open Terminal, then run:
#   bash ~/Downloads/fix-lima-path.sh

set -euo pipefail

LIMA_ORIGINAL="$HOME/Library/Application Support/rancher-desktop/lima"
LIMA_SHORT="$HOME/.rd-lima"
ZSHRC="$HOME/.zshrc"
BASHRC="$HOME/.bashrc"

echo "=== Rancher Desktop Lima Path Fix ==="
echo ""

# Check if fix is needed
SOCK_PATH="$LIMA_ORIGINAL/0/ssh.sock.1234567890123456"
SOCK_LEN=${#SOCK_PATH}
echo "Current socket path length: $SOCK_LEN (limit: 104)"

if [ "$SOCK_LEN" -le 104 ]; then
    echo "Path length OK — fix not needed."
    exit 0
fi

echo "Path too long by $((SOCK_LEN - 104)) chars. Applying fix..."
echo ""

# Step 1: Quit Rancher Desktop if running
if pgrep -q "Rancher Desktop"; then
    echo "Rancher Desktop is running. Quitting..."
    osascript -e 'quit app "Rancher Desktop"' 2>/dev/null || true
    sleep 3
    if pgrep -q "Rancher Desktop"; then
        echo "ERROR: Could not quit Rancher Desktop. Please close it manually and re-run."
        exit 1
    fi
    echo "Rancher Desktop stopped."
else
    echo "Rancher Desktop not running. Good."
fi

# Step 2: Move lima dir to short path (or set up fresh)
if [ -L "$LIMA_ORIGINAL" ]; then
    echo "Symlink already exists at original location. Checking target..."
    if [ "$(readlink "$LIMA_ORIGINAL")" = "$LIMA_SHORT" ]; then
        echo "Already fixed! Symlink points to $LIMA_SHORT"
    else
        echo "Symlink points elsewhere: $(readlink "$LIMA_ORIGINAL")"
        echo "Manual intervention needed. Exiting."
        exit 1
    fi
elif [ -d "$LIMA_ORIGINAL" ]; then
    echo "Moving lima data to shorter path..."
    if [ -d "$LIMA_SHORT" ]; then
        echo "ERROR: $LIMA_SHORT already exists. Remove it first or check previous fix attempt."
        exit 1
    fi
    mv "$LIMA_ORIGINAL" "$LIMA_SHORT"
    ln -s "$LIMA_SHORT" "$LIMA_ORIGINAL"
    echo "Moved and symlinked."
elif [ ! -e "$LIMA_ORIGINAL" ]; then
    echo "Lima directory doesn't exist yet. Creating short path preemptively..."
    mkdir -p "$LIMA_SHORT"
    mkdir -p "$(dirname "$LIMA_ORIGINAL")"
    ln -s "$LIMA_SHORT" "$LIMA_ORIGINAL"
    echo "Created $LIMA_SHORT and symlinked."
fi

# Step 3: Set LIMA_HOME in shell profiles
add_lima_home() {
    local rcfile="$1"
    local marker='export LIMA_HOME="$HOME/.rd-lima"'
    if [ -f "$rcfile" ]; then
        if grep -qF "LIMA_HOME" "$rcfile"; then
            echo "  $rcfile — LIMA_HOME already set, skipping."
            return
        fi
    fi
    echo "" >> "$rcfile"
    echo "# Fix Rancher Desktop Lima socket path length (UNIX_PATH_MAX=104)" >> "$rcfile"
    echo "$marker" >> "$rcfile"
    echo "  $rcfile — added LIMA_HOME."
}

echo ""
echo "Adding LIMA_HOME to shell profiles..."
add_lima_home "$ZSHRC"
add_lima_home "$BASHRC"

# Step 4: Verify
NEW_SOCK="$LIMA_SHORT/0/ssh.sock.1234567890123456"
NEW_LEN=${#NEW_SOCK}
echo ""
echo "New socket path length: $NEW_LEN (limit: 104)"
if [ "$NEW_LEN" -le 104 ]; then
    echo "Fix successful!"
else
    echo "WARNING: Still too long. Username may be extremely long."
    echo "Contact Rob for alternative fix."
    exit 1
fi

echo ""
echo "=== Done ==="
echo ""
echo "Next steps:"
echo "  1. Close and reopen Terminal"
echo "  2. Launch Rancher Desktop"
echo "  3. Run the claude-code setup as normal"
echo ""
