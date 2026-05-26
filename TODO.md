# TODO

## High Priority (Workshop)
- [x] End-to-end Bifrost test: 20 Playwright tests covering all phases, walker, bug, reset, celebration
- [x] Browser test: 17 Playwright tests across all 6 views, overlays, panels (37/37 passing)
- [x] Configure git remote and push all commits (pushed to sealmindset + sleepnumberinc)
- [x] Bifrost polish: phase icons (lightbulb, pencil, wrench, rocket), icons above bridge, Claude mascot walker
- [x] VS Code terminal fix: node-pty recompiled for Alpine musl, tini as PID 1
- [x] VS Code Claude Code terminal profile: auto-launches in right panel on workspace open
- [x] "See your app" button always visible (faded when disabled)
- [x] Workshop auth: getFreshEnv() reads settings.json before every CLI spawn and auth check
- [x] Fix Bifrost not showing during builds (informational messages incorrectly switching views)
- [x] Auto-continuation: builds now chain turns via --resume so code gets written
- [x] Full skill inlining: resolveSkill() sends complete /make-it content on turn 1

## High Priority (Setup Module)
- [x] Build providers.js backend module (status detection, config writing, connection testing, auth flows)
- [x] Add provider API routes to workshop/server.js
- [x] Build setup.html + setup.js + setup.css frontend wizard
- [x] Integrate setup into Workshop navigation (auth banner, gear icon, setup overlay)
- [x] Integrate setup into Welcome Dashboard (setup card, modal with iframe)
- [x] Redesign Setup Module as host-side pre-start (writes .env before docker compose up)
- [x] Create setup/server.js (zero-dependency, self-terminating)
- [x] Create setup/providers.js (.env reader/writer + connection testing)
- [x] Create setup/public/ standalone wizard (index.html, setup.js, setup.css)
- [x] Integrate into install.bat (web wizard + CLI fallback)
- [x] Integrate into install.command (macOS)
- [x] Add AWS config volume mount to docker-compose.yml
- [x] Strip Workshop to read-only provider status
- [x] Update Welcome Dashboard to read-only provider display
- [x] Per-provider config JSON files (foundry.json, bedrock.json, anthropic.json + templates)
- [x] Refactor install scripts: --ai=foundry|bedrock|anthropic argument
- [x] Add AWS CLI v2 to Docker image
- [x] Provider-aware login-wizard.sh (Azure device-code + AWS SSO)
- [x] Bedrock auth check in shell-init.sh
- [ ] Test install.bat --ai=foundry on Windows
- [ ] Test install.bat --ai=bedrock on Windows
- [x] Test install.command --ai=bedrock on macOS
- [x] Test Bedrock aws sso login inside container with real AWS account
- [ ] Test install.command --ai=claude on macOS
- [ ] Test install.bat --ai=claude on Windows
- [x] Clean up old workshop setup files (setup.html no longer primary)

## High Priority
- [x] Fix install.bat for Rancher Desktop under local admin (SSMITH) account
- [x] Test install.bat on Windows 10/11 with Rancher Desktop (under own account)
- [ ] Test install.bat on Windows 10/11 with Rancher Desktop (under SSMITH admin)
- [ ] Test install.bat on Windows 10/11 with Docker Desktop
- [ ] Verify Docker socket mounting works on Windows hosts

## High Priority (RBAC & Identity)
- [ ] Determine RBAC model: Object_ID-based vs Application-based RBAC
  - Object_ID-based RBAC requires external setup steps outside the container:
    - Register app in Entra ID (Azure AD)
    - Obtain Object_ID and configure role assignments
    - Store secrets in Secret Server
    - Document the manual Entra ID + Secret Server steps for business users
  - Application-based RBAC may be self-contained within the app
  - /make-it and /ship-it should detect which model the app uses and guide accordingly

## High Priority (Deployment)
- [x] Wire /ship-it and /argo-it into Workshop Ship view with real readiness checks
  - /ship-it: commit, push, create PR, trigger CI/CD -- all in one command
  - /argo-it: ArgoCD-based deployment pipeline for Kubernetes environments
  - Real readiness checks (gh auth, git remote, app structure, tests)
  - Mode selection: Ship for Review, Save Progress, Deploy to Kubernetes
  - kubectl + Helm added to Docker image
- [ ] End-to-end test: build app with /make-it, then /ship-it creates PR on GitHub
- [ ] End-to-end test: build app with /make-it, then /argo-it generates K8s manifests + PR
- [x] Add kubeconfig mounting from host for /argo-it cluster access

## Medium Priority
- [x] Add VS Code extensions for common languages (Python, TypeScript, Go)
- [x] Add Copilot-style Claude extension to code-server (Continue.dev with auto-provider detection)
- [ ] Support Docker socket on macOS (Colima, Docker Desktop, Rancher Desktop)

## Low Priority
- [ ] Add optional TLS/HTTPS for ttyd and code-server
- [ ] Add container resource limit recommendations in README
- [x] Create a quick-start walkthrough (interactive guided tour with spotlight + positioning)
- [x] Login wizard: auto-open Microsoft device login in new browser tab via welcome-server redirect endpoint
- [x] Login wizard: add QR code option for device code (for users on separate devices)
