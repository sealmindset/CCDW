# Claude Code Docker

Run Claude Code anywhere -- Windows, macOS, Linux. No WSL, no Node.js, no Linux setup. Just Docker.

A ready-to-run container that packages Claude Code CLI, a web-based terminal, VS Code in the browser, and the full /make-it skill suite into a single image. If you can run Docker Desktop or Rancher Desktop, you can run Claude Code.

## Quick Start

### One-Line Install (Recommended)

No clone needed. Just run one command:

**macOS / Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/SleepNumberInc/CCDW/main/bootstrap.sh | bash
```

**Windows (PowerShell):**
You'll need to request to get your local admin credentials to proceed.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
winget install 
winget install --id GitHub.cli --source winget
wsl --install
gh auth login
iex (gh api repos/SleepNumberInc/CCDW/contents/bootstrap.ps1 -H "Accept: application/vnd.github.raw")
```

The installer handles everything automatically: Rancher Desktop, Docker, AI provider configuration, and a desktop shortcut. Re-run to update.

### Native Install — macOS, No Docker (Azure AI Foundry)

Choose this if you just want the Claude Code CLI running directly on your Mac — no Docker, no container — wired up to corporate Azure AI Foundry auth.

Download `claude_corp_bootstrap.sh` (attached to the "Vibe Code for macOS" Confluence page) and run it from Terminal:

```bash
bash ~/Downloads/claude_corp_bootstrap.sh
```

or, with the repo published, `curl -fsSL https://raw.githubusercontent.com/SleepNumberInc/CCDW/main/claude_corp_bootstrap.sh | bash`.

**What it does:**

- Checks the Mac and the network first: macOS 13+, not root, Apple Silicon vs Intel (re-runs itself natively under Rosetta), disk space, Zscaler certificate trust, and whether the AI gateway is reachable. If the VPN is off, it waits for you to connect it.
- Asks for the Mac password at most once, and only if something needs installing. If the account's temporary admin access is off, it waits, or stops with the reason before changing anything. The cached password is cleared at the end.
- Installs only what is missing: Apple Command Line Tools (headless, same method Homebrew uses), Homebrew, `jq`, and the Azure CLI. Nothing Docker, Rancher, or container-related is installed.
- Installs Claude Code natively (`~/.local/bin/claude`), retrying a dropped download, and adds `~/.local/bin` to `PATH` in `~/.zprofile` and `~/.zshrc`.
- Writes an Azure token helper (`~/.claude/get-claude-token.sh`) that hands Claude Code a short-lived Entra bearer token. The token is never printed or written to disk. The helper never starts a sign-in itself; when the sign-in has expired, its error tells the person to run `claude-login`. A hand-written helper is left alone (`FORCE_TOKEN_HELPER=1` replaces it).
- Writes `~/.local/bin/claude-login`, which signs in to the Sleep Number tenant with the Cognitive Services scope. It tries the browser first and falls back to a device code (copied to the clipboard, page opened). It works for accounts with no Azure subscription. If `az` hits TLS inspection, it gives `az` the macOS trust store. The installer uses this same command for the first sign-in.
- Deep-merges the Foundry settings into `~/.claude/settings.json`, with a timestamped backup and an atomic write. Your existing hooks, plugins, and keys are kept. It removes keys that defeat Foundry mode (`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, other provider flags, the dead `apiKeyHelperTtlMs`) and lists each one it removes.
- Pre-sets `~/.claude.json` so Claude Code opens straight to the prompt. On a new account its first-run folder-trust question defaults to "No, exit", which quits on Return.
- Installs the `/make-it` skills, pinned to the tested commit (`MAKEIT_REF` overrides it) and never downgrading an existing install. Building and running apps with `/make-it` needs Docker, which this installer deliberately does not install.
- Flags any `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` exported from your shell profiles. It reports the file and line only and does not edit the file.
- Proves access end to end: sends a 1-token request to each model (opus, sonnet, haiku) through the gateway, then gets a one-word reply from `claude -p`.
- Logs every run to `~/Library/Logs/claude_corp_bootstrap/`. Exit codes: 0 = proven working, 2 = stopped with the reason, 3 = installed but the final checks did not pass.
- Fully idempotent — safe to re-run any time.

The `settings.json` keys it writes:

```json
{
  "apiKeyHelper": "~/.claude/get-claude-token.sh",
  "model": "opus",
  "env": {
    "CLAUDE_CODE_USE_FOUNDRY": "1",
    "CLAUDE_CODE_SKIP_FOUNDRY_AUTH": "1",
    "CLAUDE_CODE_API_KEY_HELPER_TTL_MS": "1800000",
    "ANTHROPIC_FOUNDRY_BASE_URL": "https://snapi-scus.azure.sleepnumber.com/anthropic",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-5-5",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5"
  }
}
```

`CLAUDE_CODE_SKIP_FOUNDRY_AUTH=1` is required. Without it, Claude Code ignores `apiKeyHelper` and falls back to the Azure credential chain.

**Requirements:** macOS 13+, corporate VPN connected, and an Entra account with access to the Foundry gateway. No Docker required.

**After install:** open a new Terminal window and run `claude`. `/status` should show Microsoft Foundry.

> If Claude Code later reports `apiKeyHelper failed … Not signed in to Azure`, run `claude-login` in a Terminal window, then type `continue` in Claude Code. A `403` means your account isn't authorized on the gateway; signing in again won't fix it.

Advanced users can override the defaults via env vars (`FOUNDRY_BASE_URL`, `FOUNDRY_DEFAULT_MODEL`, `FOUNDRY_SONNET`, `FOUNDRY_HAIKU`, `FOUNDRY_OPUS`, `FOUNDRY_TOKEN_RESOURCE`, `FOUNDRY_TENANT_ID`, `FOUNDRY_TOKEN_TTL_MS`, `FORCE_TOKEN_HELPER`, `SKIP_GATEWAY_TEST`, `MAKEIT_REF`) before running the command.

For testing off the corporate network (for example in a VM), `SKIP_CORP_CHECKS=1` skips the VPN check, Microsoft sign-in, token and gateway checks; everything else runs normally. The summary then shows a "Test mode … SKIPPED" line, so a test ALL SET is not proof that Claude Code can reach the gateway.

### One-Click Install (If You Have the Repo)

- **macOS:** Double-click `setup-claude-mac.command`
- **Windows:** Double-click `setup-claude.bat`

### Pull from Registry

```bash
docker pull ghcr.io/SleepNumberInc/CCDW:latest

docker run -d \
  --name claude-code \
  -p 3000:3000 \
  -p 7681:7681 \
  -p 8080:8080 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v ~/Documents:/home/coder/Documents \
  ghcr.io/SleepNumberInc/CCDW:latest
```

Then open **http://localhost:3000** in your browser.

### Docker Compose (Power Users)

```bash
git clone https://github.com/SleepNumberInc/CCDW.git
cd claude-code-docker
bash scripts/first-run.sh
docker compose up -d
```

## Features

- **Welcome Dashboard** -- Landing page with status lights, links, and getting-started guide (port 3000)
- **Web Terminal** -- Claude Code in your browser via ttyd (port 7681)
- **VS Code in Browser** -- Full IDE experience via code-server (port 8080)
- **Workshop** -- Build apps without touching a terminal (port 9200)
- **Claude Chat** -- Web-based chat with Claude (port 3002)
- **AI Provider Flexibility** -- Anthropic API key, Azure AI Foundry, or AWS Bedrock
- **One-Line Install** -- Single command for macOS, Linux, and Windows
- **One-Click Install** -- Double-click installer for Windows (.bat) and macOS (.command)
- **Auto-Update** -- Installer pulls the latest image every time you launch
- **Auto-Upgrade** -- Outdated Rancher Desktop is upgraded automatically during setup
- **Desktop Shortcut** -- Installer creates a "Claude Code" icon on your desktop
- **Setup Log** -- All output saved to `~/Desktop/claude-setup.log` for troubleshooting
- **Doctor Mode** -- `./install.command --doctor` for diagnostics without reinstalling
- **/make-it Savings** -- Dashboard shows token/cost savings from prompt caching
- **First-Run Walkthrough** -- Step-by-step guide shown on first terminal session
- **Setup Wizard** -- Interactive AI provider configuration (no .env editing required)
- **Friendly Errors** -- Plain-English error messages with VPN detection
- **Azure Token Health** -- Token expiry monitoring with proactive warnings
- **Azure Host Pre-Auth** -- Inherits host Azure CLI session (skips device-code login)
- **Port Conflict Detection** -- Pre-checks ports before container start, shows what's blocking
- **Container Crash Detection** -- Catches immediate crashes and shows container logs
- **Session Persistence** -- Close your browser and reopen -- same terminal session via tmux
- **Service Watchdog** -- Auto-restarts crashed services without container restart
- **Backup & Restore** -- One-command backup/restore of all settings
- **Build Apps Inside** -- Docker socket mounting lets you build and run apps
- **Auto-Updating Skills** -- /make-it skills update automatically on each container start
- **Persistent Data** -- Your workspace, settings, and git config survive container restarts

## Access

| Service | URL | Description |
|---------|-----|-------------|
| Dashboard | http://localhost:3000 | Landing page with status and links |
| Web Terminal | http://localhost:7681 | Claude Code in a browser-based terminal |
| VS Code | http://localhost:8080 | Full IDE with file explorer, extensions, terminal |
| Workshop | http://localhost:9200 | Build apps by describing what you want |
| Claude Chat | http://localhost:3002 | Chat with Claude in a web UI |
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
2. Click **Workshop** to build an app without touching a terminal
3. Or click **Web Terminal** and type `/make-it` to build from the CLI
4. Describe your app idea in plain English

Apps you build are saved in the projects folder, which is shared with your host machine.

## Troubleshooting

### Doctor Mode

Run diagnostics without reinstalling:
```bash
./install.command --doctor
```

Checks Docker, image, container health, ports, network, disk space, and .env configuration.

### Setup Log

All installer output is saved to `~/Desktop/claude-setup.log`. Share this file if you need help.

### Fix Rancher Desktop (macOS)

If Docker stops working after a Rancher Desktop update or crash:
```bash
# Double-click fix-rancher-mac.command
# or run:
./fix-rancher-mac.command
```

This factory-resets the Lima VM and Rancher Desktop configuration. Your projects and Claude Code settings are safe.

### Fix Rancher Desktop (Windows)

```cmd
fix-rancher.bat
```

Repairs corrupted WSL distros used by Rancher Desktop.

### Built-in Troubleshooter

From inside the container:
```bash
doctor
```

Checks all services, AI provider, network, Docker, disk space, and skills.

### Common Issues

**"Cannot connect to the Docker daemon"**
Make sure Docker Desktop or Rancher Desktop is running.

**Port conflicts**
The installer detects port conflicts before starting. If ports 3000, 7681, or 8080 are in use, change them in `.env`:
```env
WELCOME_PORT=3001
TTYD_PORT=7682
CODE_SERVER_PORT=8081
```

**Credentials not working**
Run the login wizard again from inside the container:
```bash
login
```

**Container won't start**
Check logs:
```bash
docker compose logs -f
```

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
  bootstrap.sh              # One-line macOS/Linux installer (curl | bash)
  claude_corp_bootstrap.sh  # Native macOS installer -- Claude Code + Azure AI Foundry (no Docker)
  bootstrap.ps1             # One-line Windows installer (irm | iex)
  setup-claude-mac.command  # macOS one-click setup (Rancher Desktop + Docker + install)
  setup-claude.bat          # Windows one-click setup (Rancher Desktop + Docker + install)
  install.command            # macOS/Linux installer (--ai=foundry|bedrock|anthropic|--doctor)
  install.bat               # Windows installer (--ai=foundry|bedrock|anthropic)
  fix-rancher-mac.command   # macOS Rancher Desktop repair (factory-reset Lima VM)
  fix-rancher.bat           # Windows Rancher Desktop repair (reset WSL distros)
  Dockerfile                # Container image (Alpine + Claude Code + Azure CLI + AWS CLI)
  docker-compose.yml        # Orchestration with volumes and ports
  .env.example              # Environment variable template
  config/
    foundry.json            # Azure AI Foundry config (org-specific)
    bedrock.json            # AWS Bedrock config (org-specific)
    anthropic.json          # Anthropic API config
    *.template.json         # Blank templates with field descriptions
  welcome/
    index.html              # Dashboard landing page with savings banner
  scripts/
    entrypoint.sh           # Container startup (all services)
    welcome-server.js       # Dashboard web server + /api/usage + /api/status
    push-image.sh           # Build and push to GHCR + ACR
    configure-provider.sh   # Generates settings.json from env vars
    login-wizard.sh         # Azure device-code / AWS SSO login flow
    shell-init.sh           # Shell session init + auth check + walkthrough
    health-monitor.sh       # Self-healing watchdog
    doctor.sh               # Connection troubleshooter
    backup.sh / restore.sh  # Settings backup and restore
```

## Persistence

| Data | Storage | Survives Restart? |
|------|---------|-------------------|
| Your projects | `~/Documents` (host mount) | Yes |
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
| 3002 | Claude Chat | Yes, via `CHAT_PORT` in .env |
| 7681 | ttyd (web terminal) | Yes, via `TTYD_PORT` in .env |
| 8080 | code-server (VS Code) | Yes, via `CODE_SERVER_PORT` in .env |
| 9200 | Workshop | Yes, via `WORKSHOP_PORT` in .env |

## Docker-in-Docker

This container mounts the host's Docker socket, so apps built with /make-it run as **sibling containers** on your host -- not nested containers. This means:

- Apps get full Docker performance (no virtualization overhead)
- You can see app containers in Docker Desktop / Rancher Desktop
- Port mappings from apps are accessible on your host machine

On Windows, the Docker socket path is handled automatically by Docker Desktop / Rancher Desktop.

## License

MIT
