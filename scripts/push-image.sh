#!/usr/bin/env bash
# =============================================================================
# Build and push Docker image to both GHCR and ACR
# Usage: ./scripts/push-image.sh [--skip-build]
# Requires: Zscaler disabled (for ACR), az cli, docker
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GHCR_IMAGE="ghcr.io/sealmindset/claude-code-docker:latest"
ACR_NAME="${ACR_NAME:-dockyardgwprod}"
ACR_HOST="${ACR_NAME}.azurecr.io"
ACR_IMAGE="${ACR_HOST}/claude-code-docker:latest"
ACR_SUBSCRIPTION="${ACR_SUBSCRIPTION:-f1e6d3a4-b486-4abc-8352-2f8f540540b4}"
AI_SUBSCRIPTION="${AI_SUBSCRIPTION:-a8da1709-ccc3-4356-b3b7-6660af86e979}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# --- Pre-flight: check Zscaler ---
echo -e "${YELLOW}[...]${NC} Checking ACR connectivity..."
if ! curl -s --connect-timeout 5 "https://${ACR_HOST}/v2/" -o /dev/null -w '' 2>/dev/null; then
    echo -e "${RED}[!]${NC} Cannot reach ${ACR_HOST}. Disable Zscaler first."
    exit 1
fi
echo -e "${GREEN}[OK]${NC} ACR reachable."

# --- Build multi-platform ---
if [[ "${1:-}" != "--skip-build" ]]; then
    echo -e "${YELLOW}[...]${NC} Building multi-platform image (amd64 + arm64)..."
    # Ensure buildx builder exists
    docker buildx inspect multiarch >/dev/null 2>&1 || \
        docker buildx create --name multiarch --use
    docker buildx use multiarch
    docker buildx build \
        --platform linux/amd64,linux/arm64 \
        -t "$GHCR_IMAGE" \
        -t "$ACR_IMAGE" \
        --push \
        "$REPO_ROOT"
    echo -e "${GREEN}[OK]${NC} Multi-platform build pushed to GHCR and ACR."
    # Pull back for local use
    docker pull "$GHCR_IMAGE"
    echo -e "${GREEN}[OK]${NC} Local image updated."
    echo ""
    echo -e "${GREEN}[OK]${NC} Both registries updated:"
    echo "  GHCR: $GHCR_IMAGE"
    echo "  ACR:  $ACR_IMAGE"
    echo ""
    echo "Safe to re-enable Zscaler."
    exit 0
else
    echo -e "${GREEN}[OK]${NC} Skipping build (--skip-build)."
fi

# --- Tag for ACR (skip-build path only) ---
docker tag "$GHCR_IMAGE" "$ACR_IMAGE"

# --- Auth: ACR (refresh token if needed) ---
echo -e "${YELLOW}[...]${NC} Logging in to ACR..."
if ! az acr login --name "$ACR_NAME" --subscription "$ACR_SUBSCRIPTION" 2>/dev/null; then
    echo -e "${YELLOW}[...]${NC} ACR login failed. Signing in to Azure..."
    az login --use-device-code
    az acr login --name "$ACR_NAME" --subscription "$ACR_SUBSCRIPTION"
fi
# Restore default subscription to AI Foundry (sn-openai-dev-01)
az account set --subscription "$AI_SUBSCRIPTION" 2>/dev/null || true
echo -e "${GREEN}[OK]${NC} ACR authenticated. Default subscription: sn-openai-dev-01."

# --- Push both ---
echo -e "${YELLOW}[...]${NC} Pushing to GHCR..."
docker push "$GHCR_IMAGE"
echo -e "${GREEN}[OK]${NC} GHCR done."

echo -e "${YELLOW}[...]${NC} Pushing to ACR..."
docker push "$ACR_IMAGE"
echo -e "${GREEN}[OK]${NC} ACR done."

echo ""
echo -e "${GREEN}[OK]${NC} Both registries updated:"
echo "  GHCR: $GHCR_IMAGE"
echo "  ACR:  $ACR_IMAGE"
echo ""
echo "Safe to re-enable Zscaler."
