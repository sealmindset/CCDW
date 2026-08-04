# Handoff -- CCDW (Claude Code Docker Workshop)
_Written 2026-07-30 12:39 by /clear-it. Read this file in full before continuing work._

## 1. Goal
Two goals this session, both **DONE**:
1. Ship the Claude Chat overhaul (real Claude Code driving the Chat UI) and publish
   `:latest` to GHCR + ACR.
2. Produce a Confluence-ready documentation set for CCDW aimed at **non-technical business
   users** — install, per-page usage, troubleshooting, glossary. Acceptance: portable
   Markdown that pastes into Confluence Cloud without cleanup; every factual claim verified
   against the repo rather than assumed.

## 2. Current State
- Branch `main`, HEAD `0fb25aa`. **Working tree CLEAN** (before this handoff write).
- `origin` (SleepNumberInc/CCDW, **INTERNAL**) is at `0fb25aa` — up to date.
- `seal` (sealmindset/CCDW, **PUBLIC**) is at `69091e2` — **deliberately 1 commit behind.**
  Rob chose "origin only, hold seal" because the 8 screenshots in `docs/confluence/img/`
  expose internal detail (see Next Steps #1). `seal` is a strict ancestor, so a later
  `git push seal main` fast-forwards cleanly — no divergence to resolve.
- Chat overhaul shipped in `69091e2`; `:latest` published to GHCR and ACR and verified by
  pulling the published image and running `node --check` on `chat/agent.js`,
  `chat/workdir.js`, `chat/server.js` inside it.
- `docs/confluence/` = 13 Markdown pages + 8 PNGs, 2,672 lines, committed in `0fb25aa`.
- Container `claude-code` up + healthy. **Its Azure token is EXPIRED** — Workshop reports
  "AI provider not configured. Foundry endpoint set but Azure token expired or missing."
  Fix: type `login` at `localhost:7681`. Not a code bug.

## 3. Active Files
- `docs/confluence/01-what-is-ccdw.md` -- overview; gained a three-way comparison section
  (Claude app / Claude Code / CCDW) and a "two things switched on" block.
- `docs/confluence/11-make-it-framework.md` -- NEW. The built-in skill suite, per-page
  exposure, all 14 skills, the 5-phase/14-step build sequence.
- `docs/confluence/12-what-ccdw-remembers.md` -- NEW. Persistence: what survives restart
  and update, and why the auth token is the exception.
- `docs/confluence/README.md` -- page tree, paste instructions, image-attachment table,
  note on why the upstream make-it docs are NOT vendored here.
- `docs/confluence/img/dashboard.png`, `img/workshop.png` -- the two screenshots blocking
  the `seal` push. Contain internal names (see Next Steps #1).
- `docs/confluence/0[2-9]-*.md`, `10-glossary.md` -- the other ten pages; 03/05/07/08/09/10
  each gained cross-links this session.

## 4. Changes Made
- Claude Chat overhaul — 12 files, +1317/−269 (committed `69091e2`, pushed origin+seal).
- `:latest` published to GHCR and ACR (outward-facing; Rob authorized explicitly).
- Confluence doc set — 21 files, +2,672 (committed `0fb25aa`, **pushed origin ONLY**).
- No source code changed while writing the docs. Docs-only commit.

## 5. Failed Approaches -- DO NOT RETRY
- **Pushing `docs/confluence/` to both remotes without checking repo visibility** -- assumed
  `seal` was as private as `origin`. FALSE: `gh repo view` says `sealmindset/CCDW` is
  **PUBLIC**, `SleepNumberInc/CCDW` is INTERNAL. The screenshots expose the Foundry
  deployment id `cogdep-aifoundry-dev-eus2-claude-opus-5` (Azure naming convention +
  env + region), GitHub user `sn-ravance`, and nine internal project names
  (`auditgithub`, `sec-diligence`, `DueDiligence`, `siqassess`, `Graph API Proxy`, …).
  Conclusion: **always check `gh repo view --json visibility` before pushing anything
  containing screenshots or config to `seal`.**
- **`scripts/push-image.sh`'s ACR path (`buildx build -t GHCR -t ACR --push`)** -- the
  `docker-container` buildx builder cannot verify ACR's TLS behind Zscaler, so the push
  fails. Its curl preflight **passes anyway** — the preflight lies. Working path: push GHCR
  only, then `docker buildx imagetools create --tag <ACR> <GHCR>` (client-side, works).
  Script still NOT patched.
- **Trusting my own doc claims without grepping** -- wrote three things that were false and
  had to correct them: (a) `install.bat --doctor` — does not exist, `grep -c doctor
  install.bat` → 0, `--doctor` is macOS-only; (b) "about 15 GB of free disk space" —
  invented, `scripts/doctor.sh` warns below 1 GB and recommends 4 GB+; (c) "macOS 13 or
  newer" — that belongs to the README's *native* install path, no version check exists in
  `install.command`. Conclusion: verify every command, flag, and number against the repo
  before it goes in a doc.
- **Waiting on `.cards` visibility for the Dashboard screenshot** -- passes while
  `#bootScreen` (`welcome/index.html:539`) still overlays the page. Wait for `#bootScreen`
  to be **hidden** instead. Also hide `#authNotify` (`welcome/index.html:650`) first — it
  renders a LIVE device code (caught `76FC-280C` in an early capture).
- **A fixed short wait for the Workshop screenshot** -- races the `#btnWalkthroughSkip`
  tour modal (~2 s) and catches an empty `#projectsGrid` (fetched after paint). Wait for the
  skip button, click it, then wait for `#projectsGrid` textContent length > 40.
- **Running Playwright scripts from `/tmp`** -- `ERR_MODULE_NOT_FOUND '@playwright/test'`.
  Must run from the project root so `node_modules` resolves.
- **`docker exec claude-code bash -lc 'ls ~/.claude'`** -- exec runs as **root**, so `~`
  is `/root` and the command fails with "No such file or directory". Use the absolute path
  `/home/coder/.claude`. Also: the container is named **`claude-code`**, not
  `claude-code-workspace`.
- **(carried forward) docker-compose bind mount with `bind.propagation: rslave`/`rshared` on
  macOS Docker Desktop** -- daemon rejects it (`path ... is not a shared or slave mount`),
  container won't start. Use a plain bind mount; drives added after start need
  `docker compose restart`.
- **(carried forward) GitHub headless auto-auth blocked by org SAML SSO + MFA** --
  SleepNumberInc enforces Microsoft SAML+MFA on the GitHub OAuth grant; cannot clear
  headlessly. Use a PAT / the `sn-ravance` gh account for org ops. See memory
  `github-auth-saml-sso-wall`.
- **(carried forward) Docker image build behind Zscaler fails with curl exit 60** -- SSL
  cert verify failure. Export the host Zscaler Root CA to `certs/zscaler.crt`
  (`security find-certificate -a -c Zscaler -p /Library/Keychains/System.keychain > certs/zscaler.crt`)
  before `docker compose build`.
- **(carried forward) Docker VM wedges after laptop sleep** -- `docker compose up` blocks
  forever on a dead daemon. Probe with `timeout 5 docker info`; if it hangs,
  `pkill -9 -f com.docker` (kill ALL, leave `com.docker.vmnetd`) then `open -a Docker`.

## 6. Next Steps
1. **Decide the `seal` push.** Four options were put to Rob; he picked "origin only, hold
   seal" as an interim. Still open: redact the PNGs, gitignore `docs/confluence/img/`
   (affects `origin` too, so not a clean split — needs proper setup, not a hack), or accept
   the names as public. Until decided, `seal` stays 1 commit behind.
2. **`/ship-it` is referenced but not installed.** `README.md:203`, `.make-it-state.md:18`,
   and the upstream make-it overview all mention it; `~/.claude/commands/` contains 14 files
   and none is `ship-it.md`. Decide whether it was removed upstream (fix the README) or is
   genuinely missing. `docs/confluence/11-make-it-framework.md` currently carries a callout
   pointing users to `/argo-it` instead.
3. **Volume-name divergence.** `install.command:973` and `scripts/mac-preflight-lib.sh:480`
   mount `claude-code-gh`; `docker-compose.yml` declares `claude-code-gh-config`.
   `reset-claude.bat:65` removes `claude-code-gh` — matches the installer, misses compose.
   Effect: install-via-compose then reset leaves GitHub auth intact despite the reset
   claiming to clear it. Deliberately NOT documented in the Confluence pages.
4. **Run `login` at `localhost:7681`** to clear the expired Azure token in the container.
5. Offered, still undecided: patch `scripts/push-image.sh` to use the `imagetools` copy for
   ACR (or add `certs/zscaler.crt` to the buildx builder) so its ACR push stops failing.
6. Offered, still undecided: fix `config/bedrock.template.json` — `us.anthropic.claude-sonnet-5`
   and `-opus-5` lack the version suffix real Bedrock model ids carry.
7. Known tech debt, flagged not fixed: `shared-nav.js` exists in three duplicate copies
   (`welcome/`, `workshop/public/js/`, `chat/public/js/`). The `#app`-vs-nav layout overflow
   fixed in Chat likely still affects Workshop.
8. Standing constraint to carry forward: Chat's `Access-Control-Allow-Origin: *` is
   **intentional** despite `bypassPermissions`. Rob decided this. Do not re-raise or
   silently change it.
