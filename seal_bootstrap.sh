#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker — One-Line Bootstrap (macOS / Linux) — Public Edition
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/sealmindset/CCDW/main/seal_bootstrap.sh | bash
#
# This downloads the full installer to a temp directory and runs it.
# Everything else (Rancher Desktop, Docker, configuration) is automatic.
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Claude Code — One-Line Installer${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# ---------------------------------------------------------------------------
# Connectivity check
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[...]${NC} Checking network..."
if ! curl -s --connect-timeout 5 -o /dev/null https://github.com 2>/dev/null; then
    echo -e "${RED}[ERROR]${NC} No internet connection."
    echo "  Check your Wi-Fi and try again."
    exit 1
fi
echo -e "${GREEN}[OK]${NC}  Internet connected."

# ---------------------------------------------------------------------------
# Download repo
# ---------------------------------------------------------------------------
INSTALL_DIR="$HOME/Documents/CCDW"

if [ -f "$INSTALL_DIR/seal_setup-claude-mac.command" ]; then
    echo -e "${GREEN}[OK]${NC}  Found existing install at $INSTALL_DIR"
    echo -e "${YELLOW}[...]${NC} Updating..."
    cd "$INSTALL_DIR"
    git pull 2>/dev/null || true
else
    echo -e "${YELLOW}[...]${NC} Downloading Claude Code Docker..."

    CLONE_OK=0

    # Strategy 1: git clone
    if command -v git &>/dev/null; then
        if git clone https://github.com/sealmindset/CCDW.git "$INSTALL_DIR" 2>/dev/null; then
            echo -e "${GREEN}[OK]${NC}  Downloaded via git."
            CLONE_OK=1
        fi
    fi

    # Strategy 2: ZIP fallback (no git required)
    if [ "$CLONE_OK" = "0" ]; then
        echo -e "${YELLOW}[...]${NC} Trying ZIP download..."
        ZIP_PATH="${TMPDIR:-/tmp}/CCDW.zip"
        if curl -fsSL --connect-timeout 15 -o "$ZIP_PATH" \
            "https://github.com/sealmindset/CCDW/archive/refs/heads/main.zip" 2>/dev/null; then
            mkdir -p "$INSTALL_DIR"
            unzip -q "$ZIP_PATH" -d "${TMPDIR:-/tmp}" 2>/dev/null
            rm -rf "$INSTALL_DIR"
            mv "${TMPDIR:-/tmp}/CCDW-main" "$INSTALL_DIR"
            rm -f "$ZIP_PATH"
            echo -e "${GREEN}[OK]${NC}  Downloaded via ZIP."
            CLONE_OK=1
        fi
    fi

    if [ "$CLONE_OK" = "0" ]; then
        echo -e "${RED}[ERROR]${NC} Could not download Claude Code Docker."
        echo ""
        echo "  Check:"
        echo "    1. Your internet connection is working"
        echo "    2. You can access github.com in a browser"
        echo ""
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Detect OS and run appropriate setup
# ---------------------------------------------------------------------------
cd "$INSTALL_DIR"

if [ "$(uname)" = "Darwin" ]; then
    SETUP_SCRIPT="$INSTALL_DIR/seal_setup-claude-mac.command"
else
    SETUP_SCRIPT="$INSTALL_DIR/seal_install.command"
fi

if [ ! -f "$SETUP_SCRIPT" ]; then
    echo -e "${RED}[ERROR]${NC} Setup script not found: $SETUP_SCRIPT"
    exit 1
fi

# Remove quarantine and make executable
xattr -d com.apple.quarantine "$SETUP_SCRIPT" 2>/dev/null || true
chmod +x "$SETUP_SCRIPT" 2>/dev/null || true

echo ""
echo -e "${GREEN}[OK]${NC}  Starting setup..."
echo ""

exec "$SETUP_SCRIPT"
