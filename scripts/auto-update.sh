#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Auto-Update /make-it Skills
# Checks GitHub for newer version and installs if available
# =============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

INSTALL_DIR="/home/coder/.claude/make-it"
REMOTE_BASE="https://raw.githubusercontent.com/sealmindset/make-it/main"

# Get installed version
INSTALLED_VERSION=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo "0.0.0")

# Check remote version (timeout after 5 seconds)
REMOTE_VERSION=$(curl -fsSL --connect-timeout 5 "$REMOTE_BASE/VERSION" 2>/dev/null | tr -d '[:space:]')

if [ -z "$REMOTE_VERSION" ]; then
    echo -e "${YELLOW}[SKIP]${NC} Could not check for skill updates (no internet?)"
    exit 0
fi

if [ "$INSTALLED_VERSION" = "$REMOTE_VERSION" ]; then
    echo -e "${GREEN}[OK]${NC} Skills are up to date (v${INSTALLED_VERSION})"
    exit 0
fi

echo -e "${YELLOW}[...]${NC} Updating skills: v${INSTALLED_VERSION} -> v${REMOTE_VERSION}"

# Run the installer
if curl -fsSL --connect-timeout 10 "$REMOTE_BASE/install.sh" | bash; then
    echo -e "${GREEN}[OK]${NC} Skills updated to v${REMOTE_VERSION}"
else
    echo -e "${YELLOW}[WARN]${NC} Skill update failed (continuing with v${INSTALLED_VERSION})"
fi
