# Changelog

## [0.4.0] - 2026-04-16

### Added
- Workshop: Business User IDE on port 9200 -- GUI front-end to /make-it
  - No-terminal experience: describe an idea in chat, watch it build, explore and ship
  - 6 views: Home (project list), Chat (ideation), Build (progress), Explore (dashboard), Iterate (changes), Ship (go live)
  - Bifrost progress bar: MCU-inspired crystalline bridge with prismatic shimmer, phase circles, Claude walker icon, bug encounters
  - WebSocket CLI bridge: real-time streaming between browser and Claude Code CLI
  - Activity feed with auto-categorization (building, testing, auth, database, infra)
  - Build map: component cards that light up as features are completed
  - Iterate view: request board for tracking changes + chat panel for quick tweaks
  - Ship wizard: readiness checklist, deployment mode selection (Docker, ZIP, GitHub), Go Live flow
  - Project discovery API: auto-detects /make-it projects and their build state
- Workshop integrated into Docker container infrastructure
  - Entrypoint launches Workshop server as background service
  - Health monitor tracks Workshop with auto-restart remediation on crash
  - Welcome dashboard shows Workshop as primary card with health status
  - Getting Started steps updated to guide users to Workshop first
- CLI bridge uses bidirectional stream-json (`-p --input-format stream-json --output-format stream-json`)
  - Structured JSON events replace fragile TUI/ANSI text parsing
  - Tool-use events mapped to user-friendly activity messages (e.g., "Creating app/page.tsx")
  - Bash commands translated to plain language ("Installing dependencies...", "Running tests...")
- `/api/auth-status` endpoint: detects Anthropic API key, Azure Foundry (key + token), settings.json
- Auth gate: banner shown on Workshop home when no AI credentials configured, links to terminal

## [0.3.1] - 2026-04-16

### Fixed
- Personal API key (`ANTHROPIC_API_KEY`) now takes priority over Azure Foundry URL in all provider detection
  - configure-provider.sh: API key checked before Foundry URL
  - self-heal-lib.sh: health monitor checks api.anthropic.com instead of Azure endpoint when API key set
  - shell-init.sh: skips Azure login wizard and VPN recovery when API key set
  - welcome-server.sh: /api/health reports Anthropic API provider when API key set
- Personal devices no longer require VPN when using a direct Anthropic API key

## [0.3.0] - 2026-04-15

### Added
- Self-healing health monitor daemon (scripts/health-monitor.sh) replaces watchdog + token-monitor
  - Root cause classification across 4 layers: infrastructure, network, auth, services
  - 11 failure types detected: DNS, internet, disk, VPN, endpoint, Azure token, API key, service crashes, Docker socket
  - Auto-remediation: silent Azure token refresh, code-server/welcome-server restart, disk cleanup
  - Exponential backoff with jitter (5s to 300s cap) on failure, fixed 30s when healthy
  - Restart rate limiting: max 5 restarts per service per 10-minute window
  - JSONL telemetry logging with auto-rotation at 1000 lines
  - Shared state file (/tmp/.health-state.json) consumed by all other scripts
- `/api/health` endpoint on welcome-server (port 3000) with full system status, auth info, telemetry
- Self-Healing History section in doctor.sh diagnostics output

### Changed
- healthcheck.sh reads shared state file instead of basic curl checks
- shell-init.sh reads health monitor state instead of token-monitor flag file
- entrypoint.sh launches single health-monitor.sh instead of separate watchdog + token-monitor

## [0.2.0] - 2026-04-14

### Added
- 3-stage login wizard (scripts/login-wizard.sh) replaces inline auth flows
  - Stage 1: Preflight Checks — VPN, network, Azure CLI connectivity
  - Stage 2: Azure Sign In — device code parsed and displayed in a box,
    clickable URL, spinner while waiting, auto-selects subscription
  - Stage 3: All Set — validates identity, subscription, token health
- `login` alias for forced re-authentication (clears session, fresh az login)
- VPN retry loop in preflight — if AI endpoint is unreachable, prompts user to connect VPN and retry
- Automatic subscription selection after Azure login (from providers.yml)
- Settings.json regeneration on successful auth (fresh token helper)
- DISABLE_AUTOUPDATER — version is pinned in the Docker image, no npm update checks
- npm CA bundle configuration for corporate SSL inspection (Zscaler compatibility)

### Changed
- shell-init.sh now delegates all authentication to login-wizard.sh (first-run and returning user)
- Returning user status displayed after recovery (no contradictory messages)
- GitHub login removed from required wizard flow (optional, run `gh auth login` when needed)
- Azure CLI cold-start retry for reliable token detection on session init

## [0.1.0] - 2026-04-10

### Added
- Initial release
- Dockerfile with Claude Code CLI, ttyd, code-server, Docker CLI, GitHub CLI
- Interactive setup wizard for first-run AI provider configuration
- Support for Anthropic API key, Azure AI Foundry, and AWS Bedrock
- Auto-update mechanism for /make-it skills on container startup
- Docker Compose with host socket mounting for sibling container execution
- Persistent volumes for Claude Code settings and workspace
- GitHub Actions CI/CD workflow for multi-arch image publishing to ghcr.io
- Health checks for ttyd and code-server
- Non-root user (coder) with Docker socket access
