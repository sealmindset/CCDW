#!/usr/bin/env bash
# =============================================================================
# Claude Code Docker - Connection Troubleshooter
# Checks everything and reports a plain-English health summary.
# Run this when something feels wrong: /opt/claude-code-docker/scripts/doctor.sh
# =============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
WARN=0
FAIL=0

pass() {
    echo -e "  ${GREEN}[PASS]${NC} $1"
    PASS=$(( PASS + 1 ))
}

warn() {
    echo -e "  ${YELLOW}[WARN]${NC} $1"
    WARN=$(( WARN + 1 ))
}

fail() {
    echo -e "  ${RED}[FAIL]${NC} $1"
    FAIL=$(( FAIL + 1 ))
}

hint() {
    echo -e "         ${YELLOW}Fix:${NC} $1"
}

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Claude Code Docker - Health Check${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# ---------------------------------------------------------------------------
# 1. Services
# ---------------------------------------------------------------------------
echo -e "${BOLD}Services${NC}"

if curl -s -o /dev/null http://127.0.0.1:7681/ 2>/dev/null; then
    pass "Web terminal (ttyd) is running on port 7681"
else
    fail "Web terminal (ttyd) is NOT responding on port 7681"
    hint "Run: docker restart claude-code"
fi

if curl -s -o /dev/null http://127.0.0.1:8080/ 2>/dev/null; then
    pass "VS Code (code-server) is running on port 8080"
else
    fail "VS Code (code-server) is NOT responding on port 8080"
    hint "The health monitor should restart it automatically. If not: docker restart claude-code"
fi

echo ""

# ---------------------------------------------------------------------------
# 2. AI Provider
# ---------------------------------------------------------------------------
echo -e "${BOLD}AI Provider${NC}"

if [ -n "$ANTHROPIC_API_KEY" ]; then
    pass "Anthropic API key is set"
elif [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
    pass "Azure AI Foundry endpoint is configured: $ANTHROPIC_FOUNDRY_BASE_URL"

    # Check Azure CLI
    if command -v az &> /dev/null; then
        pass "Azure CLI is installed"
    else
        fail "Azure CLI is not installed"
        hint "This shouldn't happen in the container -- try rebuilding the image"
    fi

    # Check Azure login
    if az account show &>/dev/null 2>&1; then
        pass "Azure CLI is logged in"

        # Check token
        TOKEN_JSON=$(az account get-access-token --resource https://cognitiveservices.azure.com 2>/dev/null)
        if [ $? -eq 0 ]; then
            EXPIRES_ON=$(echo "$TOKEN_JSON" | grep -o '"expiresOn"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"expiresOn"[[:space:]]*:[[:space:]]*"//' | sed 's/"//')
            if [ -n "$EXPIRES_ON" ]; then
                EXPIRY_EPOCH=$(date -d "$EXPIRES_ON" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$EXPIRES_ON" +%s 2>/dev/null)
                NOW_EPOCH=$(date +%s)
                if [ -n "$EXPIRY_EPOCH" ]; then
                    REMAINING=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 60 ))
                    if [ "$REMAINING" -le 0 ]; then
                        fail "Azure token has expired"
                        hint "Run: login"
                    elif [ "$REMAINING" -le 10 ]; then
                        warn "Azure token expires in $REMAINING minutes"
                        hint "Run: login"
                    else
                        pass "Azure token is valid ($REMAINING minutes remaining)"
                    fi
                else
                    pass "Azure token obtained (could not parse expiry)"
                fi
            else
                pass "Azure token obtained"
            fi
        else
            fail "Could not get Azure access token"
            hint "Run: login"
        fi
    else
        fail "Azure CLI is not logged in"
        hint "Run: login"
    fi
elif [ "${CLAUDE_CODE_USE_BEDROCK}" = "1" ]; then
    pass "AWS Bedrock is configured"
    if [ -n "$AWS_ACCESS_KEY_ID" ]; then
        pass "AWS access key is set"
    else
        warn "AWS_ACCESS_KEY_ID is not set"
        hint "Add AWS_ACCESS_KEY_ID to your .env file"
    fi
else
    fail "No AI provider is configured"
    hint "Run the setup wizard: /opt/claude-code-docker/scripts/setup-wizard.sh"
fi

echo ""

# ---------------------------------------------------------------------------
# 3. Network
# ---------------------------------------------------------------------------
echo -e "${BOLD}Network${NC}"

# General internet
if curl -s --connect-timeout 5 -o /dev/null https://www.google.com 2>/dev/null; then
    pass "Internet connection is working"
else
    fail "Cannot reach the internet"
    hint "Check your network connection and VPN status"
fi

# AI endpoint
if [ -n "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
    if curl -s --connect-timeout 5 -o /dev/null "$ANTHROPIC_FOUNDRY_BASE_URL" 2>/dev/null; then
        pass "AI endpoint is reachable: $ANTHROPIC_FOUNDRY_BASE_URL"
    else
        fail "Cannot reach AI endpoint: $ANTHROPIC_FOUNDRY_BASE_URL"
        hint "Make sure you're connected to VPN (if required)"
    fi
elif [ -n "$ANTHROPIC_API_KEY" ]; then
    if curl -s --connect-timeout 5 -o /dev/null https://api.anthropic.com 2>/dev/null; then
        pass "Anthropic API is reachable"
    else
        fail "Cannot reach Anthropic API"
        hint "Check your internet connection"
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# 4. GitHub
# ---------------------------------------------------------------------------
echo -e "${BOLD}GitHub${NC}"

if command -v gh &> /dev/null; then
    pass "GitHub CLI is installed"
    if gh auth status &>/dev/null 2>&1; then
        GH_USER=$(gh api user -q .login 2>/dev/null || echo "authenticated")
        pass "GitHub CLI is authenticated ($GH_USER)"
    else
        warn "GitHub CLI is not authenticated"
        hint "Run: gh auth login"
    fi
else
    fail "GitHub CLI is not installed"
fi

echo ""

# ---------------------------------------------------------------------------
# 5. Docker
# ---------------------------------------------------------------------------
echo -e "${BOLD}Docker${NC}"

if [ -S /var/run/docker.sock ]; then
    pass "Docker socket is mounted"
else
    warn "Docker socket is not mounted"
    hint "Add -v /var/run/docker.sock:/var/run/docker.sock to your docker run command"
fi

if docker info >/dev/null 2>&1; then
    pass "Docker is accessible (can build and run apps)"
else
    warn "Docker commands are not working"
    hint "Check Docker socket permissions (the container needs access to /var/run/docker.sock)"
fi

echo ""

# ---------------------------------------------------------------------------
# 5. Workspace & Disk
# ---------------------------------------------------------------------------
echo -e "${BOLD}Workspace & Disk${NC}"

GITHUB_DIR="/home/coder/Documents/GitHub"
if [ -d "$GITHUB_DIR" ]; then
    pass "Projects folder exists: $GITHUB_DIR"
else
    fail "Projects folder is missing: $GITHUB_DIR"
    hint "Check your volume mount in docker-compose.yml or docker run command"
fi

if [ -w "$GITHUB_DIR" ]; then
    pass "Projects folder is writable"
else
    fail "Projects folder is NOT writable"
    hint "Check file permissions on your host's projects folder"
fi

# Disk space (warn if less than 1GB free)
AVAIL_KB=$(df -k "$GITHUB_DIR" 2>/dev/null | tail -1 | awk '{print $4}')
if [ -n "$AVAIL_KB" ]; then
    AVAIL_MB=$(( AVAIL_KB / 1024 ))
    AVAIL_GB=$(( AVAIL_MB / 1024 ))
    if [ "$AVAIL_MB" -lt 1024 ]; then
        warn "Low disk space: ${AVAIL_MB}MB free"
        hint "Free up disk space on your host machine"
    else
        pass "Disk space: ${AVAIL_GB}GB free"
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# 6. Skills
# ---------------------------------------------------------------------------
echo -e "${BOLD}Skills${NC}"

if [ -d /home/coder/.claude/make-it ]; then
    VERSION=$(cat /home/coder/.claude/make-it/VERSION 2>/dev/null || echo "unknown")
    pass "/make-it skills installed (v$VERSION)"
else
    warn "/make-it skills are not installed"
    hint "Run: curl -fsSL https://raw.githubusercontent.com/sealmindset/make-it/main/install.sh | bash"
fi

if [ -d /home/coder/.claude/commands ]; then
    CMD_COUNT=$(ls /home/coder/.claude/commands/*.md 2>/dev/null | wc -l)
    pass "$CMD_COUNT skill commands available"
else
    warn "No skill commands found"
fi

echo ""

# ---------------------------------------------------------------------------
# 7. Self-Healing Status
# ---------------------------------------------------------------------------
echo -e "${BOLD}Self-Healing${NC}"

SH_STATE_FILE="/tmp/.health-state.json"
SH_TELEMETRY_FILE="/home/coder/.claude/health-telemetry.jsonl"

if [ -f "$SH_STATE_FILE" ]; then
    SH_STATUS=$(python3 -c "import json; print(json.load(open('$SH_STATE_FILE')).get('status','unknown'))" 2>/dev/null || echo "unknown")
    SH_MSG=$(python3 -c "import json; print(json.load(open('$SH_STATE_FILE')).get('message',''))" 2>/dev/null || echo "")
    SH_FAILURES=$(python3 -c "import json; print(json.load(open('$SH_STATE_FILE')).get('recent_failures_1h',0))" 2>/dev/null || echo "0")
    SH_LAST=$(python3 -c "import json; print(json.load(open('$SH_STATE_FILE')).get('last_check',''))" 2>/dev/null || echo "")

    case "$SH_STATUS" in
        healthy)  pass "Status: healthy -- ${SH_MSG}" ;;
        degraded) warn "Status: degraded -- ${SH_MSG}" ;;
        unhealthy) fail "Status: unhealthy -- ${SH_MSG}" ;;
        *)        warn "Status: ${SH_STATUS}" ;;
    esac

    if [ "$SH_FAILURES" -gt 0 ]; then
        warn "Failures in last hour: ${SH_FAILURES}"
    else
        pass "No failures in the last hour"
    fi

    [ -n "$SH_LAST" ] && echo -e "         Last check: ${SH_LAST}"
else
    warn "Health monitor state not found (may not be running)"
    hint "Health monitor starts automatically with the container"
fi

# Telemetry history (last 5 events)
if [ -f "$SH_TELEMETRY_FILE" ]; then
    EVENT_COUNT=$(wc -l < "$SH_TELEMETRY_FILE" 2>/dev/null || echo 0)
    pass "Telemetry log: ${EVENT_COUNT} events recorded"

    echo ""
    echo -e "  ${BOLD}Recent Events:${NC}"
    tail -5 "$SH_TELEMETRY_FILE" 2>/dev/null | while IFS= read -r line; do
        TS=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('ts',''))" 2>/dev/null || echo "?")
        TYPE=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('type',''))" 2>/dev/null || echo "?")
        RESULT=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('result',''))" 2>/dev/null || echo "?")
        if [ "$RESULT" = "success" ]; then
            echo -e "    ${GREEN}$TS${NC}  $TYPE  ${GREEN}$RESULT${NC}"
        else
            echo -e "    ${YELLOW}$TS${NC}  $TYPE  ${RED}$RESULT${NC}"
        fi
    done
else
    warn "No telemetry history yet"
fi

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo -e "${BLUE}========================================${NC}"
TOTAL=$(( PASS + WARN + FAIL ))

if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
    echo -e "  ${GREEN}All $TOTAL checks passed! Everything looks healthy.${NC}"
elif [ "$FAIL" -eq 0 ]; then
    echo -e "  ${GREEN}$PASS passed${NC}, ${YELLOW}$WARN warnings${NC}"
    echo -e "  Things are working but could be improved."
else
    echo -e "  ${GREEN}$PASS passed${NC}, ${YELLOW}$WARN warnings${NC}, ${RED}$FAIL failed${NC}"
    echo -e "  Check the ${RED}[FAIL]${NC} items above for fixes."
fi
echo -e "${BLUE}========================================${NC}"
echo ""
