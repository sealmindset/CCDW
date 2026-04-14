# TODO

## High Priority
- [ ] Test build on Windows 10/11 with Docker Desktop
- [ ] Test build on Windows 10/11 with Rancher Desktop
- [ ] Verify Docker socket mounting works on Windows hosts

## Medium Priority
- [ ] Add VS Code extensions for common languages (Python, TypeScript, Go)
- [ ] Add Copilot-style Claude extension to code-server
- [ ] Support Docker socket on macOS (Colima, Docker Desktop, Rancher Desktop)

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

## Low Priority
- [ ] Add optional TLS/HTTPS for ttyd and code-server
- [ ] Add container resource limit recommendations in README
- [ ] Create a quick-start video walkthrough
- [ ] Login wizard: auto-open Microsoft device login in new browser tab via welcome-server redirect endpoint
- [ ] Login wizard: add QR code option for device code (for users on separate devices)
