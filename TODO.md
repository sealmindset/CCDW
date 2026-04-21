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

## High Priority
- [x] Fix install.bat for Rancher Desktop under local admin (SSMITH) account
- [ ] Test install.bat on Windows 10/11 with Rancher Desktop (under own account)
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
- [ ] Automate end-to-end app deployment via /ship-it or /argo-it
  - User should do absolute bare minimum to get their app from local to dev to production
  - /ship-it: commit, push, create PR, trigger CI/CD -- all in one command
  - /argo-it: ArgoCD-based deployment pipeline for Kubernetes environments
  - Auto-detect deployment target (Docker Compose, K8s, cloud run, etc.)
  - Auto-generate Dockerfile, Helm chart, or manifests if missing
  - Auto-configure GitHub Actions or ArgoCD pipeline
  - Handle secrets/env vars promotion across environments (dev -> staging -> prod)
  - Provide plain-English deployment status ("Your app is live at https://...")

## Medium Priority
- [ ] Add VS Code extensions for common languages (Python, TypeScript, Go)
- [ ] Add Copilot-style Claude extension to code-server
- [ ] Support Docker socket on macOS (Colima, Docker Desktop, Rancher Desktop)

## Low Priority
- [ ] Add optional TLS/HTTPS for ttyd and code-server
- [ ] Add container resource limit recommendations in README
- [ ] Create a quick-start video walkthrough
- [ ] Login wizard: auto-open Microsoft device login in new browser tab via welcome-server redirect endpoint
- [ ] Login wizard: add QR code option for device code (for users on separate devices)
