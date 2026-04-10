# =============================================================================
# Claude Code Docker
# A ready-to-run container with Claude Code CLI + Web UI + /make-it skills
# =============================================================================
FROM node:20-alpine

LABEL org.opencontainers.image.title="Claude Code Docker"
LABEL org.opencontainers.image.description="Claude Code CLI + Web UI + /make-it skills in a single container"
LABEL org.opencontainers.image.source="https://github.com/sealmindset/claude-code-docker"

# ---------------------------------------------------------------------------
# System dependencies
# ---------------------------------------------------------------------------
RUN apk update && apk upgrade && apk add --no-cache \
    git \
    curl \
    wget \
    jq \
    unzip \
    openssh-client \
    ca-certificates \
    bash \
    shadow \
    openssl \
    python3 \
    py3-pip \
    py3-virtualenv \
    build-base \
    ttyd \
    docker-cli \
    docker-cli-compose \
    gcompat \
    libstdc++ \
    tmux

# ---------------------------------------------------------------------------
# Corporate/VPN CA certificates (for SSL inspection proxies)
# If building behind a corporate proxy with SSL inspection, place your
# CA certificates as individual .crt files in the certs/ directory.
# If not behind a proxy, create an empty certs/ directory:
#   mkdir -p certs
# ---------------------------------------------------------------------------
COPY certs/ /usr/local/share/ca-certificates/
RUN update-ca-certificates
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

# ---------------------------------------------------------------------------
# Install code-server (VS Code in browser) via standalone release
# Replace bundled glibc Node.js with system Alpine Node.js
# ---------------------------------------------------------------------------
RUN CODE_SERVER_VERSION="4.100.3" \
    && ARCH=$(uname -m) \
    && if [ "$ARCH" = "x86_64" ]; then CS_ARCH="amd64"; elif [ "$ARCH" = "aarch64" ]; then CS_ARCH="arm64"; fi \
    && curl -fsSL "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-${CS_ARCH}.tar.gz" -o /tmp/code-server.tar.gz \
    && tar -xzf /tmp/code-server.tar.gz -C /usr/local/lib/ \
    && rm "/usr/local/lib/code-server-${CODE_SERVER_VERSION}-linux-${CS_ARCH}/lib/node" \
    && ln -s "$(which node)" "/usr/local/lib/code-server-${CODE_SERVER_VERSION}-linux-${CS_ARCH}/lib/node" \
    && ln -s "/usr/local/lib/code-server-${CODE_SERVER_VERSION}-linux-${CS_ARCH}/bin/code-server" /usr/local/bin/code-server \
    && rm /tmp/code-server.tar.gz

# ---------------------------------------------------------------------------
# Install Claude Code CLI
# ---------------------------------------------------------------------------
RUN npm install -g @anthropic-ai/claude-code

# ---------------------------------------------------------------------------
# Install GitHub CLI
# ---------------------------------------------------------------------------
RUN apk add --no-cache github-cli

# ---------------------------------------------------------------------------
# Install Azure CLI (for Azure AD token-based auth)
# ---------------------------------------------------------------------------
RUN apk add --no-cache py3-pip \
    && pip3 install --break-system-packages azure-cli

# ---------------------------------------------------------------------------
# Create non-root user
# ---------------------------------------------------------------------------
RUN deluser node 2>/dev/null; delgroup node 2>/dev/null; \
    addgroup -g 1000 coder 2>/dev/null || true \
    && adduser -u 1000 -G coder -s /bin/bash -D coder 2>/dev/null || true \
    && mkdir -p /home/coder/.claude /home/coder/Documents/GitHub \
    && chown -R coder:coder /home/coder

# ---------------------------------------------------------------------------
# Copy scripts
# ---------------------------------------------------------------------------
COPY scripts/ /opt/claude-code-docker/scripts/
COPY welcome/ /opt/claude-code-docker/welcome/
RUN chmod +x /opt/claude-code-docker/scripts/*.sh

# ---------------------------------------------------------------------------
# Switch to non-root user
# ---------------------------------------------------------------------------
USER coder
WORKDIR /home/coder/Documents/GitHub

# ---------------------------------------------------------------------------
# Install /make-it skills for the coder user
# ---------------------------------------------------------------------------
RUN curl -fsSL https://raw.githubusercontent.com/sealmindset/make-it/main/install.sh | bash

# ---------------------------------------------------------------------------
# Ports: ttyd (7681), code-server (8080)
# ---------------------------------------------------------------------------
EXPOSE 3000 7681 8080

# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://127.0.0.1:7681/health 2>/dev/null || curl -f http://127.0.0.1:7681/ 2>/dev/null || exit 1

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
ENTRYPOINT ["/opt/claude-code-docker/scripts/entrypoint.sh"]
