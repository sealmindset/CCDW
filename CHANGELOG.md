# Changelog

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
