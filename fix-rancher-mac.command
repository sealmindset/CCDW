#!/usr/bin/env bash
# =============================================================================
# Fix Rancher Desktop - macOS
#
# Factory-resets Rancher Desktop's Lima VM and configuration when Docker
# stops working. Equivalent of fix-rancher.bat for Windows WSL distros.
#
# What this does:
#   1. Quits Rancher Desktop
#   2. Removes the Lima VM (Docker engine)
#   3. Removes Rancher Desktop settings
#   4. Re-creates clean settings (moby/Docker engine, no Kubernetes)
#   5. Relaunches Rancher Desktop
#
# Your Docker images will be re-downloaded, but your projects and
# Claude Code settings are safe (stored in Docker volumes and ~/Documents).
# =============================================================================

cd "$(dirname "$0")" || exit 1

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Fix Rancher Desktop — macOS${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "  This will reset Rancher Desktop's Docker engine."
echo -e "  Your projects and settings are ${GREEN}safe${NC} — only the VM is reset."
echo ""
echo -e "  ${DIM}Docker images will need to re-download (~2-5 minutes).${NC}"
echo ""
read -p "  Press Enter to continue, or Ctrl+C to cancel... " _

# ---------------------------------------------------------------------------
# Step 1: Quit Rancher Desktop
# ---------------------------------------------------------------------------
echo ""
if pgrep -q "Rancher Desktop"; then
    echo -e "${YELLOW}[...]${NC} Quitting Rancher Desktop..."
    osascript -e 'quit app "Rancher Desktop"' 2>/dev/null || true
    for i in $(seq 1 15); do
        pgrep -q "Rancher Desktop" || break
        sleep 1
    done
    if pgrep -q "Rancher Desktop"; then
        echo -e "${YELLOW}[...]${NC} Force-quitting..."
        pkill -9 "Rancher Desktop" 2>/dev/null || true
        sleep 2
    fi
    echo -e "${GREEN}[OK]${NC}    Rancher Desktop stopped."
else
    echo -e "${GREEN}[OK]${NC}    Rancher Desktop is not running."
fi

# ---------------------------------------------------------------------------
# Step 2: Remove Lima VM
# ---------------------------------------------------------------------------
LIMA_PATHS=(
    "$HOME/.rd-lima"
    "$HOME/Library/Application Support/rancher-desktop/lima"
)

for lima_path in "${LIMA_PATHS[@]}"; do
    if [ -d "$lima_path" ] || [ -L "$lima_path" ]; then
        # If it's a symlink, resolve and remove the target too
        if [ -L "$lima_path" ]; then
            real_path=$(readlink "$lima_path")
            rm -rf "$real_path" 2>/dev/null || true
            rm -f "$lima_path" 2>/dev/null || true
            echo -e "${GREEN}[OK]${NC}    Removed Lima VM (symlink): $(basename "$lima_path")"
        else
            rm -rf "$lima_path" 2>/dev/null || true
            echo -e "${GREEN}[OK]${NC}    Removed Lima VM: $(basename "$lima_path")"
        fi
    fi
done

# ---------------------------------------------------------------------------
# Step 3: Remove Rancher Desktop settings and cache
# ---------------------------------------------------------------------------
RD_CONFIG_DIR="$HOME/Library/Application Support/rancher-desktop"
RD_CACHE="$HOME/Library/Caches/rancher-desktop"
RD_LOGS="$HOME/Library/Logs/rancher-desktop"

for dir in "$RD_CONFIG_DIR" "$RD_CACHE" "$RD_LOGS"; do
    if [ -d "$dir" ]; then
        rm -rf "$dir" 2>/dev/null || true
        echo -e "${GREEN}[OK]${NC}    Removed: $(basename "$dir")"
    fi
done

# Remove Rancher Desktop socket and bin (will be recreated on launch)
if [ -d "$HOME/.rd" ]; then
    rm -rf "$HOME/.rd" 2>/dev/null || true
    echo -e "${GREEN}[OK]${NC}    Removed: ~/.rd"
fi

# ---------------------------------------------------------------------------
# Step 4: Re-create clean settings
# ---------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[...]${NC} Creating fresh configuration..."

mkdir -p "$RD_CONFIG_DIR"
cat > "$RD_CONFIG_DIR/settings.json" << 'JSON'
{
  "version": 10,
  "containerEngine": {
    "name": "moby"
  },
  "kubernetes": {
    "enabled": false
  }
}
JSON
echo -e "${GREEN}[OK]${NC}    Pre-configured: Docker engine (moby), no Kubernetes."

# ---------------------------------------------------------------------------
# Step 4b: Re-apply Lima socket path fix if needed
# ---------------------------------------------------------------------------
LIMA_ORIGINAL="$HOME/Library/Application Support/rancher-desktop/lima"
LIMA_SHORT="$HOME/.rd-lima"
SOCK_TEST="$LIMA_ORIGINAL/0/ssh.sock.1234567890123456"

if [ ${#SOCK_TEST} -gt 104 ]; then
    mkdir -p "$LIMA_SHORT"
    mkdir -p "$(dirname "$LIMA_ORIGINAL")"
    ln -sf "$LIMA_SHORT" "$LIMA_ORIGINAL"
    export LIMA_HOME="$LIMA_SHORT"
    echo -e "${GREEN}[OK]${NC}    Lima socket path fix re-applied."
fi

# ---------------------------------------------------------------------------
# Step 5: Relaunch Rancher Desktop
# ---------------------------------------------------------------------------
RANCHER_APP=""
if [ -d "/Applications/Rancher Desktop.app" ]; then
    RANCHER_APP="/Applications/Rancher Desktop.app"
elif [ -d "$HOME/Applications/Rancher Desktop.app" ]; then
    RANCHER_APP="$HOME/Applications/Rancher Desktop.app"
fi

if [ -n "$RANCHER_APP" ]; then
    echo ""
    echo -e "${YELLOW}[...]${NC} Launching Rancher Desktop (fresh start)..."
    open -a "$RANCHER_APP"

    echo -e "  ${DIM}First-time setup takes 2-3 minutes while Docker initializes.${NC}"
    echo ""

    WAIT_START=$(date +%s)
    for i in $(seq 1 60); do
        if [ -f "$HOME/.rd/bin/docker" ]; then
            export PATH="$HOME/.rd/bin:$PATH"
        fi
        if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
            break
        fi
        ELAPSED=$(( $(date +%s) - WAIT_START ))
        printf "\r  Waiting for Docker... %dm %02ds" $((ELAPSED/60)) $((ELAPSED%60))
        sleep 5
    done
    printf "\r%-60s\r" ""

    if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
        echo -e "${GREEN}[OK]${NC}    Docker is running!"
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}  Rancher Desktop has been repaired!${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo "  You can now double-click ${BOLD}setup-claude-mac.command${NC}"
        echo "  or ${BOLD}install.command${NC} to continue setup."
    else
        echo ""
        echo -e "${YELLOW}========================================${NC}"
        echo -e "${YELLOW}  Rancher Desktop is still starting${NC}"
        echo -e "${YELLOW}========================================${NC}"
        echo ""
        echo "  Wait for the Rancher Desktop menu bar icon to stop spinning,"
        echo "  then double-click ${BOLD}setup-claude-mac.command${NC} to continue."
    fi
else
    echo ""
    echo -e "${YELLOW}[WARN]${NC}  Rancher Desktop app not found in Applications."
    echo "  Double-click ${BOLD}setup-claude-mac.command${NC} to reinstall it."
fi

echo ""
read -p "Press Enter to close..."
