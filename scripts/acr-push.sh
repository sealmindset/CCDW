#!/usr/bin/env bash
# Push the pre-built image to ACR so install.bat Try 1 works for Zscaler users.
# Run from repo root: ./scripts/acr-push.sh
set -euo pipefail

ACR_NAME="${ACR_NAME:-dockyardgwprod}"
ACR_HOST="${ACR_NAME}.azurecr.io"
IMAGE="claude-code-docker:latest"
SUBSCRIPTION="${ACR_SUBSCRIPTION:-f1e6d3a4-b486-4abc-8352-2f8f540540b4}"

echo "Building image..."
docker build --platform linux/amd64 -t "${ACR_HOST}/${IMAGE}" .

echo "Logging in to ${ACR_HOST}..."
az acr login --name "${ACR_NAME}" --subscription "${SUBSCRIPTION}"

echo "Pushing ${ACR_HOST}/${IMAGE}..."
docker push "${ACR_HOST}/${IMAGE}"

echo "Importing base images..."
az acr import --name "${ACR_NAME}" --source docker.io/library/node:20-alpine \
  --image node:20-alpine --subscription "${SUBSCRIPTION}" --force

echo "Done. ACR images:"
az acr repository list --name "${ACR_NAME}" --subscription "${SUBSCRIPTION}" -o table
