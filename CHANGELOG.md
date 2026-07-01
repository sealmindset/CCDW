# Changelog

## [Unreleased]

### Added
- macOS desktop launcher: install.command now builds a real "Claude Code.app" on the Desktop
  (via `scripts/build-mac-app.sh`) instead of a plain `.webloc` shortcut
  - The app is a thin bundle whose stub exec's `scripts/launch-mac.sh`, so it always runs the
    latest launcher after a `git pull` — no rebuild needed for launcher changes
  - Uses the Claude icon (`assets/claude-icon.icns`, or generated from `claude-icon.png`)
  - Removes any pre-existing `~/Desktop/Claude Code.webloc` so users don't end up with both
  - Falls back to the legacy `.webloc` shortcut (with a warning) if `build-mac-app.sh` is
    missing or fails, so installation never breaks

## [0.6.3] - 2026-05-26

### Added
- Claude Account provider (`--ai=claude`): OAuth-based auth for Max plan, free tier, or Teams
  - No API key required -- sign in via browser on first launch
  - install.command and install.bat both support `--ai=claude` (also `--ai=oauth`, `--ai=max`)
  - config/claude.json + claude.template.json for provider configuration
  - login-wizard.sh: `claude auth login` / `claude auth logout` integration
  - shell-init.sh: OAuth status detection via `claude auth status`
  - configure-provider.sh: minimal settings.json (permissions only, no token helper)
  - claude-wrapper.sh: no false "no provider" error when CLAUDE_CODE_PROVIDER=claude
  - welcome-server.js: status, health, auth/login, auth/check all detect Claude Account
  - doctor.sh: Claude auth check + api.anthropic.com reachability
  - self-heal-lib.sh: api.anthropic.com endpoint check for claude provider

### Fixed
- Workshop banner: "AI Provider not configured" when Bedrock or Claude Account is active
- Workshop Chat: "Bedrock direct API not supported yet" error -- now fully supports Bedrock
  - AWS SigV4 request signing (pure Node.js crypto, no SDK dependency)
  - Binary event stream parser for Bedrock streaming responses
  - Model list with cross-region inference profile IDs
- Workshop Chat: added Claude Account detection (redirects to terminal for OAuth)
- Workshop readiness checks: added Bedrock network check and provider-aware fix steps
- Bedrock: post-wizard re-check in shell-init.sh was Azure-only, now provider-aware
- Bedrock: first-run status display missing AWS SSO auth line
- Bedrock: fallback profile name `sso-bedrock` corrected to `sso-bedrock-model-access` (8 files)
- welcome-server.js: Bedrock auth method now shows `sso` instead of `none` when using SSO
- SigV4 signature mismatch for Bedrock model IDs containing colons (e.g., v1:0)
- AWS CLI `--format json` flag not supported on Alpine (removed, default output is JSON)

## [0.6.2] - 2026-05-20

### Added
- fix-rancher.bat: standalone repair script for corrupted Rancher Desktop WSL distributions
  - Detects the "wsl.exe exited with code 4294967295" corruption issue
  - Closes Rancher Desktop, unregisters corrupted internal distros, restarts fresh
  - Preserves Ubuntu and other personal WSL distributions
  - Preserves Docker containers, images, and project files
  - Waits for Docker engine to become ready after repair
- scripts/fix-rancher-wsl.ps1: PowerShell engine for WSL distro repair
  - Health check mode (-DiagOnly) for diagnostics without repair
  - Preserves Rancher Desktop settings (dockerd engine) across repair
  - Graceful shutdown via rdctl before force-kill fallback
- Auto-repair in install.bat: detects corrupted WSL distros during preflight and engine wait
  - If Rancher distros exist but don't respond, repairs automatically before continuing
  - Engine failure path now attempts WSL repair before showing manual fix instructions
- Auto-repair in setup-claude.bat: WSL distro health check after WSL2 verification
- help-claude.bat: diagnostic report now includes Rancher WSL health check section

## [0.6.1] - 2026-05-19

### Added
- Host network access: apps inside the container can reach host services via `host.docker.internal`
  - Databases, APIs, and other services running on your computer are now reachable
  - Works on Docker Desktop (Mac/Windows) and Rancher Desktop
- Kubernetes config mount: `~/.kube` mounted automatically for kubectl and /argo-it
- Git identity passthrough: container inherits your name and email from host git config
  - Priority: GitHub API > host ~/.gitconfig > manual configuration
  - Host config mounted read-only; container can override without affecting host
- macOS setup: system requirement checks (macOS version, disk space) before install begins
- macOS setup: progress bar with elapsed time and phase descriptions for Rancher Desktop first-run
  - Shows "Provisioning Docker engine" → "Starting services" → "Almost ready" with visual fill bar
- ACR image pull: installer tries internal registry (dockyardgwprod) before GHCR
  - 4-layer fallback: ACR → GHCR → cached image → local build
  - Bypasses Zscaler/SSL inspection on corporate networks

### Changed
- docker-compose.yml: added `extra_hosts` for host.docker.internal resolution
- Install scripts: all docker run commands now include host-access arguments
- .env.example: documented host access features

## [0.6.0] - 2026-05-13

### Added
- Workshop Ship view overhauled with real deployment workflows
  - Real readiness checks: GitHub auth, git remote, app structure, test infrastructure
  - Three deployment modes: Ship for Review (/ship-it), Save Progress (/ship-it save), Deploy to Kubernetes (/argo-it)
  - Live progress feed during deployment with real-time CLI activity
  - Failure recovery with retry option
  - Capability detection: Kubernetes mode disabled when kubectl not available
- /argo-it wired into Workshop server and CLI bridge
- kubectl and Helm added to Docker image for Kubernetes deployments
- `POST /api/ship/readiness` endpoint for real-time project readiness assessment

### Changed
- Ship mode cards replaced: Docker/ZIP/GitHub → Ship for Review/Save Progress/Deploy to Kubernetes
- Ship readiness checks no longer simulated -- backed by real gh auth, git, and filesystem checks
- Ship view CSS expanded with proper styling for checks, mode cards, progress ring, activity feed

### Polish (CEO/executive UX audit)
- Welcome dashboard: removed port badges, renamed "Docker" to "System", "Tokens" to "AI Usage"
- Welcome dashboard: title changed to "Claude Code", subtitle to "Your personal AI development studio"
- Welcome dashboard: hid "+ New Terminal" quick action, softened VS Code/Terminal card descriptions
- Welcome dashboard: Getting Started step 4 rewritten for non-technical users
- Shell init: PS1 prompt simplified, "Claude Code Docker" renamed to "Claude Code" everywhere
- Login wizard: preflight labels rewritten in plain language (no CLI/SDK jargon)
- Login wizard: step headers renamed "Checking Your Setup" and "Sign In"
- Login wizard: Bedrock Okta group message replaced with generic "AI access permission"
- macOS install: added friendly preamble, progress dots during download, single URL at end
- macOS install: Docker wait with auto-retry, silent SSL cert export, quieter error messages
- Windows install: added friendly preamble, renamed "Preflight Checks" to "Checking Your Setup"
- Windows install: silenced SSL/cert noise, simplified ending to single URL
- Both installers: "Claude Code Docker" renamed to "Claude Code" in all user-facing text

## [0.5.2] - 2026-04-22

### Added
- SSL proxy / content filter detection across all layers (health monitor, dashboard, terminal)
  - Health monitor detects SSL interception (curl exit codes 35/51/60) as distinct `ssl_proxy` failure type
  - Welcome dashboard: amber notice banner with step-by-step instructions to pause the security tool
  - Terminal: boxed warning on shell startup when HTTPS connections are being intercepted
  - `/api/health` endpoint includes `ssl_proxy` boolean for programmatic detection
- code-server now inherits `NODE_EXTRA_CA_CERTS` and `SSL_CERT_FILE` from container environment
  - Fixes Continue.dev and other extensions failing to download behind corporate SSL inspection
- VS Code extensions pre-installed in Docker image: Python, Go, ESLint, Prettier, Continue.dev
- Go toolchain (`go` + `gopls` language server) added to container
- Continue.dev AI assistant auto-configured from active provider (Anthropic, Foundry, Bedrock)
- code-server settings: format-on-save, per-language formatters, Go/Python paths
- Login wizard: QR code displayed in terminal for mobile device authentication
- Login wizard: auto-opens sign-in page in browser via welcome-server relay
- Welcome dashboard: auth notification banner with device code + auto-open when login wizard triggers
- Welcome server: `/auth/start`, `/auth/pending`, `/auth/clear` endpoints for browser-terminal relay
- Interactive guided walkthrough: spotlight highlights target elements, positioned tooltips with arrows, progress dots
- "Take the tour" link on home view for returning users to re-trigger walkthrough
- Dashboard-driven sign-in: provider-aware auth flow triggered from welcome page
  - Anthropic: no sign-in needed (API key configured at install)
  - Azure Foundry: spawns `az login --use-device-code`, shows code, auto-opens Microsoft sign-in
  - AWS Bedrock: defers to terminal login wizard (SSO flow needs real-account testing)
- Welcome server: `/auth/login` POST spawns provider-specific auth, `/auth/check` GET verifies completion
- CORS preflight handler for cross-origin auth requests from Workshop

### Fixed
- Welcome dashboard: AI Provider badge stuck on "checking..." due to Unicode smart quotes in JavaScript
  - Curly quotes (U+2018/U+2019/U+201C/U+201D) and em dash (U+2014) broke the JS parser
  - All replaced with ASCII equivalents in `welcome/index.html`
- Provider mismatch: stale Bedrock `settings.json` persisted in Docker volume when switching to Foundry
  - `configure-provider.sh` now detects provider mismatch and regenerates settings
  - Foundry env vars + Bedrock settings.json triggers automatic cleanup and regeneration
  - Also handles: Bedrock env + Foundry/token settings, API key mode + any stale settings

### Changed
- Welcome server extracted from embedded shell string to standalone `welcome-server.js`
  - Eliminates shell escaping fragility (370 lines of JS no longer inside bash double-quotes)
  - File is now lintable, formattable, and testable with standard JS tooling
  - `welcome-server.sh` reduced to a 4-line launcher that sets env vars and `exec node`

## [0.5.1] - 2026-04-22

### Removed
- Workshop setup wizard files (setup.html, setup.js, setup.css) -- provider config now happens host-side via installer
- Dead code: renderSetupChecks(), renderSetupSteps(), iframe postMessage listener from app.js

### Changed
- Workshop setup overlay replaced with plain-language "re-run the installer" instructions
- Auth banner "Open Setup" link replaced with "How to fix" that shows the info overlay

## [0.5.0] - 2026-04-22

### Added
- Multi-provider install support with `--ai=foundry|bedrock|anthropic` argument
  - Per-provider JSON config files drive both install scripts and container-side setup
  - Config files declare endpoints, models, preflight checks, and settings templates
  - Template JSON files (*.template.json) with `_help` descriptions for organizations to fork
- AWS CLI v2 added to Docker image for Bedrock SSO authentication
- Provider-aware login wizard: Azure device-code, AWS SSO, or API key (auto-detected)
- Data-driven preflight checks: VPN, CLI tools, network, group membership per provider
- Interactive provider prompts in install.bat (PowerShell) for missing values (endpoint, API key, SSO details)
- install.bat: PowerShell-based JSON parsing replaces Node.js dependency
- install.bat: Writes `~/.aws/config` SSO profile for Bedrock
- install.command: Provider-specific prompts and `~/.aws/config` generation
- Bedrock `settings.json` generation with `awsAuthRefresh`, permissions deny/ask, all model vars
- `AUTH_OK` provider-agnostic auth variable in shell-init.sh (replaces Azure-only `AZ_OK`)
- README: installer-driven setup as recommended path alongside manual .env editing
- README: updated project structure showing config/ JSON files and current scripts
- Chapter 11: CCDW Setup Guide in MakeIt-TheDocs (architecture, all providers, installation, troubleshooting)

### Changed
- install.bat: refactored from single-provider to multi-provider with interactive menu
- install.command: refactored with `read_config()`, `write_env_from_config()`, `write_aws_config()` helpers
- configure-provider.sh: Bedrock case generates full settings.json matching AWS spec
- login-wizard.sh: full rewrite -- detects active provider, three complete login flows
- shell-init.sh: Bedrock auth check via `aws sts get-caller-identity`
- docker-compose.yml: `~/.aws` volume mount added for Bedrock credentials

## [0.4.5] - 2026-04-21

### Fixed
- install.bat: Docker discovery now works when Rancher Desktop was installed under a different Windows account (e.g. SSMITH local admin)
  - Searches PATH, current user's Rancher, Docker Desktop Program Files, then other user profiles
  - Checks Windows named pipe (\\.\pipe\docker_engine) for engine readiness
  - Offers two-option menu: install Rancher under own account (permanent fix) or use existing install (quick fix)
- install.bat: Detects and warns when running as Administrator (wrong %USERPROFILE%)
- install.bat: Reads PROJECTS_PATH from .env so volume mounts go to the right folder
- install.bat: Workshop port 9200 now mapped (was missing from docker run)
- install.bat: Progress counter during Docker engine wait ("Still waiting... 3 of 12")
- install.bat: Falls back to cached image gracefully when offline (instead of forcing a local build)
- install.bat: Rewrote all complex if-blocks to goto-based flow to fix batch parentheses escaping bug
  - Parentheses in echo text (e.g. "recommended", "moby") silently terminated script execution
  - Replaced nested if/else with labeled sections and goto jumps
  - Inline docker run commands instead of building in variables (avoids nested quote bugs)
  - Removed all parentheses from user-facing text (use dashes instead)
- install.bat: Fixed OneDrive interference with default projects folder
  - Default changed from %USERPROFILE%\Documents\GitHub to %USERPROFILE%\GitHub
  - OneDrive Known Folder Move redirects Documents into cloud sync, breaking paths
- install.bat: Expanded Docker CLI discovery to find Rancher Desktop on locked-down machines
  - Added: docker.exe in script directory (admin can pre-stage the binary)
  - Added: Rancher Desktop MSI install path in Program Files
  - Added: Rancher Desktop in current user's LocalAppData\Programs
  - Added: Windows registry search for Rancher Desktop install location via PowerShell
  - Added: Named pipe detection -- if Docker daemon is running but docker.exe is inaccessible,
    gives specific instructions for the admin to copy the binary
  - "Not found" error now lists every location that was checked

### Added
- .env.example: DOCKER_PATH override for cases where docker.exe is in a non-standard location
- .env.example: WORKSHOP_PORT setting documented

## [0.4.4] - 2026-04-17

### Added
- tini as PID 1 init process to reap zombie children (fixes 509+ zombie accumulation)
- VS Code code-server terminal now works: recompiled node-pty for Alpine musl libc
- VS Code Claude Code terminal profile: auto-launches Claude Code in right panel on workspace open
- New config files: code-server-settings.json, code-server-tasks.json

### Changed
- Bifrost walker: replaced smiley face with Claude pixel mascot icon (terracotta body, dark features)
- Bifrost phases: circles replaced with meaningful icons (lightbulb, pencil, wrench, rocket)
- Bifrost layout: phase icons moved above the bridge path (two-layer layout)
- "See your app" button: always visible, faded when app isn't running (was hidden entirely)

## [0.4.3] - 2026-04-17

### Added
- Welcome-back flow for existing projects: conversational DM-style greeting with three actions
  - "Add something new" → runs /resume-it with Bifrost progress bar (same experience as new builds)
  - "Take a look at your creation" → runs /try-it, starts Docker, embeds app in iframe
  - "We're ready to go live" → opens Ship wizard
  - Free-text input also works: type anything and it routes through /resume-it
- Bifrost progress bar now shows during /resume-it (iterating phase mapped to building)

### Fixed
- Quick reply suggestions: no longer offers generic YES/NO for non-binary questions
  - Extracts contextual options from numbered lists, lettered choices, and bold bullets
  - Detects "A or B?" alternatives and offers both as buttons
  - Only shows Yes/No for truly confirmatory questions (e.g., "Should I proceed?")
- Try-It redirect: now opens the actual app URL instead of redirecting to Workshop
  - Detects app port from CLI output and docker-compose.yml port mappings
  - Embeds the running app in an iframe on the Explore view
  - Stores detected URL across views so Try It button works immediately

### Changed
- Explore view simplified: technical dashboard replaced with clean header bar + full-size app iframe
  - Removed stat cards, test users list, and readiness checklist
  - Summary bar shows project name, health badge, page/role counts
  - App iframe is the primary content, not a toggle overlay
- Project cards on Home simplified: single click opens welcome-back chat (removed separate Open/Resume buttons)

## [0.4.2] - 2026-04-17

### Fixed
- Workshop auth passthrough: credentials configured after server start are now detected
  - Auth status, preflight checks, and CLI spawning all read fresh from settings.json
  - Users who configure AI credentials in the terminal no longer need to restart Workshop

### Changed
- Bifrost animations polished across the board:
  - Walker starts behind the first phase node so ideation phase has visible travel
  - Phase circles pop and scale when activating/completing (entrance animation)
  - Completed circle dot fades in with a delayed scale animation
  - Walker bob has a subtle tilt for more character
  - Bug wobble is faster and more frantic (0.3s with scale variation)
  - Bug defeat adds an expanding ring flash effect
  - Completion triggers a light sweep across the bridge and walker celebration jump
  - Phase transitions staggered: glow fills → walker moves → circle activates
  - Bug positioning uses percentage-based system instead of brittle pixel calculation

## [0.4.1] - 2026-04-16

### Fixed
- Bifrost progress bar now stays visible during the entire build phase
  - Informational messages no longer switch from build view to chat view
  - Only real questions (with reply options or ending with '?') interrupt the build view
- Auto-continuation: builds chain multiple turns via `--resume` so code actually gets written
- Full skill inlining: Workshop sends the complete /make-it skill content on turn 1 (TUI parity)
- Large prompt handling: prompts exceeding 128KB piped via stdin instead of command-line args

### Changed
- Docker image rebuilt with all Workshop fixes baked in

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
