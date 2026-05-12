#!/usr/bin/env bash
# =============================================================================
# Git Credential Helper — wraps gh auth git-credential with auto-reauth
#
# If gh credential lookup fails (expired token), triggers login-wizard.sh
# for GitHub device-code flow, then retries the credential request.
#
# Configured via: git config --global credential.https://github.com.helper \
#   '!/opt/claude-code-docker/scripts/gh-credential-helper.sh'
# =============================================================================

set -euo pipefail

SCRIPTS_DIR="/opt/claude-code-docker/scripts"
ACTION="${1:-get}"

# Read stdin (git sends protocol/host/path on stdin)
INPUT=$(cat)

attempt_credential() {
    echo "$INPUT" | gh auth git-credential "$ACTION" 2>/dev/null
}

if [ "$ACTION" != "get" ]; then
    echo "$INPUT" | gh auth git-credential "$ACTION" 2>/dev/null || true
    exit 0
fi

# Try credential lookup
if RESULT=$(attempt_credential); then
    echo "$RESULT"
    exit 0
fi

# Credential failed — trigger reauth
echo "" >&2
echo "  GitHub session expired. Starting sign-in..." >&2
echo "" >&2

"$SCRIPTS_DIR/login-wizard.sh" --github-only >&2

# Retry after reauth
if RESULT=$(attempt_credential); then
    echo "$RESULT"
    exit 0
fi

echo "  GitHub sign-in failed. Run: gh auth login" >&2
exit 1
