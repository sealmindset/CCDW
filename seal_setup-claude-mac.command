#!/usr/bin/env bash
# =============================================================================
# Claude Code - Public / Generic One-Click macOS Setup
#
# IMPORTANT — GATEKEEPER:
#   macOS blocks downloaded .command files from running when double-clicked.
#   The fix: RIGHT-CLICK the file → Open → click "Open" again.
#   See START-HERE.txt for full instructions with screenshots-style guidance.
#
# Download this file and double-click it. It handles everything:
#   1. Checks internet connectivity
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

# ---------------------------------------------------------------------------
# Log file — capture all output for troubleshooting
# ---------------------------------------------------------------------------
LOG_FILE="$HOME/Desktop/claude-setup.log"
echo "=== Claude Code Setup — $(date) ===" > "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

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
# Step 0a: Source shell profile for PATH (Finder double-click skips .zshrc)
# ---------------------------------------------------------------------------
if [ -z "${SHELL_PROFILE_SOURCED:-}" ]; then
    for profile in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
        if [ -f "$profile" ]; then
            source "$profile" 2>/dev/null || true
            break
        fi
    done
    export SHELL_PROFILE_SOURCED=1
fi

# Ensure Rancher Desktop bin is in PATH regardless
if [ -d "$HOME/.rd/bin" ]; then
    export PATH="$HOME/.rd/bin:$PATH"
fi

# ---------------------------------------------------------------------------
# Step 0b: Fix Lima socket path for long usernames (UNIX_PATH_MAX=104)
# ---------------------------------------------------------------------------
LIMA_ORIGINAL="$HOME/Library/Application Support/rancher-desktop/lima"
LIMA_SHORT="$HOME/.rd-lima"
SOCK_TEST="$LIMA_ORIGINAL/0/ssh.sock.1234567890123456"

if [ ${#SOCK_TEST} -gt 104 ] && [ ! -L "$LIMA_ORIGINAL" ]; then
    step_warn "Username creates Lima socket path too long (${#SOCK_TEST} > 104 chars)."
    step_wait "Applying Lima path fix..."

    if pgrep -q "Rancher Desktop"; then
        osascript -e 'quit app "Rancher Desktop"' 2>/dev/null || true
        sleep 3
    fi

    if [ -d "$LIMA_ORIGINAL" ]; then
        mv "$LIMA_ORIGINAL" "$LIMA_SHORT"
    else
        mkdir -p "$LIMA_SHORT"
        mkdir -p "$(dirname "$LIMA_ORIGINAL")"
    fi
    ln -s "$LIMA_SHORT" "$LIMA_ORIGINAL"

    # Persist LIMA_HOME in shell profiles
    for rcfile in "$HOME/.zshrc" "$HOME/.bashrc"; do
        if [ -f "$rcfile" ] && grep -qF "LIMA_HOME" "$rcfile"; then
            continue
        fi
        echo '' >> "$rcfile"
        echo '# Fix Rancher Desktop Lima socket path length (UNIX_PATH_MAX=104)' >> "$rcfile"
        echo 'export LIMA_HOME="$HOME/.rd-lima"' >> "$rcfile"
    done

    export LIMA_HOME="$LIMA_SHORT"
    step_ok "Lima path fix applied (${#SOCK_TEST} -> $(echo -n "$LIMA_SHORT/0/ssh.sock.1234567890123456" | wc -c | tr -d ' ') chars)."
fi

# ---------------------------------------------------------------------------
# Step 0c: System requirements
# ---------------------------------------------------------------------------
step_wait "Checking system requirements..."

# macOS version check
MACOS_VER=$(sw_vers -productVersion 2>/dev/null)
MACOS_MAJOR=$(echo "$MACOS_VER" | cut -d. -f1)
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ] && [ "$MACOS_MAJOR" -lt 12 ] 2>/dev/null; then
    step_fail "macOS 12 (Monterey) or later is required on Apple Silicon."
    echo "  You have macOS $MACOS_VER. Please update in System Preferences > Software Update."
    echo ""
    read -p "Press Enter to close..."
    exit 1
elif [ "$ARCH" = "x86_64" ] && [ "$MACOS_MAJOR" -lt 10 ] 2>/dev/null; then
    step_fail "macOS 10.15 (Catalina) or later is required."
    echo "  You have macOS $MACOS_VER."
    echo ""
    read -p "Press Enter to close..."
    exit 1
fi
step_ok "macOS $MACOS_VER ($ARCH)"

# Disk space check (need ~8GB for Rancher Desktop VM + Docker images)
AVAIL_GB=$(df -g "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "$AVAIL_GB" ] && [ "$AVAIL_GB" -lt 8 ] 2>/dev/null; then
    step_fail "Low disk space: ${AVAIL_GB}GB available, 8GB recommended."
    echo ""
    echo "  Claude Code needs about 8 GB of free space:"
    echo "    - Rancher Desktop: ~5 GB (Docker engine + VM)"
    echo "    - Claude Code image: ~2 GB"
    echo "    - Working space: ~1 GB"
    echo ""
    echo "  Free up some space, then double-click this file again."
    echo ""
    read -p "Press Enter to close..."
    exit 1
fi
step_ok "Disk space: ${AVAIL_GB}GB available"

# ---------------------------------------------------------------------------
# Step 0d: Connectivity checks
# ---------------------------------------------------------------------------
step_wait "Checking internet connection..."
if curl -s --connect-timeout 5 -o /dev/null https://github.com 2>/dev/null; then
    step_ok "Internet connection."
else
    step_fail "No internet connection."
    echo ""
    echo "  Please check:"
    echo "    1. Are you connected to Wi-Fi?"
    echo "    2. Can you open https://github.com in a browser?"
    echo ""
    echo "  After connecting, double-click this file again."
    echo ""
    read -p "Press Enter to close..."
    exit 1
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

# ---------------------------------------------------------------------------
# Helper: install or upgrade Rancher Desktop to latest
# ---------------------------------------------------------------------------
install_rancher_desktop() {
    local action="${1:-install}"  # "install" or "upgrade"
    local target_dir="${RANCHER_APP:-/Applications/Rancher Desktop.app}"

    # Detect architecture for download
    ARCH=$(uname -m)
    if [ "$ARCH" = "arm64" ]; then
        DMG_ARCH="aarch64"
    else
        DMG_ARCH="x86_64"
    fi

    # Strategy 1: Try brew (if available)
    if command -v brew &>/dev/null; then
        if [ "$action" = "upgrade" ]; then
            step_wait "Updating Rancher Desktop via Homebrew..."
            if brew upgrade --cask rancher 2>/dev/null; then
                step_ok "Rancher Desktop updated via Homebrew."
                RANCHER_APP="/Applications/Rancher Desktop.app"
                return 0
            fi
        else
            step_wait "Installing Rancher Desktop via Homebrew..."
            if brew install --cask rancher 2>/dev/null; then
                step_ok "Rancher Desktop installed via Homebrew."
                RANCHER_APP="/Applications/Rancher Desktop.app"
                return 0
            fi
        fi
        step_warn "Homebrew ${action} failed. Trying direct download..."
    fi

    # Strategy 2: Direct download from GitHub releases
    step_wait "Downloading latest Rancher Desktop..."

    DMG_PATH="$TMPDIR/RancherDesktop.dmg"

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
            step_wait "Installing..."

            MOUNT_POINT=$(hdiutil attach -nobrowse "$DMG_PATH" 2>/dev/null | tail -1 | awk '{print $NF}')
            if [ -d "$MOUNT_POINT/Rancher Desktop.app" ]; then
                cp -R "$MOUNT_POINT/Rancher Desktop.app" "/Applications/" 2>/dev/null \
                    || cp -R "$MOUNT_POINT/Rancher Desktop.app" "$HOME/Applications/" 2>/dev/null
                hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
                rm -f "$DMG_PATH"
                step_ok "Rancher Desktop ${action}d."
                if [ -d "/Applications/Rancher Desktop.app" ]; then
                    RANCHER_APP="/Applications/Rancher Desktop.app"
                else
                    RANCHER_APP="$HOME/Applications/Rancher Desktop.app"
                fi
                return 0
            else
                hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
                step_warn "DMG mount succeeded but app not found inside."
            fi
        else
            step_warn "Download failed."
        fi
        rm -f "$DMG_PATH" 2>/dev/null || true
    fi

    return 1
}

# Check Rancher Desktop version — auto-upgrade if outdated
RD_NEEDS_UPGRADE=0
if [ -n "$RANCHER_APP" ]; then
    RD_VERSION=$(defaults read "$RANCHER_APP/Contents/Info" CFBundleShortVersionString 2>/dev/null)
    if [ -n "$RD_VERSION" ]; then
        RD_MINOR=$(echo "$RD_VERSION" | cut -d. -f2)
        if [ "${RD_MINOR:-0}" -lt 12 ] 2>/dev/null; then
            step_warn "Rancher Desktop $RD_VERSION is outdated. Upgrading automatically..."

            if pgrep -q "Rancher Desktop"; then
                osascript -e 'quit app "Rancher Desktop"' 2>/dev/null || true
                sleep 3
            fi

            if install_rancher_desktop "upgrade"; then
                NEW_VER=$(defaults read "$RANCHER_APP/Contents/Info" CFBundleShortVersionString 2>/dev/null)
                step_ok "Rancher Desktop upgraded: $RD_VERSION → ${NEW_VER:-latest}"
            else
                step_warn "Auto-upgrade failed. Continuing with $RD_VERSION."
            fi
        else
            step_ok "Rancher Desktop $RD_VERSION"
        fi
    fi
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

    install_rancher_desktop "install"

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
elif ! python3 -c "
import json, sys
with open('$RD_SETTINGS') as f: cfg = json.load(f)
engine = cfg.get('containerEngine', {}).get('name', '')
sys.exit(0 if engine in ('moby', 'dockerd', '') else 1)
" 2>/dev/null; then
    step_warn "Rancher Desktop is configured for containerd (not Docker)."
    step_wait "Switching to Docker engine..."

    if pgrep -q "Rancher Desktop"; then
        osascript -e 'quit app "Rancher Desktop"' 2>/dev/null || true
        sleep 3
    fi

    python3 -c "
import json
with open('$RD_SETTINGS') as f: cfg = json.load(f)
cfg.setdefault('containerEngine', {})['name'] = 'moby'
cfg.setdefault('kubernetes', {})['enabled'] = False
with open('$RD_SETTINGS', 'w') as f: json.dump(cfg, f, indent=2)
" 2>/dev/null
    step_ok "Switched to Docker engine. Rancher Desktop will restart."
    RANCHER_APP="${RANCHER_APP:-/Applications/Rancher Desktop.app}"
fi

# ---------------------------------------------------------------------------
# Step 3: Launch Rancher Desktop and wait for Docker daemon
# ---------------------------------------------------------------------------
docker_ready() {
    docker info &>/dev/null 2>&1 &
    local pid=$!
    ( sleep 10 && kill "$pid" 2>/dev/null ) &
    local watchdog=$!
    wait "$pid" 2>/dev/null
    local rc=$?
    kill "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null
    return $rc
}

if ! docker_ready; then
    if [ -n "${RANCHER_APP:-}" ]; then
        step_wait "Launching Rancher Desktop..."

        # Remove quarantine if downloaded directly
        xattr -r -d com.apple.quarantine "$RANCHER_APP" 2>/dev/null || true

        open -a "$RANCHER_APP"

        echo ""
        echo -e "  ${DIM}First-time setup takes 2-3 minutes while Docker gets ready.${NC}"
        echo -e "  ${DIM}Returning users: about 30 seconds.${NC}"
        echo ""

        DOCKER_READY=0
        WAIT_START=$(date +%s)
        MAX_WAIT=300
        BAR_WIDTH=30

        for i in $(seq 1 60); do
            if docker_ready; then
                DOCKER_READY=1
                break
            fi
            # Re-check PATH — Rancher Desktop adds docker to ~/.rd/bin
            if ! command -v docker &>/dev/null && [ -f "$HOME/.rd/bin/docker" ]; then
                export PATH="$HOME/.rd/bin:$PATH"
            fi

            ELAPSED=$(( $(date +%s) - WAIT_START ))
            MINS=$(( ELAPSED / 60 ))
            SECS=$(( ELAPSED % 60 ))

            # Phase description based on elapsed time
            if [ $ELAPSED -lt 30 ]; then
                PHASE="Provisioning Docker engine"
            elif [ $ELAPSED -lt 90 ]; then
                PHASE="Starting services        "
            elif [ $ELAPSED -lt 180 ]; then
                PHASE="Almost ready              "
            else
                PHASE="Still working (be patient)"
            fi

            # Progress bar (fills over MAX_WAIT seconds)
            PCT=$(( ELAPSED * 100 / MAX_WAIT ))
            [ $PCT -gt 95 ] && PCT=95
            FILLED=$(( PCT * BAR_WIDTH / 100 ))
            EMPTY=$(( BAR_WIDTH - FILLED ))
            BAR=$(printf '%0.s█' $(seq 1 $FILLED 2>/dev/null) 2>/dev/null)
            SPC=$(printf '%0.s░' $(seq 1 $EMPTY 2>/dev/null) 2>/dev/null)

            printf "\r  ${YELLOW}%s${NC} ${DIM}[${NC}${GREEN}%s${NC}${DIM}%s${NC}${DIM}]${NC} ${DIM}%dm %02ds${NC}  " \
                "$PHASE" "$BAR" "$SPC" "$MINS" "$SECS"

            sleep 5
        done

        # Clear the progress line
        printf "\r%-80s\r" ""

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

            if ! docker_ready; then
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

# Check if we're already inside the repo (script lives next to seal_install.command)
if [ -f "$SCRIPT_DIR/seal_install.command" ]; then
    INSTALL_DIR="$SCRIPT_DIR"
    step_ok "Using local copy: $INSTALL_DIR"
elif [ -f "$INSTALL_DIR/seal_install.command" ]; then
    step_wait "Updating to latest version..."
    cd "$INSTALL_DIR"
    git pull 2>/dev/null || true
    step_ok "Updated."
else
    # Pre-flight: check GitHub authentication
    GH_AUTH=0
    if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
        step_ok "GitHub CLI authenticated."
        GH_AUTH=1
    elif git credential-osxkeychain 2>&1 | grep -qi "usage" &>/dev/null; then
        step_info "Git credential helper available."
    else
        step_warn "No GitHub credentials detected."
        echo ""
        echo "  To download Claude Code, you need GitHub access."
        echo "  The easiest way is to open this URL in your browser:"
        echo "    https://github.com/sealmindset/CCDW"
        echo "  If you can see the page, try again."
        echo ""
    fi

    step_wait "Downloading (this may take a minute)..."
    CLONE_OK=0

    # Strategy 1: git clone
    if git clone https://github.com/sealmindset/CCDW.git "$INSTALL_DIR" 2>/dev/null; then
        step_ok "Downloaded via git."
        CLONE_OK=1
    else
        step_warn "Git clone failed (likely no credentials). Trying ZIP download..."

        # Strategy 2: ZIP archive fallback
        ZIP_PATH="$TMPDIR/CCDW.zip"
        rm -f "$ZIP_PATH" 2>/dev/null || true
        if curl -fSL --connect-timeout 15 -o "$ZIP_PATH" \
            "https://github.com/sealmindset/CCDW/archive/refs/heads/main.zip" 2>/dev/null; then
            step_wait "Extracting..."
            mkdir -p "$INSTALL_DIR"
            if unzip -q "$ZIP_PATH" -d "$TMPDIR" 2>/dev/null; then
                # unzip creates CCDW-main/ — move contents into INSTALL_DIR
                rm -rf "$INSTALL_DIR"
                mv "$TMPDIR/CCDW-main" "$INSTALL_DIR"
                rm -f "$ZIP_PATH"
                step_ok "Downloaded via ZIP archive."
                CLONE_OK=1
            else
                step_warn "ZIP extraction failed."
                rm -f "$ZIP_PATH" 2>/dev/null || true
            fi
        else
            step_warn "ZIP download failed (private repo requires auth)."
            rm -f "$ZIP_PATH" 2>/dev/null || true
        fi
    fi

    if [ "$CLONE_OK" = "0" ]; then
        echo ""
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}  Could not download Claude Code${NC}"
        echo -e "${RED}========================================${NC}"
        echo ""
        echo "  Opening the GitHub repo page in your browser..."
        echo "  If you can sign in and see the repo, download"
        echo "  it manually using the green 'Code' button > 'Download ZIP'."
        echo ""
        echo "  Then unzip it and move the folder to:"
        echo "    $INSTALL_DIR"
        echo ""
        echo "  Things to check:"
        echo ""
        echo "  1. Check your internet connection."
        echo "     Can you open https://github.com in a browser?"
        echo ""
        echo "  2. GitHub access -- Make sure you can access github.com"
        echo "     and have permissions to view the repository."
        echo ""
        open "https://github.com/sealmindset/CCDW" 2>/dev/null
        echo "  After fixing, double-click this file again."
        echo ""
        read -p "Press Enter to close..."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Step 5: Remove quarantine from seal_install.command
# ---------------------------------------------------------------------------
xattr -d com.apple.quarantine "$INSTALL_DIR/seal_install.command" 2>/dev/null || true
chmod +x "$INSTALL_DIR/seal_install.command" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 6: Run the installer
# ---------------------------------------------------------------------------
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Starting Claude Code installer...${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
step_info "Pre-checks done in $(elapsed). Starting installer..."
echo ""

cd "$INSTALL_DIR"
export CLAUDE_SETUP_LOG="$LOG_FILE"
exec "$INSTALL_DIR/seal_install.command"
