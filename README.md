# Claude Code Docker

Run Claude Code on Windows -- no WSL, no Node.js, no Linux setup. Just Docker.

A ready-to-run container that packages Claude Code CLI, a web-based terminal, VS Code in the browser, and the full /make-it skill suite into a single image. If you can run Docker Desktop or Rancher Desktop, you can run Claude Code.

## Features

- **Web Terminal** -- Claude Code in your browser via ttyd (port 7681)
- **VS Code in Browser** -- Full IDE experience via code-server (port 8080)
- **Direct CLI** -- `docker exec` for power users
- **AI Provider Flexibility** -- Anthropic API key, Azure AI Foundry, or AWS Bedrock
- **Setup Wizard** -- Interactive first-run configuration (no .env editing required)
- **Build Apps Inside** -- Docker socket mounting lets you build and run apps from within the container
- **Auto-Updating Skills** -- /make-it skills update automatically on each container start
- **Persistent Data** -- Your workspace, settings, and git config survive container restarts

## Prerequisites

- **Windows 10/11** with one of:
  - [Docker Desktop](https://www.docker.com/products/docker-desktop/) (free for personal use)
  - [Rancher Desktop](https://rancherdesktop.io/) (free and open source)
- **An AI provider** (one of):
  - Anthropic API key from [console.anthropic.com](https://console.anthropic.com)
  - Azure AI Foundry endpoint and key
  - AWS credentials with Bedrock access

## Quick Start

### Option 1: Pull from Registry (Recommended)

```bash
# Pull the latest image
docker pull ghcr.io/sealmindset/claude-code-docker:latest

# Create a workspace folder
mkdir workspace

# Run the container
docker run -d \
  --name claude-code \
  -p 7681:7681 \
  -p 8080:8080 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v ./workspace:/home/coder/workspace \
  ghcr.io/sealmindset/claude-code-docker:latest
```

Then open **http://localhost:7681** in your browser. The setup wizard will walk you through connecting to your AI provider.

### Option 2: Docker Compose (Power Users)

1. Clone this repo:
   ```bash
   git clone https://github.com/sealmindset/claude-code-docker.git
   cd claude-code-docker
   ```

2. Copy and edit the environment file:
   ```bash
   cp .env.example .env
   # Edit .env with your AI provider credentials
   ```

3. Start the container:
   ```bash
   docker compose up -d
   ```

4. Open in your browser:
   - Web Terminal: **http://localhost:7681**
   - VS Code: **http://localhost:8080**

### Option 3: Build from Source

```bash
git clone https://github.com/sealmindset/claude-code-docker.git
cd claude-code-docker

# Create certs directory (required for build)
# If behind a corporate VPN with SSL inspection, export your CA certs here
mkdir -p certs
# Example: security find-certificate -a -p /Library/Keychains/System.keychain > bundle.crt
#          Then split into individual .crt files in certs/

docker build -t claude-code-docker .
docker compose up -d
```

## Access

| Service | URL | Description |
|---------|-----|-------------|
| Web Terminal | http://localhost:7681 | Claude Code in a browser-based terminal |
| VS Code | http://localhost:8080 | Full IDE with file explorer, extensions, terminal |
| Direct CLI | `docker exec -it claude-code bash` | Shell access for power users |

## AI Provider Setup

### Anthropic API Key (Personal)

Set in `.env`:
```env
ANTHROPIC_API_KEY=sk-ant-your-key-here
```

### Azure AI Foundry

Set in `.env`:
```env
ANTHROPIC_BASE_URL=https://your-resource.services.ai.azure.com
ANTHROPIC_API_KEY=your-azure-api-key
```

### AWS Bedrock

Set in `.env`:
```env
CLAUDE_CODE_USE_BEDROCK=1
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
AWS_REGION=us-east-1
```

## Building Apps with /make-it

Once inside the container, you have the full Claude Code experience:

1. Open the web terminal at http://localhost:7681
2. Type `claude` to start Claude Code
3. Type `/make-it` to build a new app from scratch
4. Answer questions about your app idea in plain English
5. Your app gets built and runs as sibling containers on your host Docker

Apps you build are saved in the `workspace/` folder, which is shared with your host machine.

## Project Structure

```
claude-code-docker/
  Dockerfile              # Container image definition
  docker-compose.yml      # Orchestration with volumes and ports
  .env.example            # Environment variable template
  scripts/
    entrypoint.sh         # Container startup (ttyd + code-server)
    shell-init.sh         # Shell session initialization
    setup-wizard.sh       # Interactive AI provider setup
    auto-update.sh        # Skill auto-update on startup
    healthcheck.sh        # Container health verification
  .github/workflows/
    publish.yml           # CI/CD: build and push to ghcr.io on tag
```

## Persistence

| Data | Storage | Survives Restart? |
|------|---------|-------------------|
| Your projects | `./workspace` (host mount) | Yes |
| Claude Code settings | `claude-code-data` volume | Yes |
| VS Code config | `claude-code-coder-config` volume | Yes |
| Git config | `claude-code-git-config` volume | Yes |

To start completely fresh, remove the named volumes:
```bash
docker compose down -v
```

## Ports

| Port | Service | Configurable? |
|------|---------|---------------|
| 7681 | ttyd (web terminal) | Yes, via `TTYD_PORT` in .env |
| 8080 | code-server (VS Code) | Yes, via `CODE_SERVER_PORT` in .env |

## Docker-in-Docker

This container mounts the host's Docker socket, so apps built with /make-it run as **sibling containers** on your host -- not nested containers. This means:

- Apps get full Docker performance (no virtualization overhead)
- You can see app containers in Docker Desktop / Rancher Desktop
- Port mappings from apps are accessible on your host machine

On Windows, the Docker socket path is handled automatically by Docker Desktop / Rancher Desktop.

## Troubleshooting

### "Cannot connect to the Docker daemon"

Make sure Docker Desktop or Rancher Desktop is running. The container needs the Docker socket mounted to build and run apps.

### Port conflicts

If ports 7681 or 8080 are already in use, change them in `.env`:
```env
TTYD_PORT=7682
CODE_SERVER_PORT=8081
```

### Credentials not working

Run the setup wizard again from inside the container:
```bash
/opt/claude-code-docker/scripts/setup-wizard.sh
```

### Container won't start

Check logs:
```bash
docker compose logs -f
```

## License

MIT
