# Claude Code Docker

Run Claude Code on Windows -- no WSL, no Node.js, no Linux setup. Just Docker.

A ready-to-run container that packages Claude Code CLI, a web-based terminal, VS Code in the browser, and the full /make-it skill suite into a single image. If you can run Docker Desktop or Rancher Desktop, you can run Claude Code.

## Features

- **Welcome Dashboard** -- Landing page with status lights, links, and getting-started guide (port 3000)
- **Web Terminal** -- Claude Code in your browser via ttyd (port 7681)
- **VS Code in Browser** -- Full IDE experience via code-server (port 8080)
- **Direct CLI** -- `docker exec` for power users
- **AI Provider Flexibility** -- Anthropic API key, Azure AI Foundry, or AWS Bedrock
- **One-Click Install** -- Double-click installer for Windows (.bat) and macOS (.command)
- **Desktop Shortcut** -- Installer creates a "Claude Code" icon on your desktop
- **Auto-Update** -- Installer pulls the latest image every time you launch
- **First-Run Walkthrough** -- Step-by-step guide shown on first terminal session
- **Setup Wizard** -- Interactive AI provider configuration (no .env editing required)
- **Friendly Errors** -- Plain-English error messages with VPN detection
- **Azure Token Health** -- Token expiry monitoring with proactive warnings
- **Session Persistence** -- Close your browser and reopen -- same terminal session via tmux
- **Service Watchdog** -- Auto-restarts crashed services without container restart
- **Backup & Restore** -- One-command backup/restore of all settings
- **Build Apps Inside** -- Docker socket mounting lets you build and run apps
- **Auto-Updating Skills** -- /make-it skills update automatically on each container start
- **Persistent Data** -- Your workspace, settings, and git config survive container restarts

## Prerequisites

- **Windows 10/11** or **macOS** with one of:
  - [Docker Desktop](https://www.docker.com/products/docker-desktop/) (free for personal use)
  - [Rancher Desktop](https://rancherdesktop.io/) (free and open source)
- **An AI provider** (one of):
  - Anthropic API key from [console.anthropic.com](https://console.anthropic.com)
  - Azure AI Foundry endpoint and key
  - AWS credentials with Bedrock access

## Quick Start

### Option 1: One-Click Install (Recommended)

The fastest way to get started:

- **Windows:** Double-click `install.bat` or run `install.bat --ai=foundry`
- **macOS:** Double-click `install.command` or run `./install.command --ai=foundry`

Replace `foundry` with `bedrock` or `anthropic` for other providers. Double-clicking presents an interactive menu.

The installer will:
1. Run preflight checks (VPN, CLI tools, access)
2. Configure your AI provider (writes `.env` and credential files)
3. Download (or update) the latest Docker image
4. Start the container
5. Create a "Claude Code" shortcut on your desktop
6. Open the dashboard in your browser

### Option 2: Pull from Registry

```bash
docker pull ghcr.io/sealmindset/claude-code-docker:latest

mkdir -p ~/Documents/GitHub

docker run -d \
  --name claude-code \
  -p 3000:3000 \
  -p 7681:7681 \
  -p 8080:8080 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v ~/Documents/GitHub:/home/coder/Documents/GitHub \
  ghcr.io/sealmindset/claude-code-docker:latest
```

Then open **http://localhost:3000** in your browser.

### Option 3: Docker Compose (Power Users)

1. Clone this repo:
   ```bash
   git clone https://github.com/sealmindset/claude-code-docker.git
   cd claude-code-docker
   ```

2. Run the first-time setup:
   ```bash
   bash scripts/first-run.sh
   ```

3. Edit `.env` with your AI provider credentials (or skip and use the setup wizard).

4. Start the container:
   ```bash
   docker compose up -d
   ```

5. Open in your browser:
   - Dashboard: **http://localhost:3000**
   - Web Terminal: **http://localhost:7681**
   - VS Code: **http://localhost:8080**

### Option 4: Build from Source

```bash
git clone https://github.com/sealmindset/claude-code-docker.git
cd claude-code-docker

# Create certs directory (required for build)
# If behind a corporate VPN with SSL inspection, export your CA certs here
mkdir -p certs

docker build -t claude-code-docker .
docker compose up -d
```

## Access

| Service | URL | Description |
|---------|-----|-------------|
| Dashboard | http://localhost:3000 | Landing page with status and links |
| Web Terminal | http://localhost:7681 | Claude Code in a browser-based terminal |
| VS Code | http://localhost:8080 | Full IDE with file explorer, extensions, terminal |
| Direct CLI | `docker exec -it claude-code bash` | Shell access for power users |

## AI Provider Setup

### Option A: Installer-Driven Setup (Recommended)

The installer configures your AI provider automatically from pre-built JSON configs:

```bash
# macOS
./install.command --ai=foundry      # Azure AI Foundry
./install.command --ai=bedrock      # AWS Bedrock
./install.command --ai=anthropic    # Anthropic API key

# Windows
install.bat --ai=foundry
install.bat --ai=bedrock
install.bat --ai=anthropic
```

If you omit `--ai=`, an interactive menu appears. The installer runs preflight checks (VPN, CLI tools, access), prompts for any missing values, and writes `.env` for you.

Provider configs live in `config/<provider>.json`. Organizations fork the repo and fill in their own endpoints, model names, and SSO URLs. See `config/*.template.json` for blank starting points.

### Option B: Manual .env Setup

If you prefer to edit `.env` directly:

**Anthropic API Key (Personal):**
```env
ANTHROPIC_API_KEY=sk-ant-your-key-here
```

**Azure AI Foundry:**
```env
CLAUDE_CODE_USE_FOUNDRY=1
ANTHROPIC_FOUNDRY_BASE_URL=https://your-resource.services.ai.azure.com/anthropic
ANTHROPIC_DEFAULT_SONNET_MODEL=your-sonnet-deployment-name
ANTHROPIC_DEFAULT_HAIKU_MODEL=your-haiku-deployment-name
ANTHROPIC_DEFAULT_OPUS_MODEL=your-opus-deployment-name
```

**AWS Bedrock:**
```env
CLAUDE_CODE_USE_BEDROCK=1
AWS_REGION=us-east-1
AWS_PROFILE=sso-bedrock-model-access
ANTHROPIC_MODEL=sonnet
ANTHROPIC_DEFAULT_SONNET_MODEL=us.anthropic.claude-sonnet-4-6
ANTHROPIC_DEFAULT_HAIKU_MODEL=us.anthropic.claude-haiku-4-5-20251001-v1:0
ANTHROPIC_DEFAULT_OPUS_MODEL=us.anthropic.claude-opus-4-6-v1
DISABLE_PROMPT_CACHING=0
```

For Bedrock, you also need `~/.aws/config` with an SSO profile. The installer creates this automatically when using `--ai=bedrock`.

### Authentication Inside the Container

After the container starts, your first terminal session runs a login wizard:

- **Azure AI Foundry (SSO):** `az login --use-device-code` -- visit a URL and enter a code
- **AWS Bedrock (SSO):** `aws sso login --profile <name>` -- authorize in your browser
- **Anthropic API Key:** No login needed -- the key is read from the environment

To re-authenticate later, type `login` in the terminal.

## Building Apps with /make-it

Once inside the container, you have the full Claude Code experience:

1. Open the dashboard at http://localhost:3000
2. Click **Web Terminal** to open the terminal
3. Type `claude` to start Claude Code
4. Type `/make-it` to build a new app from scratch
5. Describe your app idea in plain English

Apps you build are saved in the projects folder, which is shared with your host machine.

## Built-in Commands

| Command | Description |
|---------|-------------|
| `claude` | Start Claude Code |
| `cc` | Start Claude Code with friendly error messages |
| `login` | Re-run the login wizard (refresh Azure/GitHub sessions) |
| `doctor` | Run the connection troubleshooter |
| `backup` | Save all settings to a backup file |
| `restore <file>` | Restore settings from a backup |

## Project Structure

```
claude-code-docker/
  install.bat              # Windows installer (--ai=foundry|bedrock|anthropic)
  install.command           # macOS installer (--ai=foundry|bedrock|anthropic)
  Dockerfile               # Container image (Alpine + Claude Code + Azure CLI + AWS CLI)
  docker-compose.yml       # Orchestration with volumes and ports
  .env.example             # Environment variable template
  config/
    foundry.json           # Azure AI Foundry config (org-specific)
    foundry.template.json  # Blank Foundry template with field descriptions
    bedrock.json           # AWS Bedrock config (org-specific)
    bedrock.template.json  # Blank Bedrock template with field descriptions
    anthropic.json         # Anthropic API config
    anthropic.template.json# Blank Anthropic template
  welcome/
    index.html             # Dashboard landing page
  scripts/
    entrypoint.sh          # Container startup (all services)
    configure-provider.sh  # Generates settings.json from env vars
    login-wizard.sh        # Azure device-code / AWS SSO login flow
    shell-init.sh          # Shell session init + auth check + walkthrough
    welcome-server.sh      # Dashboard web server
    health-monitor.sh      # Self-healing watchdog
    claude-wrapper.sh      # Friendly error wrapper with VPN detection
    doctor.sh              # Connection troubleshooter
    backup.sh              # Settings backup
    restore.sh             # Settings restore
    auto-update.sh         # Skill auto-update on startup
    healthcheck.sh         # Container health verification
  .github/workflows/
    publish.yml            # CI/CD: build and push to ghcr.io on tag
```

## Persistence

| Data | Storage | Survives Restart? |
|------|---------|-------------------|
| Your projects | `~/Documents/GitHub` (host mount) | Yes |
| Claude Code settings | `claude-code-data` volume | Yes |
| Git config | `claude-code-git-config` volume | Yes |
| Terminal session | tmux (in-memory) | Yes (while container runs) |

To start completely fresh, remove the named volumes:
```bash
docker compose down -v
```

## Ports

| Port | Service | Configurable? |
|------|---------|---------------|
| 3000 | Dashboard (welcome page) | Yes, via `WELCOME_PORT` in .env |
| 7681 | ttyd (web terminal) | Yes, via `TTYD_PORT` in .env |
| 8080 | code-server (VS Code) | Yes, via `CODE_SERVER_PORT` in .env |

## Docker-in-Docker

This container mounts the host's Docker socket, so apps built with /make-it run as **sibling containers** on your host -- not nested containers. This means:

- Apps get full Docker performance (no virtualization overhead)
- You can see app containers in Docker Desktop / Rancher Desktop
- Port mappings from apps are accessible on your host machine

On Windows, the Docker socket path is handled automatically by Docker Desktop / Rancher Desktop.

## Troubleshooting

### Something not working?

Run the built-in troubleshooter from inside the container:
```bash
doctor
```

This checks all services, AI provider, network, Docker, disk space, and skills, then tells you exactly what's wrong and how to fix it.

### "Cannot connect to the Docker daemon"

Make sure Docker Desktop or Rancher Desktop is running. The container needs the Docker socket mounted to build and run apps.

### Port conflicts

If ports 3000, 7681, or 8080 are already in use, change them in `.env`:
```env
WELCOME_PORT=3001
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

### Backup and restore

Before making changes or moving to a new machine:
```bash
# Inside the container
backup                    # Creates claude-code-backup-YYYYMMDD.tar.gz
restore <backup-file>     # Restores from backup
```

## License

MIT
