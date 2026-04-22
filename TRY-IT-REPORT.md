# Claude Code Docker -- Try-It Report
> Tested: 2026-04-22
> Status: All Passing (20/20)

## Summary

Full infrastructure smoke test of the CCDW container with v0.5.2 changes (VS Code extensions, login UX, walkthrough, provider-aware auth, welcome-server.js extraction).

| What Was Tested | Result |
|----------------|--------|
| Docker image builds | PASS |
| Container starts and passes health check | PASS |
| Welcome dashboard (port 3000) | PASS |
| Workshop (port 9200) | PASS |
| Web terminal (port 7681) | PASS |
| VS Code code-server (port 8080) | PASS |
| API: /api/status | PASS |
| API: /api/health | PASS |
| API: /api/usage | PASS |
| API: /auth/pending | PASS |
| API: /auth/check | PASS |
| API: /auth/start (POST) | PASS |
| API: /auth/clear (POST) | PASS |
| Auth relay cycle (start -> pending -> clear) | PASS |
| CORS preflight (OPTIONS /auth/*) | PASS |
| VS Code extensions installed (5/5) | PASS |
| Go toolchain (gopls) | PASS |
| QR code tool (qrencode) | PASS |
| welcome-server.js syntax validation | PASS |
| welcome-server.sh -> .js extraction | PASS |

## Services

| Service | Port | HTTP Status | Notes |
|---------|------|-------------|-------|
| Welcome Dashboard | 3000 | 200 | Cards, status, AI Provider section, Getting Started |
| Workshop | 9200 | 200 | Home view with walkthrough overlay, project cards |
| Web Terminal (ttyd) | 7681 | 200 | Shell init complete, Azure auth verified |
| VS Code (code-server) | 8080 | 302 | Redirect to login (expected), file explorer + projects |

## v0.5.2 Features Verified

| Feature | Status | Evidence |
|---------|--------|----------|
| Python extension | PASS | `ms-python.python` in extension list |
| Go extension | PASS | `golang.go` in extension list |
| ESLint extension | PASS | `dbaeumer.vscode-eslint` in extension list |
| Prettier extension | PASS | `esbenp.prettier-vscode` in extension list |
| Continue.dev extension | PASS | `continue.continue` in extension list |
| gopls language server | PASS | `/home/coder/go/bin/gopls` v0.21.1 |
| qrencode terminal QR | PASS | `/usr/bin/qrencode` available |
| Walkthrough overlay | PASS | "Welcome to Workshop" step 1/5, progress dots, Skip/Next |
| "Take the tour" link | PASS | `btnTakeTour` element present in Workshop HTML |
| Auth notification banner | PASS | `authNotify` element in Welcome dashboard |
| Provider-aware sign-in | PASS | `checkSigninNeeded` JS function served |
| /auth/login endpoint | PASS | Returns `{authenticated: true, provider: "azure"}` |
| /auth/pending endpoint | PASS | Returns `{pending: false}` (no active login) |
| /auth/check endpoint | PASS | Returns `{authenticated: true, provider: "azure"}` |

## API Responses

**GET /api/status**
```json
{"docker":"ok","ai_provider":"Azure AI Foundry","ai_status":"ok"}
```

**GET /api/health**
- Status: healthy
- Auth: Azure AI Foundry via azure_cli_token
- Docker socket: available
- Disk: 359 GB free

**GET /auth/check**
```json
{"authenticated":true,"provider":"azure"}
```

## Screenshots

Saved in `.try-it/screenshots/`:
- `welcome-dashboard.png` -- Welcome page with all cards, status section, Getting Started
- `workshop-home.png` -- Workshop with walkthrough overlay (step 1/5)
- `terminal.png` -- Web terminal with shell init complete, Azure verified
- `vscode.png` -- VS Code with file explorer, Welcome tab, zero errors

## How to Access

| Service | URL |
|---------|-----|
| Welcome Dashboard | http://localhost:3000 |
| Workshop | http://localhost:9200 |
| Web Terminal | http://localhost:7681 |
| VS Code | http://localhost:8080 |

## Bugs Found & Fixed This Session

| Bug | Root Cause | Fix |
|-----|-----------|-----|
| AI Provider badge stuck on "checking..." | Unicode smart quotes (U+2018/2019) broke JS parser | Replaced all curly quotes with ASCII in index.html |
| "sso-bedrock-model-access not found" in terminal | Stale Bedrock settings.json in persistent Docker volume | configure-provider.sh now detects provider mismatch and regenerates |

## What to Do Next
- Test walkthrough steps 2-5 (interactive spotlight + positioned tooltips)
- Test Azure sign-in flow from Welcome dashboard (click Sign In button)
- Test QR code rendering in login wizard (run `login` in terminal)
- Test Continue.dev auto-configuration (open Continue panel in VS Code)
- Rebuild Docker image to bake in all fixes (when Open VSX is stable)
