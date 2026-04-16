# Claude Code Docker -- Try-It Report
> Tested: 2026-04-16
> Status: All Passing

## Summary

Your app was tested automatically. Here's what happened:

| What Was Tested | Result |
|----------------|--------|
| Container starts up | PASS |
| Welcome dashboard loads | PASS |
| Web terminal (ttyd) loads | PASS |
| VS Code (code-server) loads | PASS |
| Health API responds | PASS |
| Self-healing monitor running | PASS |
| Docker socket accessible | PASS |
| AI endpoint reachable | PASS |

## Services

| Service | Port | Status | Notes |
|---------|------|--------|-------|
| Welcome Dashboard | 3000 | Healthy | 15KB page, status lights active |
| Web Terminal (ttyd) | 7681 | Healthy | HTML terminal interface loaded |
| VS Code (code-server) | 8080 | Healthy | Redirects to workspace (expected) |
| Health Monitor | -- | Running | All systems operational |

## Health API (/api/health)

- **Status:** healthy
- **Message:** All systems operational
- **Auth provider:** Azure AI Foundry (azure_cli_token)
- **AI endpoint reachable:** Yes
- **Docker socket:** Available
- **Disk space:** Plenty available
- **Recent failures (1h):** 0

## How to Access Your App

- **Welcome Dashboard:** http://localhost:3000
  Overview page with status lights, links, and getting-started guide

- **Web Terminal:** http://localhost:7681
  Claude Code CLI in your browser -- type `/make-it` to build an app

- **VS Code in Browser:** http://localhost:8080
  Full IDE experience with your GitHub projects folder mounted

- **Health API:** http://localhost:3000/api/health
  JSON status endpoint for monitoring

## What to Do Next
- Open http://localhost:3000 to see the welcome dashboard
- Open http://localhost:7681 to use Claude Code in your browser
- Open http://localhost:8080 to browse code in VS Code
- If something doesn't look right, tell me and I'll fix it
- When you're done exploring, just tell me "stop the app"
- To make changes, type **/resume-it**
