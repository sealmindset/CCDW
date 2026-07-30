# Troubleshooting

Most CCDW problems are one of three things: **you are signed out**, **the
container is not running**, or **you are not on the VPN**. Check those three
before anything else.

---

## Start here

| Symptom | Most likely cause | Fix |
|---|---|---|
| "AI provider not configured" | Sign-in expired | Type `login` in the **Terminal** page |
| "Token has expired" | Sign-in expired | Same |
| Page will not load at all | Container not running | Double-click the **Claude Code** desktop shortcut |
| Everything is slow or times out | Not on VPN | Connect the corporate VPN |
| Model list is empty or wrong | Sign-in expired | Sign in, then click **Refresh** on the Dashboard |

If none of those fit, find your symptom below.

---

## Nothing loads — "this site can't be reached"

The container is not running.

1. Double-click the **Claude Code** shortcut on your desktop.
2. Wait 60 seconds. Startup is not instant.
3. Go to `http://localhost:3000`.

Still nothing? Check that Rancher Desktop is running — look for its icon in the
menu bar (Mac) or system tray (Windows). If it is not there, launch it, wait for
it to finish starting, then try the shortcut again.

**On a Mac, if Rancher Desktop is misbehaving after an update or crash**, there is
a repair script in the CCDW folder:

```
fix-rancher-mac.command
```

Double-click it.

---

## "AI provider not configured" / "Token has expired"

Your sign-in ran out. This is normal and happens roughly daily.

**Fastest fix:** open `http://localhost:7681` and type:

```
login
```

Follow the prompts, then reload whichever page you were on.

**Alternative:** open the **Dashboard**. If there is a sign-in banner with a
code, click **Open Sign-in Page**, enter the code, and approve.

**If sign-in itself fails**, you are almost certainly off the VPN. Connect and
try again.

---

## Everything is slow, or requests time out

**Check the VPN first.** If your organization uses Azure AI Foundry or AWS
Bedrock, you must be on the corporate network. Off-VPN, requests hang and then
fail.

**Check the AI Provider dot on the Dashboard.** Green means the connection is
healthy and the slowness is elsewhere.

**Consider what you asked.** Large jobs genuinely take a long time. A Workshop
build touching many files can run for tens of minutes. Slow is not always broken.

---

## A port is already in use

CCDW needs ports 3000, 3002, 7681, 8080, and 9200. If another program has one,
CCDW will say so by name at startup.

**Fix:** quit the other program and relaunch CCDW. The startup message tells you
what is holding the port.

---

## Run the built-in diagnostics

CCDW ships with a self-check that inspects Docker, the image, container health,
ports, network, disk space, and configuration — without reinstalling anything.

**macOS:**

```bash
./install.command --doctor
```

It prints a pass/fail list. This is the single most useful thing to run before
asking for help.

**Windows:** there is no `--doctor` flag. Run `help-claude.bat` from the CCDW
folder instead, and attach `Desktop\claude-setup.log` when you ask for help.

---

## Find the setup log

Everything the installer prints is saved to:

```
~/Desktop/claude-setup.log
```

On Windows that is `Desktop\claude-setup.log` in your user folder.

**Attach this file whenever you ask for help.** It usually contains the actual
error, which is often several screens above where you noticed the problem.

---

## Workshop problems

**A build seems stuck.**
Check the provider indicator in the top right. Amber or red means your sign-in
expired mid-build. Sign in again and start a new request.

**The app it built does not work as expected.**
Describe the problem as a new change request in the **Changes** panel, in plain
English: "When I upload a CSV with more than 100 rows, the table is empty." It
will investigate and fix.

**"See your app" is greyed out.**
The app is not running yet. Wait for the status to reach **Demo Ready**.

**I deleted a project by accident.**
Deletion is permanent. Check whether your organization backs up `Documents`;
otherwise it is gone. Back up projects you care about.

---

## Claude Chat problems

**The message box is disabled.**
A turn is already running. Wait, or click the stop button.

**"Could not read that folder."**
It is outside `Documents`, `Desktop`, `Downloads`, or an external drive. Copy
what you need into one of those.

**An external drive is not showing up.**
Drives plugged in *after* CCDW started are not visible. Restart CCDW with the
drive connected.

**Claude changed the wrong files.**
Check the folder chip at the top — the conversation may be bound to a broader
folder than you intended. If the folder is a git repository you can undo the
changes; otherwise restore from backup. Bind conversations narrowly to avoid
this.

---

## VS Code problems

**It takes forever to load.**
The first load is slow — 10 to 20 seconds — while it builds a browser cache.
Later loads are fast.

**My edit did not take effect.**
You did not save. `Cmd + S` on Mac, `Ctrl + S` on Windows. Unsaved tabs show a
dot instead of a close button.

**A welcome/walkthrough tab keeps appearing.**
That is VS Code's own onboarding. Close it; it stops eventually.

---

## Terminal problems

**Nothing happens when I type.**
Claude may be working. Wait. If it is genuinely stuck, press `Ctrl + C`.

**"command not found."**
You typed a system command that does not exist. To ask Claude something, just
write it as a sentence.

**I lost my session.**
You probably did not — reopen `localhost:7681` and it should still be there.
Sessions survive closing the browser.

---

## Reset options, least to most drastic

| Action | What it costs |
|---|---|
| Reload the browser page | Nothing |
| Restart the container (relaunch the shortcut) | In-flight work only |
| Re-run the installer | Nothing — projects and settings are preserved |
| Remove and reinstall the container | Chat conversations and container-side settings; **projects in `Documents` survive** |

Re-running the installer is safe and is the standard way to update. It is
usually the right escalation.

---

## When to ask for help

Ask when:

- The self-check reports a failure you do not understand.
- The same error survives a restart and a re-install.
- Sign-in fails while you are definitely on the VPN — that is an account or
  access issue, not a CCDW issue.

**Include in your request:**

1. Which page (Dashboard / Workshop / Claude Chat / VS Code / Terminal).
2. What you were doing.
3. The exact error text, copied — not paraphrased.
4. `~/Desktop/claude-setup.log`.
5. The output of `--doctor` (macOS).

That set answers almost every follow-up question in advance.

---

## Related pages

- **Getting Started** — installation and sign-in, step by step.
- **Dashboard** — the health indicators that name most problems.
- **What CCDW Remembers** — what a reset costs, and what survives it.
- **Glossary** — plain-English definitions for the terms above.
