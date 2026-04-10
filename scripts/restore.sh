#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Restore
# Restores settings from a backup archive created by backup.sh.
# Usage: restore <backup-file>
# =============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BACKUP_FILE="$1"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Claude Code Docker - Restore${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [ -z "$BACKUP_FILE" ]; then
    echo -e "${RED}[ERROR]${NC} Please provide a backup file."
    echo ""
    echo -e "  Usage: ${GREEN}restore /path/to/claude-code-backup-YYYYMMDD-HHMMSS.tar.gz${NC}"
    echo ""
    echo "  Available backups in your projects folder:"
    ls -1 /home/coder/Documents/GitHub/claude-code-backup-*.tar.gz 2>/dev/null || echo "    (none found)"
    echo ""
    exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo -e "${RED}[ERROR]${NC} File not found: $BACKUP_FILE"
    exit 1
fi

# ---------------------------------------------------------------------------
# Extract to temp directory
# ---------------------------------------------------------------------------
RESTORE_DIR=$(mktemp -d)
echo -e "${YELLOW}[...]${NC} Extracting backup..."
tar -xzf "$BACKUP_FILE" -C "$RESTORE_DIR" 2>/dev/null

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} Failed to extract backup. Is this a valid backup file?"
    rm -rf "$RESTORE_DIR"
    exit 1
fi

# ---------------------------------------------------------------------------
# Restore files
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[...]${NC} Restoring settings..."

# Claude Code settings
if [ -d "$RESTORE_DIR/claude" ]; then
    mkdir -p /home/coder/.claude
    cp "$RESTORE_DIR/claude/settings.json" /home/coder/.claude/ 2>/dev/null && \
        echo -e "  ${GREEN}[OK]${NC} Claude settings restored"
    if [ -d "$RESTORE_DIR/claude/commands" ]; then
        cp -r "$RESTORE_DIR/claude/commands" /home/coder/.claude/ 2>/dev/null && \
            echo -e "  ${GREEN}[OK]${NC} Custom commands restored"
    fi
    cp "$RESTORE_DIR/claude/get-claude-token.sh" /home/coder/.claude/ 2>/dev/null && \
        chmod +x /home/coder/.claude/get-claude-token.sh && \
        echo -e "  ${GREEN}[OK]${NC} Token helper restored"
fi

# Git config
if [ -d "$RESTORE_DIR/git" ]; then
    cp "$RESTORE_DIR/git/.gitconfig" /home/coder/ 2>/dev/null && \
        echo -e "  ${GREEN}[OK]${NC} Git config restored"
    if [ -d "$RESTORE_DIR/git/.gitconfig.d" ]; then
        cp -r "$RESTORE_DIR/git/.gitconfig.d" /home/coder/ 2>/dev/null && \
            echo -e "  ${GREEN}[OK]${NC} Git config extras restored"
    fi
fi

# Environment
if [ -d "$RESTORE_DIR/env" ] && [ -f "$RESTORE_DIR/env/.env" ]; then
    cp "$RESTORE_DIR/env/.env" /home/coder/Documents/GitHub/.env 2>/dev/null && \
        echo -e "  ${GREEN}[OK]${NC} Environment file restored"
fi

# Shell customizations
if [ -f "$RESTORE_DIR/.bashrc" ]; then
    cp "$RESTORE_DIR/.bashrc" /home/coder/ 2>/dev/null && \
        echo -e "  ${GREEN}[OK]${NC} Shell config restored"
fi

# Cleanup
rm -rf "$RESTORE_DIR"

echo ""
echo -e "${GREEN}[OK]${NC} Restore complete!"
echo ""
echo -e "  ${YELLOW}Note:${NC} You may need to restart the container for all changes to take effect."
echo ""
