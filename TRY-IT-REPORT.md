# Claude Code Docker -- Try-It Report
> Tested: 2026-04-20
> Status: All Passing

## Summary

Your development environment was tested automatically. Here's what happened:

| What Was Tested | Result |
|----------------|--------|
| Container starts and is healthy | PASS |
| Welcome Dashboard loads | PASS |
| Workshop (Business User IDE) loads | PASS |
| Web Terminal loads | PASS |
| VS Code in browser loads | PASS |

## Services Tested

| Service | Port | Status | Notes |
|---------|------|--------|-------|
| Welcome Dashboard | 3000 | PASS | Landing page with service cards and system status |
| Workshop | 9200 | PASS | "New Project" flow ready, shows "Connected" status |
| Web Terminal (ttyd) | 7681 | PASS | Terminal ready with Azure AI Foundry configured |
| VS Code (code-server) | 8080 | PASS | File explorer, Claude Code task auto-launched |

## Screenshots

Screenshots of each interface are saved in `.try-it/screenshots/`:
- `welcome-dashboard.png` -- Landing page with service cards
- `welcome-dashboard-full.png` -- Full page including system status and getting started guide
- `workshop-home.png` -- Workshop IDE home screen
- `web-terminal.png` -- Web terminal with ready prompt
- `code-server.png` -- VS Code in browser with file explorer

## How to Access Your Environment

- **Welcome page:** http://localhost:3000 -- Start here to see all your options
- **Workshop:** http://localhost:9200 -- Build apps by describing your idea (no coding needed)
- **Web Terminal:** http://localhost:7681 -- Type `claude` to start, then `/make-it` to build an app
- **VS Code:** http://localhost:8080 -- Full IDE with file explorer, extensions, and terminal

## Issues Found
None -- all services are running and accessible.

## What to Do Next
- Open http://localhost:3000 in your browser to see the welcome page
- Click **Workshop** to build an app without touching a terminal
- Or open the **Web Terminal** to use Claude Code directly
- To make changes, type **/resume-it**
- To shut down, type **/wrap-it**
