#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Mount External Drives
# Double-click this file to add or remove drive mounts from your container.
# The container will restart briefly (~10 seconds) to apply changes.
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
echo -e "${BLUE}  Claude Code — Drive Manager${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# ---------------------------------------------------------------------------
# Check Docker is running
# ---------------------------------------------------------------------------
if ! docker info &>/dev/null; then
    echo -e "${RED}[!]${NC} Docker is not running. Start Docker Desktop first."
    echo ""
    read -p "Press Enter to close..."
    exit 1
fi

# ---------------------------------------------------------------------------
# Check container exists
# ---------------------------------------------------------------------------
if ! docker ps -a --format '{{.Names}}' | grep -q '^claude-code$'; then
    echo -e "${RED}[!]${NC} Claude Code container not found. Run install.command first."
    echo ""
    read -p "Press Enter to close..."
    exit 1
fi

# ---------------------------------------------------------------------------
# Load current EXTRA_MOUNTS from .env
# ---------------------------------------------------------------------------
ENV_FILE="$(pwd)/.env"
CURRENT_MOUNTS=""
if [ -f "$ENV_FILE" ]; then
    CURRENT_MOUNTS=$(grep '^EXTRA_MOUNTS=' "$ENV_FILE" 2>/dev/null | head -1 | sed 's/^EXTRA_MOUNTS=//')
fi

# ---------------------------------------------------------------------------
# Discover available volumes (macOS: /Volumes/*, Linux: /mnt/*, /media/*)
# ---------------------------------------------------------------------------
VOLUMES=()
SKIP_NAMES=("Macintosh HD" "Recovery" "Preboot" "VM" "com.apple" "Update")

if [ -d /Volumes ]; then
    for vol in /Volumes/*/; do
        vol="${vol%/}"
        name=$(basename "$vol")
        skip=false
        for s in "${SKIP_NAMES[@]}"; do
            [[ "$name" == *"$s"* ]] && skip=true && break
        done
        $skip && continue
        [ -d "$vol" ] && VOLUMES+=("$vol")
    done
fi

# Also check /mnt and /media (Linux)
for base in /mnt /media; do
    if [ -d "$base" ]; then
        for vol in "$base"/*/; do
            vol="${vol%/}"
            [ -d "$vol" ] && VOLUMES+=("$vol")
        done
    fi
done

if [ ${#VOLUMES[@]} -eq 0 ]; then
    echo -e "${YELLOW}[!]${NC} No external drives found."
    echo ""
    echo "  Plug in an external drive and try again."
    echo ""
    read -p "Press Enter to close..."
    exit 0
fi

# ---------------------------------------------------------------------------
# Show drive picker
# ---------------------------------------------------------------------------
echo -e "  Select drives to mount inside Claude Code."
echo -e "  ${DIM}Currently mounted drives are marked with [x].${NC}"
echo ""

# Parse current mounts into array
IFS='|' read -ra MOUNTED <<< "$CURRENT_MOUNTS"

SELECTED=()
i=1
for vol in "${VOLUMES[@]}"; do
    name=$(basename "$vol")
    # Check if already mounted
    marker=" "
    for m in "${MOUNTED[@]}"; do
        [ "$m" = "$vol" ] && marker="x" && break
    done

    # Show size if available
    size=""
    if command -v df &>/dev/null; then
        size=$(df -h "$vol" 2>/dev/null | tail -1 | awk '{print $2}')
        [ -n "$size" ] && size=" ${DIM}(${size})${NC}"
    fi

    echo -e "  ${BOLD}${i})${NC} [${marker}] ${name}${size}"
    echo -e "     ${DIM}${vol}${NC}"

    # Pre-select currently mounted
    [ "$marker" = "x" ] && SELECTED+=("$i")

    i=$((i + 1))
done

echo ""
echo -e "  Enter drive numbers to toggle (e.g., ${BOLD}1 3${NC}), or:"
echo -e "    ${BOLD}a${NC} = select all    ${BOLD}n${NC} = select none    ${BOLD}Enter${NC} = keep current"
echo ""
read -p "  Your choice: " CHOICE

# ---------------------------------------------------------------------------
# Process selection
# ---------------------------------------------------------------------------
NEW_MOUNTS=()

if [ -z "$CHOICE" ]; then
    # Keep current
    for m in "${MOUNTED[@]}"; do
        [ -n "$m" ] && NEW_MOUNTS+=("$m")
    done
elif [ "$CHOICE" = "a" ] || [ "$CHOICE" = "A" ]; then
    NEW_MOUNTS=("${VOLUMES[@]}")
elif [ "$CHOICE" = "n" ] || [ "$CHOICE" = "N" ]; then
    NEW_MOUNTS=()
else
    # Start with current mounts, toggle selected numbers
    for m in "${MOUNTED[@]}"; do
        [ -n "$m" ] && NEW_MOUNTS+=("$m")
    done

    for num in $CHOICE; do
        idx=$((num - 1))
        if [ $idx -ge 0 ] && [ $idx -lt ${#VOLUMES[@]} ]; then
            vol="${VOLUMES[$idx]}"
            # Toggle: if in list, remove; if not, add
            found=false
            TEMP_MOUNTS=()
            for m in "${NEW_MOUNTS[@]}"; do
                if [ "$m" = "$vol" ]; then
                    found=true
                else
                    TEMP_MOUNTS+=("$m")
                fi
            done
            if $found; then
                NEW_MOUNTS=("${TEMP_MOUNTS[@]}")
            else
                NEW_MOUNTS+=("$vol")
            fi
        fi
    done
fi

# ---------------------------------------------------------------------------
# Save to .env
# ---------------------------------------------------------------------------
MOUNT_STR=""
for m in "${NEW_MOUNTS[@]}"; do
    [ -n "$MOUNT_STR" ] && MOUNT_STR="${MOUNT_STR}|"
    MOUNT_STR="${MOUNT_STR}${m}"
done

if [ -f "$ENV_FILE" ]; then
    if grep -q '^EXTRA_MOUNTS=' "$ENV_FILE"; then
        # Update existing line
        sed -i.bak "s|^EXTRA_MOUNTS=.*|EXTRA_MOUNTS=${MOUNT_STR}|" "$ENV_FILE"
        rm -f "${ENV_FILE}.bak"
    else
        echo "" >> "$ENV_FILE"
        echo "# External drive mounts (managed by mount-drive.command)" >> "$ENV_FILE"
        echo "EXTRA_MOUNTS=${MOUNT_STR}" >> "$ENV_FILE"
    fi
else
    echo "EXTRA_MOUNTS=${MOUNT_STR}" > "$ENV_FILE"
fi

# ---------------------------------------------------------------------------
# Show what will happen
# ---------------------------------------------------------------------------
echo ""
if [ ${#NEW_MOUNTS[@]} -eq 0 ]; then
    echo -e "${YELLOW}[...]${NC} Removing all extra drive mounts..."
else
    echo -e "${YELLOW}[...]${NC} Mounting ${#NEW_MOUNTS[@]} drive(s):"
    for m in "${NEW_MOUNTS[@]}"; do
        echo -e "  ${GREEN}✓${NC} $(basename "$m")"
    done
fi

# ---------------------------------------------------------------------------
# Capture current container config and recreate
# ---------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[...]${NC} Restarting Claude Code with new mounts (takes ~10 seconds)..."

# Get current container's image
IMAGE=$(docker inspect claude-code --format '{{.Config.Image}}' 2>/dev/null)
[ -z "$IMAGE" ] && IMAGE="ghcr.io/sealmindset/claude-code-docker:latest"

# Get current port mappings
get_port() {
    docker inspect claude-code --format "{{(index (index .NetworkSettings.Ports \"$1\") 0).HostPort}}" 2>/dev/null
}
WELCOME_PORT=$(get_port "3000/tcp") ; [ -z "$WELCOME_PORT" ] && WELCOME_PORT=3000
TTYD_PORT=$(get_port "7681/tcp")    ; [ -z "$TTYD_PORT" ] && TTYD_PORT=7681
TTYD_NEW_PORT=$(get_port "7682/tcp"); [ -z "$TTYD_NEW_PORT" ] && TTYD_NEW_PORT=7682
CS_PORT=$(get_port "8080/tcp")      ; [ -z "$CS_PORT" ] && CS_PORT=8080
WS_PORT=$(get_port "9200/tcp")      ; [ -z "$WS_PORT" ] && WS_PORT=9200

# Get Docker socket GID
DOCKER_GID=$(stat -f '%g' /var/run/docker.sock 2>/dev/null || stat -c '%g' /var/run/docker.sock 2>/dev/null || echo "0")

# Standard volume mounts (must match install.command)
PROJECTS_DIR="$HOME/Documents"
AZURE_DIR="$HOME/.azure"
AWS_DIR="$HOME/.aws"

# Stop and remove
docker stop claude-code &>/dev/null
docker rm claude-code &>/dev/null

# Build volume args
VOL_ARGS=(
    -v /var/run/docker.sock:/var/run/docker.sock
    -v "$PROJECTS_DIR:/home/coder/Documents"
    -v "$HOME/Downloads:/home/coder/Downloads"
    -v "$HOME/Desktop:/home/coder/Desktop"
    -v "$AZURE_DIR:/home/coder/.azure"
    -v "$AWS_DIR:/home/coder/.aws"
    -v claude-code-data:/home/coder/.claude
    -v claude-code-gh:/home/coder/.config/gh
    -v claude-code-git-config:/home/coder/.gitconfig.d
    -v claude-code-local:/home/coder/.local
    -v claude-code-continue:/home/coder/.continue
    -v claude-code-npm:/home/coder/.npm
    -v claude-code-bash-history:/home/coder/.shell-persist
)

# Add extra drive mounts
for m in "${NEW_MOUNTS[@]}"; do
    name=$(basename "$m")
    VOL_ARGS+=(-v "$m:/home/coder/Drives/$name")
done

# Recreate container
if docker run -d \
    --name claude-code \
    --restart unless-stopped \
    --group-add "$DOCKER_GID" \
    --env-file "$ENV_FILE" \
    -p "${WELCOME_PORT}:3000" \
    -p "${TTYD_PORT}:7681" \
    -p "${TTYD_NEW_PORT}:7682" \
    -p "${CS_PORT}:8080" \
    -p "${WS_PORT}:9200" \
    "${VOL_ARGS[@]}" \
    "$IMAGE" &>/dev/null; then

    echo -e "${GREEN}[OK]${NC} Claude Code restarted with new mounts!"
    echo ""

    if [ ${#NEW_MOUNTS[@]} -gt 0 ]; then
        echo -e "  Your drives are available at:"
        for m in "${NEW_MOUNTS[@]}"; do
            name=$(basename "$m")
            echo -e "    ${GREEN}~/Drives/${name}${NC}"
        done
    fi
    echo ""
    echo -e "  Dashboard: ${GREEN}http://localhost:${WELCOME_PORT}${NC}"
    echo ""
else
    echo -e "${RED}[!]${NC} Failed to restart. Check Docker Desktop."
fi

read -p "Press Enter to close..."
