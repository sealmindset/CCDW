#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - First Run Setup (runs on the HOST, not in container)
# Ensures the projects directory exists before starting the container.
# =============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Claude Code Docker - First Run Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# ---------------------------------------------------------------------------
# Detect OS and set default projects path
# ---------------------------------------------------------------------------
DEFAULT_DIR=""

case "$(uname -s)" in
    Darwin)
        DEFAULT_DIR="$HOME/Documents/GitHub"
        echo -e "  Platform: ${GREEN}macOS${NC}"
        ;;
    Linux)
        DEFAULT_DIR="$HOME/Documents/GitHub"
        echo -e "  Platform: ${GREEN}Linux${NC}"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        DEFAULT_DIR="$USERPROFILE/Documents/GitHub"
        echo -e "  Platform: ${GREEN}Windows${NC}"
        ;;
    *)
        DEFAULT_DIR="$HOME/Documents/GitHub"
        echo -e "  Platform: ${YELLOW}Unknown (using default path)${NC}"
        ;;
esac

echo ""

# ---------------------------------------------------------------------------
# Ask about projects folder (default is fine for 80% of users)
# ---------------------------------------------------------------------------
echo -e "Your projects will be saved to: ${GREEN}${DEFAULT_DIR}${NC}"
echo ""
read -p "Press Enter to use this location, or type a different path: " CUSTOM_DIR

if [ -n "$CUSTOM_DIR" ]; then
    # Expand ~ to home directory
    CUSTOM_DIR="${CUSTOM_DIR/#\~/$HOME}"
    PROJECTS_DIR="$CUSTOM_DIR"
    echo ""
    echo -e "  Using custom path: ${GREEN}${PROJECTS_DIR}${NC}"
else
    PROJECTS_DIR="$DEFAULT_DIR"
fi

echo ""

# ---------------------------------------------------------------------------
# Create projects directory if it doesn't exist
# ---------------------------------------------------------------------------
if [ -d "$PROJECTS_DIR" ]; then
    echo -e "${GREEN}[OK]${NC} Projects folder already exists."
else
    echo -e "${YELLOW}[...]${NC} Creating projects folder..."
    mkdir -p "$PROJECTS_DIR"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[OK]${NC} Created: $PROJECTS_DIR"
    else
        echo -e "${RED}[ERROR]${NC} Could not create $PROJECTS_DIR"
        echo "  Please create this directory manually and try again."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Create .env from .env.example
# ---------------------------------------------------------------------------
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        echo -e "${YELLOW}[...]${NC} Creating .env from template..."
        cp .env.example .env
        echo -e "${GREEN}[OK]${NC} Created .env"
    fi
else
    echo -e "${GREEN}[OK]${NC} .env file already exists."
fi

# Write PROJECTS_PATH only if user chose a non-default location
if [ "$PROJECTS_DIR" != "$DEFAULT_DIR" ]; then
    # Remove any existing PROJECTS_PATH line and add the custom one
    if [ -f .env ]; then
        grep -v "^PROJECTS_PATH=" .env > .env.tmp && mv .env.tmp .env
        echo "PROJECTS_PATH=${PROJECTS_DIR}" >> .env
        echo -e "${GREEN}[OK]${NC} Set custom projects path in .env"
    fi
else
    echo -e "${GREEN}[OK]${NC} Using default projects path (~/Documents/GitHub)"
fi

echo ""
echo -e "  ${YELLOW}Next step:${NC} Edit .env to add your AI provider credentials,"
echo "  or skip that -- the setup wizard will guide you on first start."

# ---------------------------------------------------------------------------
# Check Docker
# ---------------------------------------------------------------------------
echo ""
if command -v docker &> /dev/null; then
    if docker info &> /dev/null; then
        echo -e "${GREEN}[OK]${NC} Docker is running."
    else
        echo -e "${RED}[ERROR]${NC} Docker is installed but not running."
        echo "  Please start Docker Desktop or Rancher Desktop and try again."
        exit 1
    fi
else
    echo -e "${RED}[ERROR]${NC} Docker is not installed."
    echo "  Please install Docker Desktop or Rancher Desktop:"
    echo "    https://www.docker.com/products/docker-desktop/"
    echo "    https://rancherdesktop.io/"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Ready! Run: docker compose up -d${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "  Then open ${BOLD}http://localhost:7681${NC} in your browser."
echo ""
