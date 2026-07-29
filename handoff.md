# Handoff -- CCDW (Claude Code Docker Workshop)
_Written 2026-07-29 11:15 by /clear-it. Read this file in full before continuing work._

## 1. Goal
Make the CCDW terminal feel like a real macOS terminal — seamless copy/paste with no
web-layer barrier. Specifically: user can select text and copy it exactly like
Terminal.app (drag-select + ⌘C, auto-copy on release, right-click Copy/Paste, ⌘V paste).
Acceptance: native-quality selection/clipboard in the macOS app. **DONE this session.**

## 2. Current State
- **SHIPPED, committed, pushed to both remotes, built, deployed, running.**
- Branch `main`, HEAD `1dd8e26`. Working tree CLEAN. Pushed to `origin`
  (SleepNumberInc/CCDW) and `seal` (sealmindset/CCDW).
- The macOS terminal app was rewritten from a WKWebView-wraps-ttyd shell into a **real
  native terminal emulator (SwiftTerm)** that drives a `docker exec -it` PTY straight into
  the `claude-code` container. No ttyd / xterm.js / WKWebView / OSC-52 in the app path.
- App built to `~/Applications/CCDW Terminal.app` (SwiftPM `swift build -c release`, ad-hoc
  signed). Verified LIVE: app process up, spawned the expected PTY child
  (`docker exec -it -u coder -w /home/coder/Documents claude-code bash --init-file
  /opt/claude-code-docker/scripts/shell-init.sh`), no crash.
- Container `claude-code` up + healthy (unchanged this session). Browser terminal on
  :7681/:7682 (ttyd + tmux) deliberately LEFT AS-IS — only the native app changed.
- **NOT visually tested:** actual copy/paste *feel* (drag-select, ⌘C, right-click, ⌘V)
  needs Rob's hands — cannot GUI-test headless. Code paths match SwiftTerm's verified API.

## 3. Active Files
- `scripts/mac-app/Sources/CCDWTerminal/main.swift` -- NEW native app. SwiftTerm
  `LocalProcessTerminalView` subclass; docker discovery, `docker exec` PTY, all 4 copy
  behaviors, right-click menu, zoom, reconnect, container-down banner.
- `scripts/mac-app/Package.swift` -- NEW SwiftPM manifest; SwiftTerm pinned `exact("1.5.0")`.
- `scripts/mac-app/Package.resolved` -- NEW, committed for reproducible builds.
- `scripts/mac-app/build-terminal-app.sh` -- rewritten: `swift build -c release` → assemble
  + ad-hoc sign the `.app` bundle around the built binary.
- `scripts/mac-app/CCDWTerminal.swift` -- DELETED (old WKWebView wrapper).
- `.gitignore` -- added `scripts/mac-app/.build/`.
- `CHANGELOG.md` -- `### Changed` entry describing the rewrite.

## 4. Changes Made
- Native SwiftTerm terminal replaces WKWebView (committed `1dd8e26`, pushed origin+seal).
- Prior session-start commit this session: `7274ef2` docs handoff/make-it-state (pushed).
- App built + deployed to `~/Applications/CCDW Terminal.app` and relaunched (host-side
  artifact, not in git).

## 5. Failed Approaches -- DO NOT RETRY
- **Trying to get Terminal.app-native copy while xterm.js is in the loop** -- assumed the
  Edit-menu Copy / `window.getSelection()` could be wired to work natively in the WKWebView.
  FALSE: xterm.js sets `user-select: none` and draws its OWN selection overlay via its
  internal SelectionService, so `window.getSelection()` is always empty and WKWebView's
  native `copy:` has nothing to grab. The real selection lives only in `term.getSelection()`.
  Conclusion: a browser xterm can only ever *bridge* selection to the clipboard, never be
  truly native → this is why we went native (SwiftTerm). Do not reopen the WKWebView path.
- **Assuming ttyd exposes its xterm instance globally** -- it does not (`window.term` etc.
  absent; minified bundle, version-fragile). A JS bridge would have had to monkey-patch to
  capture the instance. Avoided entirely by dropping the web layer.
- **(carried forward) docker-compose bind mount with `bind.propagation: rslave`/`rshared` on
  macOS Docker Desktop** -- daemon rejects it (`path ... is not a shared or slave mount`),
  container won't start. Use a plain bind mount; drives added after start need
  `docker compose restart`.
- **(carried forward) GitHub headless auto-auth blocked by org SAML SSO + MFA** --
  SleepNumberInc enforces Microsoft SAML+MFA on the GitHub OAuth grant; cannot clear
  headlessly. Use a PAT / the `sn-ravance` gh account for org ops (that account has org
  access; `rob-vance_snlabs` gets "Repository not found" on push). See memory
  `github-auth-saml-sso-wall`.
- **(carried forward) Docker image build behind Zscaler fails with curl exit 60** -- SSL
  cert verify failure. Export the host Zscaler Root CA to `certs/zscaler.crt`
  (`security find-certificate -a -c Zscaler -p /Library/Keychains/System.keychain > certs/zscaler.crt`)
  before `docker compose build`.
- **(carried forward) Docker VM wedges after laptop sleep** -- `docker compose up` blocks
  forever on a dead daemon. Probe with `timeout 5 docker info`; if it hangs,
  `pkill -9 -f com.docker` (kill ALL, leave `com.docker.vmnetd`) then `open -a Docker`.

## 6. Next Steps
Goal is done. Remaining is validation + optional polish:
1. **Rob: hands-on test the copy feel** in the open `~/Applications/CCDW Terminal.app`
   window — drag-select + ⌘C, auto-copy on release, right-click Copy/Paste, ⌘V paste. Note:
   full-screen TUIs (claude/vim/less) grab the mouse; **hold Shift to force a manual text
   selection** (Terminal.app + ssh/tmux behavior). Report anything that feels off.
2. If distribution beyond this Mac is wanted: replace ad-hoc sign in
   `build-terminal-app.sh` with a Developer ID cert + notarization (unsigned/ad-hoc won't
   launch on other machines — see memory `macos-app-signing-distribution`).
3. Optional: silence the 3 cosmetic `Selector(("copy:"))` build warnings by switching the
   Edit-menu items to `#selector(NSText.copy(_:))` etc. (functionally identical).
4. Optional (only if browser terminal parity is wanted): the original plan considered
   dropping tmux from ttyd — NOT done, because going native fixed selection at the source
   and dropping tmux would only cost :7681/:7682 browser users their session persistence.
