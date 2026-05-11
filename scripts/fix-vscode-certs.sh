#!/usr/bin/env bash
# =============================================================================
# Fix VSCode Extension Certificate Errors (Host-Side)
#
# Fixes: UNKNOWN_CERTIFICATE_VERIFICATION_ERROR in VSCode extensions
# (Claude, GitHub Copilot, etc.) caused by SSL inspection proxies
# (Zscaler, Netskope, Palo Alto GlobalProtect, etc.)
#
# What it does:
#   1. Finds SSL inspection proxy root CAs in macOS Keychain or Linux CA store
#   2. Exports them to ~/.ssl-proxy-certs/proxy-ca-bundle.pem
#   3. Sets NODE_EXTRA_CA_CERTS persistently in shell profile
#   4. Optionally patches VSCode settings.json
#
# Usage:
#   ./fix-vscode-certs.sh              # Auto-detect and fix
#   ./fix-vscode-certs.sh --check      # Check current status
#   ./fix-vscode-certs.sh --vscode     # Also patch VSCode settings.json
#   ./fix-vscode-certs.sh --quick-fix  # Disable proxyStrictSSL (fast workaround)
# =============================================================================

set -euo pipefail

CERT_DIR="$HOME/.ssl-proxy-certs"
CERT_FILE="$CERT_DIR/proxy-ca-bundle.pem"
PATCH_VSCODE=false
CHECK_ONLY=false
QUICK_FIX=false

# SSL inspection proxy patterns to search for
PROXY_PATTERNS=("Zscaler" "Netskope" "Palo Alto" "GlobalProtect" "Blue Coat" "Forcepoint" "Symantec Web" "ContentKeeper")

for arg in "$@"; do
  case "$arg" in
    --vscode)    PATCH_VSCODE=true ;;
    --check)     CHECK_ONLY=true ;;
    --quick-fix) QUICK_FIX=true ;;
    --help|-h)
      echo "Usage: $0 [--check] [--vscode] [--quick-fix]"
      echo ""
      echo "  --check      Show current certificate configuration status"
      echo "  --vscode     Also patch VSCode settings.json with terminal env"
      echo "  --quick-fix  Disable http.proxyStrictSSL in VSCode (fast but less secure)"
      exit 0
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

green()  { printf '\033[32m✓ %s\033[0m\n' "$1"; }
yellow() { printf '\033[33m⚠ %s\033[0m\n' "$1"; }
red()    { printf '\033[31m✗ %s\033[0m\n' "$1"; }
info()   { printf '  %s\n' "$1"; }

get_vscode_settings_path() {
  if [ "$(uname)" = "Darwin" ]; then
    echo "$HOME/Library/Application Support/Code/User/settings.json"
  else
    echo "$HOME/.config/Code/User/settings.json"
  fi
}

# ---------------------------------------------------------------------------
# Quick fix: just disable proxyStrictSSL
# ---------------------------------------------------------------------------

if $QUICK_FIX; then
  echo ""
  echo "=== Quick Fix: Disable SSL Strict Verification ==="
  echo ""
  yellow "This disables certificate verification in VSCode — use as a temporary workaround."
  info   "Run without --quick-fix to properly install proxy certificates instead."
  echo ""

  VS_SETTINGS="$(get_vscode_settings_path)"
  if [ ! -f "$VS_SETTINGS" ]; then
    mkdir -p "$(dirname "$VS_SETTINGS")"
    echo '{}' > "$VS_SETTINGS"
  fi

  python3 -c "
import json, sys
path = sys.argv[1]
with open(path) as f:
    s = json.load(f)
s['http.proxyStrictSSL'] = False
with open(path, 'w') as f:
    json.dump(s, f, indent=4)
print('Done')
" "$VS_SETTINGS" && green "Set http.proxyStrictSSL = false in VSCode settings"

  echo ""
  info "Restart VSCode for this to take effect."
  info "To undo: Settings → search 'proxy strict ssl' → check the box"
  echo ""
  exit 0
fi

# ---------------------------------------------------------------------------
# Check mode
# ---------------------------------------------------------------------------

if $CHECK_ONLY; then
  echo ""
  echo "=== SSL Proxy Certificate Status ==="
  echo ""

  if [ -f "$CERT_FILE" ]; then
    green "Proxy CA bundle: $CERT_FILE"
    CERT_COUNT=$(grep -c "BEGIN CERTIFICATE" "$CERT_FILE" 2>/dev/null || echo 0)
    info "  Contains $CERT_COUNT certificate(s)"
    # Show subjects
    openssl crl2pkcs7 -nocrl -certfile "$CERT_FILE" 2>/dev/null \
      | openssl pkcs7 -print_certs -noout 2>/dev/null \
      | grep "subject=" | while read -r line; do
        info "  $line"
      done
  else
    yellow "No proxy CA bundle at $CERT_FILE"
  fi

  echo ""
  if [ -n "${NODE_EXTRA_CA_CERTS:-}" ]; then
    green "NODE_EXTRA_CA_CERTS (session): $NODE_EXTRA_CA_CERTS"
  else
    yellow "NODE_EXTRA_CA_CERTS not set in current shell"
  fi

  # Check shell profile
  SHELL_RC=""
  for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    [ -f "$rc" ] && SHELL_RC="$rc" && break
  done
  if [ -n "$SHELL_RC" ] && grep -q "NODE_EXTRA_CA_CERTS" "$SHELL_RC" 2>/dev/null; then
    green "NODE_EXTRA_CA_CERTS persisted in $SHELL_RC"
  else
    yellow "NODE_EXTRA_CA_CERTS not in shell profile"
  fi

  # Check VSCode
  VS_SETTINGS="$(get_vscode_settings_path)"
  echo ""
  if [ -f "$VS_SETTINGS" ]; then
    SSL_VAL=$(python3 -c "import json; s=json.load(open('$VS_SETTINGS')); print(s.get('http.proxyStrictSSL', 'not set'))" 2>/dev/null || echo "parse error")
    info "VSCode http.proxyStrictSSL: $SSL_VAL"
  else
    info "VSCode settings.json not found"
  fi

  # Detect running proxy
  echo ""
  PROXY_FOUND=false
  if [ "$(uname)" = "Darwin" ]; then
    for p in Zscaler ZscalerApp Netskope GlobalProtect; do
      if pgrep -f "$p" &>/dev/null; then
        green "SSL proxy running: $p"
        PROXY_FOUND=true
      fi
    done
  fi
  if ! $PROXY_FOUND; then
    info "No SSL inspection proxy process detected"
  fi

  echo ""
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 1: Detect SSL inspection proxy
# ---------------------------------------------------------------------------

echo ""
echo "=== VSCode Certificate Fix ==="
echo ""

PROXY_DETECTED=false
DETECTED_NAME=""

if [ "$(uname)" = "Darwin" ]; then
  # macOS: search Keychain for proxy CAs
  for pattern in "${PROXY_PATTERNS[@]}"; do
    if security find-certificate -c "$pattern" /Library/Keychains/System.keychain &>/dev/null 2>&1 || \
       security find-certificate -c "$pattern" ~/Library/Keychains/login.keychain-db &>/dev/null 2>&1; then
      PROXY_DETECTED=true
      DETECTED_NAME="$pattern"
      break
    fi
  done
  # Also check running processes
  for p in Zscaler ZscalerApp Netskope GlobalProtect; do
    if pgrep -f "$p" &>/dev/null; then
      PROXY_DETECTED=true
      [ -z "$DETECTED_NAME" ] && DETECTED_NAME="$p"
    fi
  done
else
  # Linux: check CA directories
  for dir in /usr/local/share/ca-certificates /etc/pki/ca-trust/source/anchors; do
    for pattern in "${PROXY_PATTERNS[@]}"; do
      if find "$dir" -iname "*${pattern}*" -type f 2>/dev/null | grep -q .; then
        PROXY_DETECTED=true
        DETECTED_NAME="$pattern"
        break 2
      fi
    done
  done
fi

if ! $PROXY_DETECTED; then
  yellow "No SSL inspection proxy detected on this machine."
  info "If you're sure a proxy is installed, the certificate may be named differently."
  echo ""
  if [ "$(uname)" = "Darwin" ]; then
    info "Check: Keychain Access → System keychain → search for your proxy name"
  else
    info "Check: ls /usr/local/share/ca-certificates/"
  fi
  echo ""
  read -rp "Continue anyway? [y/N] " yn
  case "$yn" in [yY]*) ;; *) exit 0 ;; esac
else
  green "SSL inspection proxy detected: $DETECTED_NAME"
fi

# ---------------------------------------------------------------------------
# Step 2: Export proxy CA certificates
# ---------------------------------------------------------------------------

echo ""
echo "Exporting proxy root CA certificates..."

mkdir -p "$CERT_DIR"
: > "$CERT_FILE"  # Truncate

EXPORTED=0

if [ "$(uname)" = "Darwin" ]; then
  for pattern in "${PROXY_PATTERNS[@]}"; do
    # Try System keychain, then login keychain
    for keychain in /Library/Keychains/System.keychain ~/Library/Keychains/login.keychain-db; do
      CERTS=$(security find-certificate -a -c "$pattern" -p "$keychain" 2>/dev/null || true)
      if [ -n "$CERTS" ]; then
        echo "$CERTS" >> "$CERT_FILE"
        # Count certs found
        COUNT=$(echo "$CERTS" | grep -c "BEGIN CERTIFICATE" || true)
        if [ "$COUNT" -gt 0 ]; then
          info "  Found $COUNT cert(s) matching '$pattern' in $(basename "$keychain")"
          EXPORTED=$((EXPORTED + COUNT))
        fi
      fi
    done
  done
else
  for dir in /usr/local/share/ca-certificates /etc/pki/ca-trust/source/anchors /etc/ssl/certs; do
    for pattern in "${PROXY_PATTERNS[@]}"; do
      while IFS= read -r cert_file; do
        cat "$cert_file" >> "$CERT_FILE"
        EXPORTED=$((EXPORTED + 1))
        info "  Exported: $cert_file"
      done < <(find "$dir" -iname "*${pattern}*" -type f 2>/dev/null)
    done
  done
fi

if [ "$EXPORTED" -eq 0 ]; then
  red "No proxy certificates found to export."
  info "Try the quick-fix instead: $0 --quick-fix"
  rm -f "$CERT_FILE"
  exit 1
fi

# Validate at least one cert is valid PEM
if openssl x509 -in "$CERT_FILE" -noout -subject &>/dev/null; then
  green "Exported $EXPORTED certificate(s) to $CERT_FILE"
else
  red "Exported file does not contain valid certificates."
  rm -f "$CERT_FILE"
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 3: Set NODE_EXTRA_CA_CERTS
# ---------------------------------------------------------------------------

echo ""
echo "Setting NODE_EXTRA_CA_CERTS..."

EXPORT_LINE="export NODE_EXTRA_CA_CERTS=\"$CERT_FILE\""

# Find shell profile
SHELL_RC=""
for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
  [ -f "$rc" ] && SHELL_RC="$rc" && break
done
[ -z "$SHELL_RC" ] && SHELL_RC="$HOME/.zshrc" && touch "$SHELL_RC"

if grep -q "NODE_EXTRA_CA_CERTS" "$SHELL_RC" 2>/dev/null; then
  # Update existing
  if [ "$(uname)" = "Darwin" ]; then
    sed -i '' "s|.*NODE_EXTRA_CA_CERTS.*|$EXPORT_LINE|" "$SHELL_RC"
  else
    sed -i "s|.*NODE_EXTRA_CA_CERTS.*|$EXPORT_LINE|" "$SHELL_RC"
  fi
  green "Updated NODE_EXTRA_CA_CERTS in $SHELL_RC"
else
  {
    echo ""
    echo "# SSL proxy CA certificates for Node.js / VSCode extensions (added by CCDW)"
    echo "$EXPORT_LINE"
  } >> "$SHELL_RC"
  green "Added NODE_EXTRA_CA_CERTS to $SHELL_RC"
fi

export NODE_EXTRA_CA_CERTS="$CERT_FILE"

# ---------------------------------------------------------------------------
# Step 4: Patch VSCode settings (optional)
# ---------------------------------------------------------------------------

if $PATCH_VSCODE; then
  echo ""
  echo "Patching VSCode settings..."

  VS_SETTINGS="$(get_vscode_settings_path)"
  if [ ! -f "$VS_SETTINGS" ]; then
    mkdir -p "$(dirname "$VS_SETTINGS")"
    echo '{}' > "$VS_SETTINGS"
  fi

  python3 -c "
import json, sys, platform

path = sys.argv[1]
cert = sys.argv[2]

with open(path) as f:
    settings = json.load(f)

# Set NODE_EXTRA_CA_CERTS in VSCode terminal env
if platform.system() == 'Darwin':
    env_key = 'terminal.integrated.env.osx'
elif platform.system() == 'Windows':
    env_key = 'terminal.integrated.env.windows'
else:
    env_key = 'terminal.integrated.env.linux'

if env_key not in settings:
    settings[env_key] = {}
settings[env_key]['NODE_EXTRA_CA_CERTS'] = cert

# Keep proxyStrictSSL true (proper cert fix, no need to disable)
if 'http.proxyStrictSSL' not in settings:
    settings['http.proxyStrictSSL'] = True

with open(path, 'w') as f:
    json.dump(settings, f, indent=4)
print('Updated')
" "$VS_SETTINGS" "$CERT_FILE" && green "VSCode settings patched"
fi

# ---------------------------------------------------------------------------
# Step 5: Verify
# ---------------------------------------------------------------------------

echo ""
echo "=== Verification ==="

if command -v node &>/dev/null; then
  RESULT=$(timeout 10 env NODE_EXTRA_CA_CERTS="$CERT_FILE" node -e "
    const https = require('https');
    const req = https.get('https://api.anthropic.com', {timeout: 5000}, (res) => {
      console.log('OK:' + res.statusCode);
      process.exit(0);
    });
    req.on('error', (e) => { console.log('FAIL:' + e.code); process.exit(1); });
    req.on('timeout', () => { console.log('FAIL:TIMEOUT'); req.destroy(); process.exit(1); });
  " 2>&1 || echo "FAIL:TIMEOUT")

  if echo "$RESULT" | grep -q "OK:"; then
    green "Node.js connects to api.anthropic.com with proxy CA — certificate fix working"
  else
    yellow "Connection test: $RESULT"
    info "The cert may not cover this domain, or network may be blocking it."
    info "Try the quick-fix as a workaround: $0 --quick-fix"
  fi
else
  yellow "Node.js not found — skipping connection test"
fi

echo ""
green "Done! Restart VSCode for changes to take effect."
echo ""
echo "  If you still see UNKNOWN_CERTIFICATE_VERIFICATION_ERROR:"
echo "    1. Fully quit and reopen VSCode (Cmd+Q / Alt+F4, not just reload)"
echo "    2. Verify env var: echo \$NODE_EXTRA_CA_CERTS"
echo "    3. Quick workaround: $0 --quick-fix"
echo ""
