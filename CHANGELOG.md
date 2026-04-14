# Changelog

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
