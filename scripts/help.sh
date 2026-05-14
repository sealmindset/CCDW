#!/usr/bin/env bash
# =============================================================================
# Help — shows available commands in plain language
# =============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

echo ""
echo -e "${BLUE}  Available Commands${NC}"
echo ""
echo -e "  ${BOLD}Getting Started${NC}"
echo -e "    ${GREEN}claude${NC}          Start the AI assistant"
echo -e "    ${GREEN}cc${NC}              Same as claude (shortcut)"
echo -e "    ${GREEN}login${NC}           Sign in to Azure / GitHub"
echo -e "    ${GREEN}doctor${NC}          Check if everything is working"
echo ""
echo -e "  ${BOLD}Files & Folders${NC}"
echo -e "    ${GREEN}dir${NC}             List files (like Windows Explorer)"
echo -e "    ${GREEN}cd ${DIM}folder${NC}       Go into a folder"
echo -e "    ${GREEN}cd ..${NC}           Go up one folder"
echo -e "    ${GREEN}copy ${DIM}a b${NC}       Copy file a to b"
echo -e "    ${GREEN}move ${DIM}a b${NC}       Move or rename a file"
echo -e "    ${GREEN}del ${DIM}file${NC}       Delete a file"
echo -e "    ${GREEN}md ${DIM}name${NC}        Create a new folder"
echo -e "    ${GREEN}type ${DIM}file${NC}      Show file contents"
echo -e "    ${GREEN}edit ${DIM}file${NC}      Edit a file (nano editor)"
echo -e "    ${GREEN}find-file ${DIM}name${NC} Search for a file"
echo -e "    ${GREEN}tree${NC}            Show folder structure"
echo ""
echo -e "  ${BOLD}Drives & Storage${NC}"
echo -e "    ${GREEN}drives${NC}          Show mounted external drives"
echo -e "    ${GREEN}mount-drive${NC}     Instructions to add a drive"
echo ""
echo -e "  ${BOLD}System${NC}"
echo -e "    ${GREEN}cls${NC}             Clear the screen"
echo -e "    ${GREEN}whoami${NC}          Show your username"
echo -e "    ${GREEN}ipconfig${NC}        Show network info"
echo -e "    ${GREEN}tasklist${NC}        Show running processes"
echo -e "    ${GREEN}systeminfo${NC}      Show system info"
echo ""
echo -e "  ${BOLD}Backup & Recovery${NC}"
echo -e "    ${GREEN}backup${NC}          Back up your settings"
echo -e "    ${GREEN}restore${NC}         Restore settings from backup"
echo ""
echo -e "  ${BOLD}File Transfer${NC}"
echo -e "    ${GREEN}send ${DIM}file${NC}      Copy a file to your Desktop"
echo -e "    ${GREEN}fetch ${DIM}file${NC}     Grab a file from Desktop or Downloads"
echo ""
echo -e "  ${BOLD}Copy & Paste${NC}"
echo -e "    ${YELLOW}Text:${NC}   Ctrl+V (or Cmd+V) pastes into terminal"
echo -e "    ${YELLOW}Files:${NC}  Drop files on your Desktop or Downloads folder"
echo -e "            They appear instantly at ~/Desktop and ~/Downloads"
echo ""
echo -e "  ${DIM}Tip: Your Documents, Downloads, and Desktop folders are${NC}"
echo -e "  ${DIM}shared with your computer. Changes sync both ways.${NC}"
echo ""
