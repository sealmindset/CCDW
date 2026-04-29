#!/usr/bin/env bash
# =============================================================================
# Claude Code - One-Click macOS Setup
#
# Download this file and double-click it. It handles everything:
#   1. Checks VPN and internet connectivity
#   2. Installs Rancher Desktop (if needed)
#   3. Launches Rancher Desktop and waits for Docker
#   4. Downloads Claude Code Docker
#   5. Runs the installer
#
# You do NOT need to open a terminal or know any commands.
# Just double-click this file and follow the prompts.
# =============================================================================

cd "$(dirname "$0")" || exit 1

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Timer — track how long setup takes
# ---------------------------------------------------------------------------
SETUP_START=$(date +%s)

elapsed() {
    local now=$(date +%s)
    local secs=$(( now - SETUP_START ))
    local mins=$(( secs / 60 ))
    local remaining=$(( secs % 60 ))
    echo "${mins}m ${remaining}s"
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
step_ok()   { echo -e "${GREEN}[OK]${NC}    $1"; }
step_fail() { echo -e "${RED}[ERROR]${NC} $1"; }
step_wait() { echo -e "${YELLOW}[...]${NC}   $1"; }
step_info() { echo -e "${BLUE}[INFO]${NC}  $1"; }
step_warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }

# ---------------------------------------------------------------------------
# Determine install location
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/Documents/CCDW"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Claude Code - macOS Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# ---------------------------------------------------------------------------
# Gatekeeper: remove quarantine from self (if double-clicked from Downloads)
# ---------------------------------------------------------------------------
xattr -d com.apple.quarantine "$0" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 0: Connectivity checks
# ---------------------------------------------------------------------------
step_wait "Checking internet connection..."
if curl -s --connect-timeout 5 -o /dev/null https://github.com 2>/dev/null; then
    step_ok "Internet connection."
else
    step_fail "No internet connection."
    echo ""
    echo "  Please check:"
    echo "    1. Are you connected to Wi-Fi?"
    echo "    2. Is your VPN connected? Look for the GlobalProtect"
    echo "       or Zscaler icon in the menu bar (top-right)."
    echo ""
    echo "  After connecting, double-click this file again."
    echo ""
    read -p "Press Enter to close..."
    exit 1
fi

step_wait "Checking VPN connection..."
if curl -s --connect-timeout 8 -o /dev/null https://snapistg-scus.azure.sleepnumber.com 2>/dev/null; then
    step_ok "VPN connected."
else
    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}  VPN is not connected${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo "  Claude Code needs VPN to reach Sleep Number services."
    echo ""
    echo "  How to connect:"
    echo "    1. Look for the GlobalProtect icon in the menu bar"
    echo "       (top-right corner of your screen)"
    echo "    2. Click it and make sure it says \"Connected\""
    echo "    3. If you don't see it, open Spotlight (Cmd+Space)"
    echo "       and search for \"GlobalProtect\""
    echo ""
    read -p "  Press Enter after connecting your VPN... "

    if ! curl -s --connect-timeout 8 -o /dev/null https://snapistg-scus.azure.sleepnumber.com 2>/dev/null; then
        step_fail "Still cannot reach Sleep Number services."
        echo "         Make sure GlobalProtect VPN is connected and try again."
        echo ""
        read -p "Press Enter to close..."
        exit 1
    fi
    step_ok "VPN connected."
fi

# ---------------------------------------------------------------------------
# Step 1: Check for / install Rancher Desktop
# ---------------------------------------------------------------------------
echo ""
step_wait "Checking for Docker..."

DOCKER_FOUND=0
RANCHER_APP=""

# Check common Rancher Desktop locations
if [ -d "/Applications/Rancher Desktop.app" ]; then
    RANCHER_APP="/Applications/Rancher Desktop.app"
elif [ -d "$HOME/Applications/Rancher Desktop.app" ]; then
    RANCHER_APP="$HOME/Applications/Rancher Desktop.app"
fi

# Check if docker CLI is available
if command -v docker &>/dev/null; then
    DOCKER_FOUND=1
elif [ -f "$HOME/.rd/bin/docker" ]; then
    export PATH="$HOME/.rd/bin:$PATH"
    DOCKER_FOUND=1
fi

if [ "$DOCKER_FOUND" = "0" ] && [ -z "$RANCHER_APP" ]; then
    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}  Rancher Desktop needs to be installed${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo "  Rancher Desktop provides Docker for your Mac."
    echo "  It's free and open-source."
    echo ""

    # Detect architecture for download
    ARCH=$(uname -m)
    if [ "$ARCH" = "arm64" ]; then
        DMG_ARCH="aarch64"
    else
        DMG_ARCH="x86_64"
    fi

    # Strategy 1: Try brew (if available)
    if command -v brew &>/dev/null; then
        step_wait "Installing Rancher Desktop via Homebrew..."
        if brew install --cask rancher 2>/dev/null; then
            step_ok "Rancher Desktop installed via Homebrew."
            RANCHER_APP="/Applications/Rancher Desktop.app"
        else
            step_warn "Homebrew install failed. Trying direct download..."
        fi
    fi

    # Strategy 2: Direct download from GitHub releases
    if [ -z "$RANCHER_APP" ]; then
        step_wait "Downloading Rancher Desktop..."

        DMG_PATH="$TMPDIR/RancherDesktop.dmg"

        # Get latest release URL
        DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/rancher-sandbox/rancher-desktop/releases/latest" \
            | python3 -c "
import json, sys
data = json.load(sys.stdin)
for asset in data.get('assets', []):
    name = asset['name']
    if name.endswith('.dmg') and '$DMG_ARCH' in name:
        print(asset['browser_download_url'])
        break
" 2>/dev/null)

        if [ -n "$DOWNLOAD_URL" ]; then
            echo "  Downloading $(basename "$DOWNLOAD_URL")..."
            if curl -L --progress-bar -o "$DMG_PATH" "$DOWNLOAD_URL"; then
                step_wait "Installing (this opens the DMG)..."

                # Mount DMG and copy app
                MOUNT_POINT=$(hdiutil attach -nobrowse "$DMG_PATH" 2>/dev/null | tail -1 | awk '{print $NF}')
                if [ -d "$MOUNT_POINT/Rancher Desktop.app" ]; then
                    cp -R "$MOUNT_POINT/Rancher Desktop.app" "/Applications/" 2>/dev/null \
                        || cp -R "$MOUNT_POINT/Rancher Desktop.app" "$HOME/Applications/" 2>/dev/null
                    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
                    rm -f "$DMG_PATH"
                    step_ok "Rancher Desktop installed."
                    if [ -d "/Applications/Rancher Desktop.app" ]; then
                        RANCHER_APP="/Applications/Rancher Desktop.app"
                    else
                        RANCHER_APP="$HOME/Applications/Rancher Desktop.app"
                    fi
                else
                    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
                    step_warn "DMG mount succeeded but app not found inside."
                fi
            else
                step_warn "Download failed."
            fi
            rm -f "$DMG_PATH" 2>/dev/null || true
        fi
    fi

    # Strategy 3: Open browser (last resort)
    if [ -z "$RANCHER_APP" ]; then
        echo ""
        echo -e "${YELLOW}========================================${NC}"
        echo -e "${YELLOW}  Automatic install did not work${NC}"
        echo -e "${YELLOW}========================================${NC}"
        echo ""
        echo "  Opening the Rancher Desktop download page..."
        echo ""
        echo "  When the page opens:"
        echo "    1. Click the macOS download button"
        echo "    2. Open the .dmg when it downloads"
        echo "    3. Drag Rancher Desktop to Applications"
        echo "    4. Then double-click this file again"
        echo ""
        open "https://rancherdesktop.io/" 2>/dev/null
        read -p "Press Enter to close..."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Step 2: Pre-configure Rancher Desktop (skip first-run dialog)
# ---------------------------------------------------------------------------
RD_CONFIG_DIR="$HOME/Library/Application Support/rancher-desktop"
RD_SETTINGS="$RD_CONFIG_DIR/settings.json"

if [ ! -f "$RD_SETTINGS" ]; then
    step_wait "Pre-configuring Rancher Desktop to use Docker engine..."
    mkdir -p "$RD_CONFIG_DIR"
    cat > "$RD_SETTINGS" << 'JSON'
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
    step_ok "Pre-configured Docker engine (skips first-run dialog)."
fi

# ---------------------------------------------------------------------------
# Step 3: Launch Rancher Desktop and wait for Docker daemon
# ---------------------------------------------------------------------------
if ! docker info &>/dev/null 2>&1; then
    if [ -n "${RANCHER_APP:-}" ]; then
        step_wait "Launching Rancher Desktop..."

        # Remove quarantine if downloaded directly
        xattr -r -d com.apple.quarantine "$RANCHER_APP" 2>/dev/null || true

        open -a "$RANCHER_APP"

        step_wait "Waiting for Docker to start (this can take 30-60 seconds)..."
        echo -e "  ${DIM}The Rancher Desktop icon in your menu bar will stop animating when ready.${NC}"

        DOCKER_READY=0
        for i in $(seq 1 24); do
            if docker info &>/dev/null 2>&1; then
                DOCKER_READY=1
                break
            fi
            # Re-check PATH — Rancher Desktop adds docker to ~/.rd/bin
            if ! command -v docker &>/dev/null && [ -f "$HOME/.rd/bin/docker" ]; then
                export PATH="$HOME/.rd/bin:$PATH"
            fi
            sleep 5
        done

        if [ "$DOCKER_READY" = "0" ]; then
            echo ""
            echo -e "${YELLOW}========================================${NC}"
            echo -e "${YELLOW}  Docker is not ready yet${NC}"
            echo -e "${YELLOW}========================================${NC}"
            echo ""
            echo "  Rancher Desktop is still starting up."
            echo ""
            echo "  Wait for the Rancher Desktop icon in your menu bar"
            echo "  to stop spinning, then press Enter to continue."
            echo ""
            read -p "  Press Enter when ready... "

            # Add path one more time
            if ! command -v docker &>/dev/null && [ -f "$HOME/.rd/bin/docker" ]; then
                export PATH="$HOME/.rd/bin:$PATH"
            fi

            if ! docker info &>/dev/null 2>&1; then
                step_fail "Docker still not running."
                echo ""
                echo "  Try these steps:"
                echo "    1. Open Rancher Desktop from Applications"
                echo "    2. When prompted, select 'dockerd (moby)' as the engine"
                echo "    3. Wait for it to finish loading"
                echo "    4. Then double-click this file again"
                echo ""
                read -p "Press Enter to close..."
                exit 1
            fi
        fi
    else
        step_fail "Docker is not running and Rancher Desktop was not found."
        echo ""
        echo "  Please start Rancher Desktop from Applications,"
        echo "  wait for it to finish loading, then run this file again."
        echo ""
        read -p "Press Enter to close..."
        exit 1
    fi
fi

step_ok "Docker is running."

# ---------------------------------------------------------------------------
# Step 4: Download or update Claude Code Docker
# ---------------------------------------------------------------------------
echo ""
step_wait "Getting Claude Code Docker..."

# Check if we're already inside the repo (script lives next to install.command)
if [ -f "$SCRIPT_DIR/install.command" ]; then
    INSTALL_DIR="$SCRIPT_DIR"
    step_ok "Using local copy: $INSTALL_DIR"
elif [ -f "$INSTALL_DIR/install.command" ]; then
    step_wait "Updating to latest version..."
    cd "$INSTALL_DIR"
    git pull 2>/dev/null || true
    step_ok "Updated."
else
    step_wait "Downloading (this may take a minute)..."
    if git clone https://github.com/SleepNumberInc/CCDW.git "$INSTALL_DIR" 2>/dev/null; then
        step_ok "Downloaded."
    else
        echo ""
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}  Could not download Claude Code${NC}"
        echo -e "${RED}========================================${NC}"
        echo ""
        echo "  Two things to check:"
        echo ""
        echo "  1. VPN -- Make sure GlobalProtect is connected."
        echo "     Look for its icon in the menu bar (top-right)."
        echo ""
        echo "  2. GitHub access -- Your GitHub account needs access to"
        echo "     the Sleep Number organization. If you haven't set this"
        echo "     up yet, ask your manager or the AI CoE team."
        echo ""
        echo "  After fixing, double-click this file again."
        echo ""
        read -p "Press Enter to close..."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Step 5: Remove quarantine from install.command
# ---------------------------------------------------------------------------
xattr -d com.apple.quarantine "$INSTALL_DIR/install.command" 2>/dev/null || true
chmod +x "$INSTALL_DIR/install.command" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 6: Run the installer
# ---------------------------------------------------------------------------
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Starting Claude Code installer...${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
step_info "Setup completed in $(elapsed). Handing off to installer."
echo ""

cd "$INSTALL_DIR"
exec "$INSTALL_DIR/install.command" --ai=foundry
