#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Backup
# Creates a zip of all settings and config for easy restore.
# Usage: backup [output-path]
# =============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DEFAULT_OUTPUT="/home/coder/Documents/GitHub/claude-code-backup-${TIMESTAMP}.tar.gz"
OUTPUT="${1:-$DEFAULT_OUTPUT}"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Claude Code Docker - Backup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Create temp directory for backup contents
BACKUP_DIR=$(mktemp -d)
mkdir -p "$BACKUP_DIR/claude" "$BACKUP_DIR/git" "$BACKUP_DIR/env"

# ---------------------------------------------------------------------------
# Collect settings
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[...]${NC} Collecting settings..."

# Claude Code settings (but not the huge cache/data)
if [ -d /home/coder/.claude ]; then
    cp -r /home/coder/.claude/settings.json "$BACKUP_DIR/claude/" 2>/dev/null
    cp -r /home/coder/.claude/commands "$BACKUP_DIR/claude/" 2>/dev/null
    cp /home/coder/.claude/get-claude-token.sh "$BACKUP_DIR/claude/" 2>/dev/null
    # Save make-it version for reference
    cat /home/coder/.claude/make-it/VERSION > "$BACKUP_DIR/claude/make-it-version.txt" 2>/dev/null
fi

# Git config
if [ -f /home/coder/.gitconfig ]; then
    cp /home/coder/.gitconfig "$BACKUP_DIR/git/"
fi
if [ -d /home/coder/.gitconfig.d ]; then
    cp -r /home/coder/.gitconfig.d "$BACKUP_DIR/git/"
fi

# Environment files
if [ -f /home/coder/Documents/GitHub/.env ]; then
    cp /home/coder/Documents/GitHub/.env "$BACKUP_DIR/env/"
fi

# Shell customizations
if [ -f /home/coder/.bashrc ]; then
    cp /home/coder/.bashrc "$BACKUP_DIR/"
fi

# ---------------------------------------------------------------------------
# Create archive
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[...]${NC} Creating backup archive..."

tar -czf "$OUTPUT" -C "$BACKUP_DIR" . 2>/dev/null
rm -rf "$BACKUP_DIR"

if [ -f "$OUTPUT" ]; then
    SIZE=$(du -h "$OUTPUT" | cut -f1)
    echo -e "${GREEN}[OK]${NC} Backup created: $OUTPUT ($SIZE)"
    echo ""
    echo -e "  To restore on a new container, copy this file there and run:"
    echo -e "    ${GREEN}restore $OUTPUT${NC}"
else
    echo -e "${RED}[ERROR]${NC} Failed to create backup."
    exit 1
fi

echo ""
