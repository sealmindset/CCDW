#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - macOS One-Click Installer
# Double-click this file in Finder to install and start Claude Code Docker.
# =============================================================================

# Move to the script's directory (in case double-clicked from Finder)
cd "$(dirname "$0")" || exit 1

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Claude Code Docker - Installer${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# ---------------------------------------------------------------------------
# Check for Docker
# ---------------------------------------------------------------------------
if ! command -v docker &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Docker is not installed."
    echo ""
    echo "  Please install one of the following:"
    echo "    - Docker Desktop:   https://www.docker.com/products/docker-desktop/"
    echo "    - Rancher Desktop:  https://rancherdesktop.io/"
    echo ""
    echo "  After installing, double-click this file again."
    echo ""
    read -p "Press Enter to close..."
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Docker is installed but not running."
    echo ""
    echo "  Please start Docker Desktop or Rancher Desktop,"
    echo "  wait for it to finish loading, then double-click this file again."
    echo ""
    read -p "Press Enter to close..."
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Docker is running."

# ---------------------------------------------------------------------------
# Create projects folder
# ---------------------------------------------------------------------------
PROJECTS_DIR="$HOME/Documents/GitHub"
AZURE_DIR="$HOME/.azure"

if [ ! -d "$PROJECTS_DIR" ]; then
    echo -e "${YELLOW}[...]${NC} Creating projects folder: $PROJECTS_DIR"
    mkdir -p "$PROJECTS_DIR"
fi
echo -e "${GREEN}[OK]${NC} Projects folder: $PROJECTS_DIR"

# Create Azure config dir if it doesn't exist (for az login inside the container)
mkdir -p "$AZURE_DIR"

# ---------------------------------------------------------------------------
# Auto-update: always pull latest image
# ---------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[...]${NC} Checking for updates and downloading latest version..."
if docker pull ghcr.io/sealmindset/claude-code-docker:latest; then
    echo -e "${GREEN}[OK]${NC} Image is up to date."
else
    echo -e "${YELLOW}[WARN]${NC} Could not check for updates. Using cached image if available."
fi

# ---------------------------------------------------------------------------
# Stop existing container if running
# ---------------------------------------------------------------------------
docker rm -f claude-code &>/dev/null || true

# ---------------------------------------------------------------------------
# Start the container
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Detect Docker socket GID so the container can use Docker
# ---------------------------------------------------------------------------
DOCKER_GID=$(stat -f '%g' /var/run/docker.sock 2>/dev/null || stat -c '%g' /var/run/docker.sock 2>/dev/null || echo "0")

echo ""
echo -e "${YELLOW}[...]${NC} Starting Claude Code Docker..."
if ! docker run -d \
    --name claude-code \
    --group-add "$DOCKER_GID" \
    -p 3000:3000 \
    -p 7681:7681 \
    -p 8080:8080 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$PROJECTS_DIR:/home/coder/Documents/GitHub" \
    -v "$AZURE_DIR:/home/coder/.azure" \
    -v claude-code-data:/home/coder/.claude \
    -v claude-code-gh:/home/coder/.config/gh \
    -v claude-code-git-config:/home/coder/.gitconfig.d \
    ghcr.io/sealmindset/claude-code-docker:latest; then
    echo -e "${RED}[ERROR]${NC} Failed to start the container."
    echo ""
    echo "  Common fixes:"
    echo "    - Make sure ports 3000, 7681 and 8080 are not in use"
    echo "    - Restart Rancher Desktop and try again"
    echo ""
    read -p "Press Enter to close..."
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Claude Code Docker is running!"

# ---------------------------------------------------------------------------
# Wait for the dashboard to be ready, then open browser
# ---------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[...]${NC} Waiting for dashboard to start..."

for i in $(seq 1 30); do
    if curl -s -o /dev/null http://localhost:3000 2>/dev/null; then
        break
    fi
    sleep 2
done

echo -e "${GREEN}[OK]${NC} Dashboard is ready!"
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "  Opening Claude Code in your browser..."
echo -e "${BLUE}========================================${NC}"
echo ""

open "http://localhost:3000"

# ---------------------------------------------------------------------------
# Create desktop shortcut (macOS .webloc file)
# ---------------------------------------------------------------------------
DESKTOP_SHORTCUT="$HOME/Desktop/Claude Code.webloc"
if [ ! -f "$DESKTOP_SHORTCUT" ]; then
    cat > "$DESKTOP_SHORTCUT" << 'WEBLOC'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>URL</key>
    <string>http://localhost:3000</string>
</dict>
</plist>
WEBLOC
    echo -e "${GREEN}[OK]${NC} Desktop shortcut created: \"Claude Code\" on your desktop"
fi

echo ""
echo -e "  Dashboard:     ${GREEN}http://localhost:3000${NC}"
echo -e "  Web Terminal:  ${GREEN}http://localhost:7681${NC}"
echo -e "  VS Code:       ${GREEN}http://localhost:8080${NC}"
echo ""
echo "  To stop:    docker rm -f claude-code"
echo "  To restart: double-click this file or the desktop shortcut"
echo ""
read -p "Press Enter to close this window..."
