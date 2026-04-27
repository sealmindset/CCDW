# Vibe Code for Windows

This guide walks you through everything you need to go from zero to building your first app with Claude Code -- using Docker. No Node.js, no Azure CLI, no GitHub CLI. Just Docker and a browser.

> **Time estimate:** First-time setup takes about 15-20 minutes of hands-on work. Some access requests require approval and may take 1-2 business days, so start early.

> **Why Docker Edition?** The standard setup requires installing Node.js, Azure CLI, GitHub CLI, and other tools directly on your Windows machine. The Docker Edition packages everything into a single container -- you just install Rancher Desktop and double-click a file. Everything else happens in your browser.

## Overview

There are two phases. **Phase 1** is access requests you submit now (some need approval). **Phase 2** is the actual install -- you'll do this after your access is approved.

| Phase | What you do | Time |
|-------|------------|------|
| **1. Request Access** | Submit 5 access requests online | 10 minutes now, 1-2 days to get approved |
| **2. Install & Go** | Download one file, double-click, follow prompts | 15-20 minutes |

> **Never open any terminal or PowerShell as Admin.** When Windows asks for an admin password during setup, use the credentials from your Local Admin email (the SSMITH account). But always open terminals normally -- never right-click "Run as administrator."

---

## Phase 1: Request Access

These are access requests that require approval. **Submit all 5 now** -- some take 1-2 business days. You can't proceed to Phase 2 until they're approved.

> *Complete these in order -- some steps depend on earlier ones.*

### 1. Sleep Number VPN

The VPN connects you to Sleep Number's internal network. You'll need it to access Claude Code.

- Navigate to https://sleepnumber.identitynow.com/ui/d/requestcenter/request-access
- Select "Request for Myself"
- Click "Entitlements" on the left menu
- Search for `VPNPRD_USER_SSO`

`[SCREENSHOT: IdentityNow search results showing VPNPRD_USER_SSO]`

- "Select" the group, enter in a comment like "Need to install software libraries to support", then click "Save"
- Click "Review Request"
- Click "Submit Request"

### 2. Local Admin

Your work computer normally prevents you from installing system components. You need Local Admin **once** to enable WSL2 (a Windows feature that Docker needs).

> **What needs Local Admin and what doesn't:**
>
> - **WSL2** -- needs Local Admin (one-time Windows feature)
> - **Rancher Desktop** -- does NOT need Local Admin
> - **Everything else** -- no admin needed

- Navigate to [Service Portal](https://sleepnumber.service-now.com)
- Search for `Local Admin Rights`
- Complete the form:
  - Select your system you need local admin
  - Enter the justification as "Need to enable WSL2 for Rancher Desktop and local development"
- Click "Submit"

`[SCREENSHOT: ServiceNow Local Admin Rights form]`

> You will receive an email with your temporary admin credentials. **Save this email** -- you'll need the password during install.
>
> **Important:** You must be on the VPN to receive the credentials email.

### 3. Zscaler DevOps Group

Zscaler is a security tool on your computer. This access is a safety net in case it interferes during setup.

- Navigate to https://sleepnumber.identitynow.com/ui/d/requestcenter/request-access
- Select "Request for Myself"
- Click "Entitlements" on the left menu
- Search for `ZscalerPRD_DevopsZTunnel_AppC`
- "Select" the group, enter a comment like "Need to install software libraries to support", then click "Save"
- Click "Review Request", then "Submit Request"

> **Note:** You probably won't need to disable Zscaler. This is just insurance in case something blocks during install.

### 4. Azure Subscription

Azure is the cloud platform that powers Claude Code at Sleep Number.

- Navigate to https://sleepnumber.identitynow.com/ui/d/requestcenter/request-access
- Select "Request for Myself"
- Click "Entitlements" on the left menu
- Search for `AIFoundryDEV_User_AppC`
- "Select" the group, enter a comment like "Need access to AI Foundry for Claude Code", then click "Save"
- Click "Review Request", then "Submit Request"

> This requires approval from Sandarsh Sridhar and Lukas Menne. You'll get an email when approved.

### 5. GitHub

GitHub is where Sleep Number stores all code. Think of it like a shared drive for software projects.

- Navigate to https://sleepnumber.identitynow.com/ui/d/requestcenter/request-access
- Select "Request for Myself"
- Click "Entitlements" on the left menu
- Search for `githubSleepNumberIncSCIMPRD_GithubRW_AppC`
- "Select" the group, enter a comment like "Need to maintain my code in a repo", then click "Save"
- Click "Review Request", then "Submit Request"

> This also requires approval. You'll get an email when approved.

### Checklist

Before moving to Phase 2, make sure you have:

- [ ] VPN access (can connect to Sleep Number VPN)
- [ ] Local Admin credentials (email with SSMITH password)
- [ ] Zscaler DevOps group (approved)
- [ ] Azure subscription (approved)
- [ ] GitHub access (approved)

---

## Phase 2: Install & Go

All access approved? Let's install. This is a one-time process.

### Step 1: Download the setup file

Download **setup-claude.bat** from the Confluence page attachment.

`[SCREENSHOT: Confluence page showing the setup-claude.bat attachment with download arrow]`

Save it anywhere you can find it -- your Desktop or Downloads folder works fine.

### Step 2: Double-click setup-claude.bat

Find the file you downloaded and **double-click it**. A black window appears with progress messages.

`[SCREENSHOT: setup-claude.bat window showing "Claude Code - Setup" header]`

> **Do NOT right-click and "Run as administrator"** -- just double-click normally.

The setup file does everything automatically. It will walk you through a few steps:

#### What you'll see: Git

If Git isn't installed yet, the setup installs it for you. You'll see:

```
[...]  Checking for Git...
[...]  Git is not installed. Installing now...
[OK]   Git installed.
```

`[SCREENSHOT: setup window showing Git installation progress]`

If it asks you to restart after installing Git, do so, then double-click `setup-claude.bat` again.

#### What you'll see: WSL2

If WSL2 isn't installed, the setup installs it. **Windows will ask for an admin password:**

`[SCREENSHOT: Windows UAC dialog asking for admin password]`

Enter the SSMITH admin credentials from your Local Admin email (Phase 1, step 2).

After WSL2 installs, you **must restart your computer**. Then double-click `setup-claude.bat` again.

> After restarting, a Ubuntu window may pop up asking you to create a username. **Just close it** -- you don't need it.

#### What you'll see: Rancher Desktop

If Rancher Desktop isn't installed, the setup installs it. No admin password needed.

After it installs, **restart your computer one more time**. Then double-click `setup-claude.bat` again.

After restarting, look for the Rancher Desktop icon in your system tray (bottom-right corner, near the clock):

`[SCREENSHOT: Windows system tray showing Rancher Desktop icon, with arrow pointing to it]`

**Wait for the icon to stop spinning** before continuing. This means Docker is ready.

> **Tip:** Rancher Desktop starts automatically with Windows. You'll see this icon every day -- it just means Docker is running in the background.

#### What you'll see: AI Provider

The installer asks you to choose your AI provider. **Press 1** for Azure AI Foundry:

```
========================================
  Choose your AI provider:
========================================

    1. Azure AI Foundry  (Claude via Azure)
    2. AWS Bedrock       (Claude via AWS)
    3. Anthropic API     (direct API key)
    4. Skip for now      (edit .env manually)

Enter choice: _
```

`[SCREENSHOT: install.bat provider selection screen]`

#### What you'll see: Passphrase

The installer asks for a setup passphrase. **Type `ccdw`** (lowercase) and press Enter:

```
========================================
  AI Foundry Setup
========================================

  Enter the setup passphrase to activate Claude.
  (Get this from your team lead or the AI CoE team.)
  Press Enter to skip (will use Azure SSO instead).

  Setup passphrase: _
```

`[SCREENSHOT: install.bat passphrase prompt]`

> **The passphrase is `ccdw`** (all lowercase). This activates Claude so it works immediately. If you don't have it, ask your team lead or the AI CoE team.

#### What you'll see: Finishing up

The installer downloads everything it needs, starts the container, and opens your browser:

```
[OK]  Image downloaded via registry.
[OK]  Container started.
[OK]  Dashboard: http://localhost:3000
```

`[SCREENSHOT: install.bat completion screen with success messages]`

Your browser opens automatically to the Claude Code dashboard:

`[SCREENSHOT: Welcome Dashboard showing three tiles - Web Terminal, VS Code, Workshop]`

**You're installed.** A "Claude Code" shortcut is on your desktop for next time.

---

### Step 3: Connect to GitHub (one time)

You need to connect to GitHub once so Claude can save your work.

1. On the dashboard, click **Web Terminal**

`[SCREENSHOT: Welcome Dashboard with arrow pointing to Web Terminal tile]`

2. In the terminal, type `gh auth login` and press Enter

`[SCREENSHOT: Web terminal showing gh auth login command]`

3. Use the arrow keys to select **GitHub.com** and press Enter
4. Select **HTTPS** and press Enter
5. Select **Login with a web browser** and press Enter
6. The terminal shows a one-time code (like `A1B2-C3D4`). **Copy this code.**

`[SCREENSHOT: Terminal showing the one-time code highlighted]`

7. The terminal also shows a link. **Click the link** or open it in your browser
8. Paste the code on the GitHub page
9. Sign in with your Sleep Number GitHub account
10. Click "Authorize"

`[SCREENSHOT: GitHub authorization page]`

11. Come back to the terminal -- it shows "Logged in" when done

`[SCREENSHOT: Terminal showing successful gh auth login]`

> You only do this once. Your GitHub login is saved permanently.

---

## Vibe Coding

You're ready to build your first app. No coding experience needed.

> Describe your idea the way you'd explain it to a coworker. What problem does it solve? Who uses it? What should it do? Claude will ask follow-up questions to fill in the gaps.

### Build Your App

**Step 1:** In the web terminal, type `claude` and press Enter

`[SCREENSHOT: Terminal with "claude" typed, showing Claude Code starting up]`

**Step 2:** At the Claude prompt (you'll see a `>` cursor), type `/make-it` and press Enter

`[SCREENSHOT: Claude Code prompt with /make-it typed]`

**Step 3:** Claude interviews you:

- "What problem do you want to solve?"
- "Who's going to use it?"
- "What should it do?"
- "What do you want to call it?"

Answer in plain English. Be as brief or detailed as you want.

`[SCREENSHOT: Claude Code /make-it interview showing questions and example answers]`

**Step 4:** Claude shows you a summary of what it will build. Review it and confirm.

**Step 5:** Watch Claude build your app. You'll see progress updates:

`[SCREENSHOT: Claude Code build progress showing checkmarks for database, auth, pages, etc.]`

**Step 6:** When done, your app opens in the browser. Explore it, click around, and try logging in with the test accounts Claude provides.

`[SCREENSHOT: Example finished app in browser showing login page]`

### Deploy Your App

When you're happy with your app and ready to share it:

**Step 1:** In the same Claude session, type `/ship-it`

**Step 2:** Claude commits your code, pushes it to GitHub, and creates a pull request.

> **That's it.** You describe what you want, Claude builds it, and /ship-it gets it to your team.

> Before you can /ship-it, make sure you completed the GitHub login in Step 3 above.

---

## Daily Use

After the one-time setup, your daily workflow is:

1. **Double-click "Claude Code"** on your desktop
2. Your browser opens to the dashboard
3. Click **Web Terminal**
4. Type `claude`
5. Start building (or type `/resume-it` to continue a previous project)

> If Rancher Desktop isn't running, start it from the Start menu and wait for the icon to stop spinning.

---

## Helpful Commands

These commands work in the web terminal (outside of Claude Code):

| Command | What it does |
|---------|-------------|
| `claude` | Start Claude Code |
| `doctor` | Check if everything is working (troubleshooter) |
| `login` | Refresh your Azure sign-in (if using SSO) |
| `backup` | Save all your settings to a file |
| `restore <file>` | Restore settings from a backup |

---

## Troubleshooting

### "Something is not working"

Type `doctor` in the terminal. It checks everything and tells you exactly what's wrong and how to fix it.

### Setup file says "restart your computer"

This is normal during first-time install. You may need to restart up to 2 times:
1. After WSL2 installs
2. After Rancher Desktop installs

After each restart, just double-click `setup-claude.bat` again. It picks up where it left off.

### Can't reach AI service (VPN)

If you see "Can't reach the AI service" but your internet is working, connect to the Sleep Number VPN on your Windows machine, then try again.

### Container won't start

Make sure Rancher Desktop is running (check for the icon in your system tray). If it's not running:

1. Open the Start menu
2. Search for "Rancher Desktop"
3. Click to open it
4. Wait for the icon to stop spinning (1-2 minutes)
5. Then double-click `setup-claude.bat` again

`[SCREENSHOT: Windows Start menu search showing Rancher Desktop]`

### install.bat can't find Docker

1. Make sure Rancher Desktop is running (system tray icon should be present)
2. Make sure Rancher Desktop was installed under **your** Windows account, not the SSMITH admin account
3. If it was installed under the wrong account, uninstall it, then double-click `setup-claude.bat` -- it will reinstall under your account

### Need to start fresh

Double-click `setup-claude.bat` again. It automatically stops the old container and starts a fresh one. Your projects in the `GitHub` folder are preserved.

### Wrong passphrase or skipped it

Double-click `setup-claude.bat` again. It will detect that the API key is missing and prompt you for the passphrase.

### Azure SSO Fallback

If you don't have the setup passphrase, Claude uses Azure sign-in instead. On your first visit to the web terminal, a login wizard guides you through:

1. **Preflight Checks** -- The wizard checks your VPN connection and network access
2. **Sign in to Azure** -- The wizard shows a code and a link. Open the link in your browser, enter the code, sign in with your Sleep Number account
3. **All Set** -- The wizard confirms everything is working

> If you ever get an error, type `login` in the terminal to sign in again.

---

## What's Different from the Standard Setup?

|  | Standard Setup | Docker Edition |
|---|---|---|
| **Install on Windows** | Node.js, Azure CLI, GitHub CLI, Claude Code, /make-it skills | Download one file, double-click |
| **Setup time** | 60 minutes to hours | 15-20 minutes |
| **Terminal** | Windows PowerShell | Web browser |
| **Updates** | Manual (`npm update`, skill updates) | Automatic (every launch) |
| **Azure login** | Manual `az login` + pick from 37 subscriptions | Setup passphrase (one-time) |
| **Troubleshooting** | Check each tool individually | Type `doctor` |

## Quick Reference: What Needs Local Admin?

| Action | Local Admin? | How Often? |
|--------|-------------|-----------|
| Install WSL2 | Yes (SSMITH password) | Once ever |
| Install Rancher Desktop | No | Once ever |
| Run setup-claude.bat | No | Anytime |
| Daily use | No | Never |
| Updates | No | Automatic |

---

## Getting Help

- **Type `doctor`** in the terminal -- it diagnoses most issues automatically
- **Ask your team champion** -- they've been through the setup and can help
- **Contact the AI CoE team** -- for access issues or passphrase questions
- **Re-run `setup-claude.bat`** -- it's safe to run multiple times and fixes most install issues

> Once you're set up -- *Done!* You're ready to build. Even present your app at the next company's invitational AI Hackathon to showcase what you built!
