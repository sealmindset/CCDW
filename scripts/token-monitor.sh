#!/usr/bin/env bash
# =============================================================================
# Azure Token Idle Monitor (Item #10)
# Background process that checks Azure token expiry every 5 minutes.
# Writes a warning file that shell-init.sh picks up on next prompt.
# =============================================================================

WARNING_FILE="/tmp/.azure-token-warning"
CHECK_INTERVAL=300   # 5 minutes

# Only run if Azure AI Foundry is configured
if [ -z "$ANTHROPIC_FOUNDRY_BASE_URL" ]; then
    exit 0
fi

while true; do
    sleep "$CHECK_INTERVAL"

    # Try to get token and check expiry
    TOKEN_JSON=$(az account get-access-token --resource https://cognitiveservices.azure.com 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "expired" > "$WARNING_FILE"
        continue
    fi

    EXPIRES_ON=$(echo "$TOKEN_JSON" | grep -o '"expiresOn"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"expiresOn"[[:space:]]*:[[:space:]]*"//' | sed 's/"//')
    if [ -n "$EXPIRES_ON" ]; then
        EXPIRY_EPOCH=$(date -d "$EXPIRES_ON" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$EXPIRES_ON" +%s 2>/dev/null)
        NOW_EPOCH=$(date +%s)

        if [ -n "$EXPIRY_EPOCH" ]; then
            REMAINING=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 60 ))

            if [ "$REMAINING" -le 0 ]; then
                echo "expired" > "$WARNING_FILE"
            elif [ "$REMAINING" -le 10 ]; then
                echo "$REMAINING" > "$WARNING_FILE"
            else
                rm -f "$WARNING_FILE"
            fi
        fi
    fi
done
