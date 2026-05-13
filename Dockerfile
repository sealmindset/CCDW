# =============================================================================
# Claude Code Docker
# A ready-to-run container with Claude Code CLI + Web UI + /make-it skills
# =============================================================================
# ACR imported images: set REGISTRY_MIRROR to pull base images from Azure ACR
# instead of directly from Docker Hub (bypasses Zscaler/SSL inspection).
# Example: docker build --build-arg REGISTRY_MIRROR=dockyardgwprod.azurecr.io/ .
ARG REGISTRY_MIRROR=
FROM ${REGISTRY_MIRROR}node:20-alpine

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
    go \
    libqrencode-tools \
    libstdc++ \
    tmux \
    su-exec \
    sudo \
    rsync \
    tini

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

# Rebuild node-pty for Alpine/musl (the pre-built binary targets glibc)
RUN cd /usr/local/lib/code-server-*/lib/vscode/node_modules/node-pty \
    && npm rebuild

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
    && pip3 install --break-system-packages azure-cli pyyaml

# ---------------------------------------------------------------------------
# Install AWS CLI v2 (for Bedrock SSO auth)
# ---------------------------------------------------------------------------
RUN apk add --no-cache aws-cli

# ---------------------------------------------------------------------------
# Install kubectl + Helm (for /argo-it Kubernetes deployments)
# ---------------------------------------------------------------------------
RUN ARCH=$(uname -m) \
    && if [ "$ARCH" = "x86_64" ]; then K8S_ARCH="amd64"; elif [ "$ARCH" = "aarch64" ]; then K8S_ARCH="arm64"; fi \
    && curl -fsSL "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/${K8S_ARCH}/kubectl" -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl \
    && curl -fsSL https://get.helm.sh/helm-v3.17.3-linux-${K8S_ARCH}.tar.gz | tar xz -C /tmp \
    && mv /tmp/linux-${K8S_ARCH}/helm /usr/local/bin/helm \
    && rm -rf /tmp/linux-${K8S_ARCH}

# ---------------------------------------------------------------------------
# Create non-root user
# ---------------------------------------------------------------------------
RUN deluser node 2>/dev/null; delgroup node 2>/dev/null; \
    addgroup -g 1000 coder 2>/dev/null || true \
    && adduser -u 1000 -G coder -s /bin/bash -D coder 2>/dev/null || true \
    && echo 'coder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/coder \
    && chmod 0440 /etc/sudoers.d/coder \
    && mkdir -p /home/coder/.claude /home/coder/Documents/GitHub /home/coder/Downloads /home/coder/Desktop \
    && chown -R coder:coder /home/coder

# ---------------------------------------------------------------------------
# UTF-8 locale (needed for Unicode box-drawing and block elements)
# ---------------------------------------------------------------------------
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Go toolchain paths (VS Code Go extension needs gopls on PATH)
ENV GOPATH=/home/coder/go
ENV PATH=$GOPATH/bin:$PATH

# ---------------------------------------------------------------------------
# Copy scripts
# ---------------------------------------------------------------------------
COPY scripts/ /opt/claude-code-docker/scripts/
COPY welcome/ /opt/claude-code-docker/welcome/
COPY workshop/ /opt/claude-code-docker/workshop/
RUN cd /opt/claude-code-docker/workshop && npm install --omit=dev ws
COPY config/ /opt/claude-code-docker/config/
# Fix CRLF line endings from Windows git checkouts, then set executable
RUN sed -i 's/\r$//' /opt/claude-code-docker/scripts/*.sh \
    /opt/claude-code-docker/config/*.yml 2>/dev/null; \
    chmod +x /opt/claude-code-docker/scripts/*.sh

# ---------------------------------------------------------------------------
# Fake browser opener for headless container
# gh/az try to launch xdg-open, which doesn't exist in Docker.
# This wrapper prints the URL so the user knows to open it manually,
# then exits cleanly so CLI tools don't error out.
# ---------------------------------------------------------------------------
RUN mv /opt/claude-code-docker/scripts/xdg-open /usr/local/bin/xdg-open

# ---------------------------------------------------------------------------
# Switch to coder user for extensions, Go tools, and skill install
# ---------------------------------------------------------------------------
USER coder
WORKDIR /home/coder/Documents/GitHub

# VS Code extensions (code-server uses Open VSX registry)
RUN code-server --install-extension ms-python.python \
    && code-server --install-extension golang.go \
    && code-server --install-extension dbaeumer.vscode-eslint \
    && code-server --install-extension esbenp.prettier-vscode \
    && code-server --install-extension Continue.continue

# Go language server (gopls) for the Go extension
RUN go install golang.org/x/tools/gopls@latest

# /make-it skills
RUN curl -fsSL https://raw.githubusercontent.com/sealmindset/make-it/main/install.sh | bash

# Caveman plugin (ultra-compressed communication mode)
RUN claude plugin marketplace add JuliusBrussee/caveman \
    && claude plugin install caveman@caveman

# ---------------------------------------------------------------------------
# Claude Code user-level instructions (shown on every conversation start)
# ---------------------------------------------------------------------------
RUN printf '%s\n' \
    "Run /make-it to turn your idea into a working application." \
    > /home/coder/.claude/CLAUDE.md

# ---------------------------------------------------------------------------
# Stage .claude contents for volume initialization at runtime
# (Named volumes mask image contents after first creation)
# ---------------------------------------------------------------------------
RUN cp -a /home/coder/.claude /home/coder/.claude-defaults

# ---------------------------------------------------------------------------
# Switch back to root for entrypoint (it drops to coder after setup)
# ---------------------------------------------------------------------------
USER root

# ---------------------------------------------------------------------------
# Ports: Workshop (9200), Welcome (3000), ttyd (7681), code-server (8080)
# ---------------------------------------------------------------------------
EXPOSE 3000 7681 7682 8080 9200

# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://127.0.0.1:7681/health 2>/dev/null || curl -f http://127.0.0.1:7681/ 2>/dev/null || exit 1

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
ENTRYPOINT ["/sbin/tini", "--", "/opt/claude-code-docker/scripts/entrypoint.sh"]
