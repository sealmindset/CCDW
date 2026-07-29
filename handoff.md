# Handoff -- CCDW (Claude Code Docker Workshop)
_Written 2026-07-23 11:46 by /clear-it. Read this file in full before continuing work._

## 1. Goal
Get CCDW running again. `docker compose up -d` was hanging indefinitely. Diagnose and
restore the `claude-code` container to healthy. (Ops/environment fix — no code change intended.)
Acceptance: `docker compose ps` shows `claude-code` Up + healthy, ports mapped.

## 2. Current State
- **RESOLVED.** Container `claude-code` is **Up + healthy**, ports mapped
  (3000, 3002, 7681-7682, 8080, 9200). Docker engine v29.5.3.
- Root cause: Docker Desktop's Linux VM was paused on laptop sleep (VM console log froze
  2026-07-20 16:33, "multiplexer is offline") and never cleanly resumed → engine (dockerd)
  wedged → `docker compose up` blocked forever on a dead daemon.
- Fixed by hard-killing all `com.docker*` procs + relaunching Docker Desktop clean. Engine
  came up in ~10s; `compose up -d` then succeeded.
- Branch `main`, HEAD `6ae970d`. No code changed this session.
- Pre-existing uncommitted changes untouched (prior PAT/GitHub-auth work): welcome-server.js,
  entrypoint.sh, gh-*, package*.json, .make-it-state.md, CHANGELOG.md, plus untracked
  handoff.md / .handoff-history.md / scripts/gh-token-setup.command.
- **Warning: host disk 98% full, only ~9.3Gi free** (`/System/Volumes/Data`). Docker
  builds/pulls will start failing soon. Prune recommended.

## 3. Active Files
- None edited this session. Investigation only (docker/compose ops).
- `docker-compose.yml` -- referenced during diagnosis (has the `/Volumes` bind mount from
  commit `6ae970d`); mount was NOT the cause, source `/Volumes` exists.

## 4. Changes Made
- No code or config changes. Only ran diagnostics + restarted Docker Desktop.

## 5. Failed Approaches -- DO NOT RETRY
- **First restart via `osascript quit` + `pkill -f com.docker.backend`** -- assumed quitting
  the app + killing the named backend would reboot the engine. FAILED: a stale
  `com.docker.backend` (pid 21317) survived, so `open -a Docker` saw Docker "already running"
  and never rebooted the VM; engine still down after 90s. Fix that worked: `pkill -9 -f
  "Docker Desktop"` AND `pkill -9 -f com.docker` (kill ALL docker procs; leave only the
  `com.docker.vmnetd` privileged helper), THEN `open -a Docker`.
- **Diagnosing via `docker version` / `docker info` with no timeout** -- hung indefinitely
  (that's the whole symptom — dead daemon). Always wrap docker CLI probes in `timeout 5-8`
  during an outage so the shell returns.
- **(carried forward) docker-compose bind mount with `bind.propagation: rslave`/`rshared` on
  macOS Docker Desktop** -- daemon rejects it (`path ... is not a shared or slave mount`),
  container won't start. Use plain bind mount. Drives plugged in after start need
  `docker compose restart`.
- **(carried forward) GitHub headless auto-auth blocked by org SAML SSO + MFA** -- SleepNumberInc
  enforces Microsoft SAML+MFA on the GitHub OAuth grant; cannot clear headlessly. Use PAT /
  the `sn-ravance` gh account for org ops. See memory `github-auth-saml-sso-wall`.
- **(carried forward) Docker image build behind Zscaler fails with curl exit 60** -- SSL cert
  verify failure. Export host Zscaler Root CA to `certs/zscaler.crt`
  (`security find-certificate -a -c Zscaler -p /Library/Keychains/System.keychain > certs/zscaler.crt`)
  before `docker compose build`.

## 6. Next Steps
None blocking — CCDW is up and healthy. Optional:
1. **Reclaim disk (recommended, host at 98%):** `docker system prune -a` to remove unused
   images/build cache. Omit `--volumes` unless sure — keeps `claude-code-data`,
   `claude-code-git-config`, `claude-code-gh-config`.
2. If the VM wedges again after sleep: don't wait on `compose up`; run
   `timeout 5 docker info` first — if it hangs, `pkill -9 -f com.docker` then `open -a Docker`.
3. Prior-session PAT/GitHub-auth work still uncommitted (see .handoff-history.md) — decide
   whether to finish/commit separately. This session did not touch it.
