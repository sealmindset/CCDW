#!/usr/bin/env bash
# =============================================================================
# In-container mount-drive helper
# Shows currently mounted drives and tells the user how to add more.
# =============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
DIM='\033[2m'
NC='\033[0m'

echo ""
echo -e "${BLUE}Drive Manager${NC}"
echo ""

# Show currently mounted drives
if [ -d /home/coder/Drives ] && [ "$(ls -A /home/coder/Drives 2>/dev/null)" ]; then
    echo -e "  ${GREEN}Mounted drives:${NC}"
    for drive in /home/coder/Drives/*/; do
        [ -d "$drive" ] || continue
        name=$(basename "$drive")
        size=$(df -h "$drive" 2>/dev/null | tail -1 | awk '{print $2 " total, " $4 " free"}')
        echo -e "    ${GREEN}✓${NC} ${name}  ${DIM}${size}${NC}"
        echo -e "      ${DIM}~/Drives/${name}${NC}"
    done
    echo ""
else
    echo -e "  ${DIM}No external drives mounted.${NC}"
    echo ""
fi

echo -e "  To add or remove drives:"
echo -e "    ${YELLOW}Double-click mount-drive.command${NC} on your Mac"
echo -e "    ${DIM}(in the Claude Code Docker folder)${NC}"
echo ""
echo -e "  The container restarts briefly (~10 sec) to apply changes."
echo -e "  All your work and settings are preserved."
echo ""
