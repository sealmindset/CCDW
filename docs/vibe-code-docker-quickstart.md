# Vibe Code Quick Start -- Docker Edition (Windows)

This guide walks you through everything you need to go from zero to building your first app with Claude Code -- using Docker. No Node.js, no Azure CLI, no GitHub CLI. Just Docker and a browser.

> **Time estimate:** First-time setup takes about 15-20 minutes of hands-on work. Some access requests require approval and may take 1-2 business days, so start early.

> **Why Docker Edition?** The standard setup requires installing Node.js, Azure CLI, GitHub CLI, and other tools directly on your Windows machine. The Docker Edition packages everything into a single container -- you just install Rancher Desktop and double-click a file. Everything else happens in your browser.

Here is what we need to do to get started.

- [Prerequisites](#prerequisites) -- Access requests (start these first, some need approval)
- [Install WSL2 and Rancher Desktop](#install-wsl2-and-rancher-desktop) -- Two installs, one reboot
- [Launch Claude Code Docker](#launch-claude-code-docker) -- Double-click and go
- [First-Time Setup](#first-time-setup) -- Azure login and GitHub login (inside your browser)
- [Vibe Coding](#vibe-coding) -- Build your first app

---

## Prerequisites

These are access requests that require approval. **Start these now** -- some take 1-2 business days.

> *Complete these in order -- some steps depend on earlier ones.*

### 1. Sleep Number VPN

The VPN connects you to Sleep Number's internal network. You'll need it to access Claude Code and related development tools.

<details>
<summary>Request VPN</summary>

- Navigate to https://sleepnumber.identitynow.com/ui/d/requestcenter/request-access
- Select "Request for Myself"
- Click "Entitlements" on the left menu
- Search for `VPNPRD_USER_SSO`
- "Select" the group, enter in a comment like "Need to install software libraries to support", then click "Save"
- Next, click "Review Request"
- Finally, click "Submit Request"

</details>

### 2. Local Admin

Your work computer normally prevents you from installing system components. You need Local Admin **once** to enable WSL2 -- a Windows feature that Rancher Desktop requires.

> **What needs Local Admin and what doesn't:**
> - **WSL2** -- needs Local Admin (it's a Windows system feature)
> - **Rancher Desktop** -- does NOT need Local Admin (installs under your own account)
> - **Everything else** -- no admin needed

<details>
<summary>Request Local Admin</summary>

- Navigate to [Service Portal](https://sleepnumber.service-now.com/sp)
- Search for `Local Admin Rights`
- Complete the form:
  - Select your system you need local admin
  - Enter the justification as "Need to enable WSL2 for Rancher Desktop and local development"
- Next, click "Submit"

> You will receive an email with further instructions.

> **Important:** You must be able to VPN into Sleep Number in order to get the temporary password you will need to elevate your privileges.

</details>

### 3. Zscaler DevOps Group

Zscaler is a security tool on your computer. Sometimes it can interfere with development tools. This access lets you temporarily pause it for up to 15 minutes when needed.

<details>
<summary>Request Zscaler</summary>

- Navigate to https://sleepnumber.identitynow.com/ui/d/requestcenter/request-access
- Select "Request for Myself"
- Click "Entitlements" on the left menu
- Search for `ZscalerPRD_DevopsZTunnel_AppC`
- "Select" the group, enter in a comment like "Need to install software libraries to support", then click "Save"
- Next, click "Review Request"
- Finally, click "Submit Request"

> **Note:** Only disable Zscaler sparingly for specific development needs, and be aware that each disablement is time-boxed to a maximum of 15 minutes.

</details>

### 4. Azure Subscription

Azure is the cloud platform that powers Claude Code at Sleep Number. You need access to the company's Azure subscription to use it.

<details>
<summary>Request Azure Access</summary>

- Navigate to https://sleepnumber.identitynow.com/ui/d/requestcenter/request-access
- Select "Request for Myself"
- Click "Entitlements" on the left menu
- Search for `AIFoundryDEV_User_AppC`
- "Select" the group, enter in a comment like "Need access to AI Foundry for Claude Code", then click "Save"
- Next, click "Review Request"
- Finally, click "Submit Request"

> This will trigger an approval process that will be sent to Sandarsh Sridhar and Lukas Menne for approval.

</details>

### 5. GitHub

GitHub is where Sleep Number stores all code. Think of it like a shared drive, but specifically designed for software projects. Your work is automatically saved, backed up, and shared with your team from here. This is a required step -- all code must live in GitHub.

<details>
<summary>Request GitHub Repo</summary>

- Navigate to https://sleepnumber.identitynow.com/ui/d/requestcenter/request-access
- Select "Request for Myself"
- Click "Entitlements" on the left menu
- Search for `githubSleepNumberIncSCIMPRD_GithubRW_AppC`
- "Select" the group, enter in a comment like "Need to maintain my code in a repo", then click "Save"
- Next, click "Review Request"
- Finally, click "Submit Request"

> This will trigger an approval process that will be sent to Sandarsh Sridhar and Lukas Menne for approval.

</details>

---

## Install WSL2 and Rancher Desktop

Two things to install, then one reboot. After that, you never need Local Admin again.

### Step 1: Install WSL2 (requires Local Admin)

WSL2 (Windows Subsystem for Linux) is a Windows feature that Rancher Desktop needs to run Docker containers. You only need to do this once.

1. Open **Command Prompt as Administrator**
   - Click Start, type `cmd`
   - Right-click **Command Prompt** and select **Run as administrator**
   - Enter your Local Admin credentials when prompted
2. Type this command and press Enter:
   ```
   wsl --install
   ```
3. Wait for it to finish -- it downloads and enables the WSL2 components
4. **Restart your computer** when prompted

> **Important:** You must restart after installing WSL2. Rancher Desktop will not work until after the reboot.

After restarting, a Ubuntu terminal window may pop up and ask you to create a username/password. You can close this window -- you don't need Ubuntu itself, just the WSL2 engine that was installed alongside it.

### Step 2: Install Rancher Desktop (no Local Admin needed)

This is the only application you install. Everything else runs inside the container.

Rancher Desktop is free, open-source, and provides the Docker engine that powers Claude Code Docker.

1. Download Rancher Desktop from https://rancherdesktop.io/
2. Run the installer -- **install it under YOUR Windows account, not a shared admin account**
   - If Windows asks you to choose "Install for all users" or "Install for me only", choose **"Install for me only"**
   - No admin password is needed for this step
3. Open Rancher Desktop from the Start menu
4. Go to **Preferences > Container Engine** and select **dockerd**
5. Wait for Rancher Desktop to finish starting up (the icon in your system tray will stop spinning)

> **Why install under your own account?** If Rancher Desktop is installed under a shared admin account, Docker commands won't work from your account due to Windows file permissions. Installing under your own account avoids this entirely.

> **Tip:** Rancher Desktop needs to be running whenever you want to use Claude Code Docker. It starts automatically with Windows, so you usually don't need to think about it.

### Step 3: Reboot one more time

After installing both WSL2 and Rancher Desktop, **restart your computer**. This ensures Rancher Desktop's Docker engine starts cleanly.

After rebooting:
- Rancher Desktop should start automatically (check for its icon in the system tray)
- Wait until the icon stops spinning before proceeding

---

## Launch Claude Code Docker

Once Rancher Desktop is running, open a command prompt and run:

```
git clone https://github.com/SleepNumberInc/CCDW.git "%USERPROFILE%\CCDW"
```

Then open the `CCDW` folder on your computer and **double-click** `install.bat`.

> **Do NOT right-click and "Run as administrator"** -- just double-click it normally. Running as admin causes files to end up in the wrong folder.

That's it. The installer handles everything from there:

- Finds Docker on your machine (checks multiple locations automatically)
- Downloads the latest Claude Code Docker image
- Creates your projects folder (`GitHub` in your user folder)
- Starts the container
- Creates a **"Claude Code"** shortcut on your desktop
- Opens the dashboard in your browser

> **Next time:** Just double-click the **"Claude Code"** shortcut on your desktop. If there's an update, it downloads automatically. You never need to run the git clone again.

---

## First-Time Setup

When the dashboard opens in your browser, you'll see three options. Click **Web Terminal** to open the terminal.

> **Important:** Make sure you're connected to the Sleep Number VPN before doing this.

On your first visit, a login wizard will guide you through signing in. It runs automatically -- just follow the prompts on screen.

### Step 1: Preflight Checks

The wizard checks that everything is in place -- your VPN connection, network access, and the AI endpoint. If something isn't right, it tells you exactly what to fix.

```
  ╭──────────────────────────────────────────────────────╮
  │  Preflight Checks                          Step 1/3  │
  ╰──────────────────────────────────────────────────────╯

  ✓ Azure CLI
  ✓ Internet connection
  ✓ Microsoft login service
  ✓ AI endpoint (VPN connected)
```

If the AI endpoint check fails, connect to the Sleep Number VPN and press Enter to retry.

### Step 2: Sign in to Azure

The wizard starts the Azure sign-in process and shows you a code and a link.

```
  ╭──────────────────────────────────────────────────────╮
  │  Azure Sign In                             Step 2/3  │
  ╰──────────────────────────────────────────────────────╯

  Enter this code at the Microsoft sign-in page:

  ┌───────────────────┐
  │   B3PBMBADU       │
  └───────────────────┘

  ▸ https://microsoft.com/devicelogin
```

1. Click the link -- it opens in your browser
2. Enter the code shown on screen
3. Sign in with your Sleep Number account (you'll complete MFA as usual)
4. Come back to the terminal -- it detects when you're done

The wizard automatically selects the correct Azure subscription for you. No need to pick from a list.

### Step 3: All Set

The wizard confirms everything is working and shows your status.

```
  ╭──────────────────────────────────────────────────────╮
  │  All Set                                   Step 3/3  │
  ╰──────────────────────────────────────────────────────╯

  ✓ Signed in as       rob.vance@sleepnumber.com
  ✓ Subscription       sn-openai-dev-01
  ✓ AI endpoint        Connected
  ✓ Session            Active
  ✓ Docker             Available

  You're all set! Type claude to start Claude Code.
  Then type /make-it to build your first app.
```

> You only need to do this once. Your login is saved and survives container restarts. Azure refreshes your session automatically in the background. If you ever get an error, just type `login` in the terminal to sign in again.

---

## Vibe Coding

You're ready to build your first app. No coding experience needed -- just describe what you want in plain English, and Claude does the rest.

> You can be brief or explain in great detail. You don't need to be technical -- just describe your idea the way you'd explain it to a coworker. What problem does it solve? Who uses it? What should it do? Share as much or as little as you want, and Claude will ask follow-up questions to fill in the gaps.

### Build Your App

**Step 1:** In the web terminal, type:

```
claude
```

**Step 2:** At the Claude prompt, type:

```
/make-it
```

**Step 3:** Claude will interview you and ask questions like:
- "What problem do you want to solve?"
- "Who's going to use it?"
- "What should it do?"
- "What do you want to call it?"

**Step 4:** Confirm your design and let Claude build. You'll see progress updates as your app comes together -- login, permissions, pages, database, and all.

**Step 5:** When the build finishes, your app opens in the browser. Explore it, click around, and log in with the test accounts Claude provides.

### Deploy Your App

When you're happy with your app and ready to share it:

**Step 1:** In the same Claude session, type:

```
/ship-it
```

**Step 2:** Claude commits your code, pushes it to GitHub, and creates a pull request. Automated security and quality checks run from there -- you just verify your app still works when asked.

> **That's it.** You describe what you want, Claude builds it, and /ship-it gets it to your team.

---

## Helpful Commands

These commands work in the web terminal (outside of Claude Code):

| Command | What it does |
|---------|-------------|
| `claude` | Start Claude Code |
| `login` | Refresh your Azure sign-in (use when you get errors) |
| `doctor` | Check if everything is working (troubleshooter) |
| `backup` | Save all your settings to a file |
| `restore <file>` | Restore settings from a backup |

---

## Troubleshooting

### "Something is not working"

Type `doctor` in the terminal. It checks everything and tells you exactly what's wrong and how to fix it.

### Azure session expired

If you get an error when using Claude, your Azure session may have expired. Just type:

```
login
```

The login wizard will clear your old session and walk you through a fresh sign-in.

### Can't reach AI service (VPN)

If you see "Can't reach the AI service" but your internet is working, connect to the Sleep Number VPN on your Windows machine, then try again.

### Container won't start

Make sure Rancher Desktop is running (check for the icon in your system tray). If it's not running, start it and wait for it to finish loading, then double-click `install.bat` again.

If you just installed Rancher Desktop and it won't start, **restart your computer**. Rancher Desktop needs WSL2 to be fully initialized, which sometimes requires a reboot.

### install.bat can't find Docker

The installer searches many locations for Docker automatically. If it still can't find it:

1. Make sure Rancher Desktop is running (system tray icon should be present)
2. Make sure Rancher Desktop was installed under **your** Windows account, not a shared admin account
3. If it was installed under a different account, the easiest fix is to install Rancher Desktop again under your own account from [rancherdesktop.io](https://rancherdesktop.io/)

### Need to start fresh

Double-click `install.bat` again. It automatically stops the old container and starts a fresh one. Your projects in the `GitHub` folder are preserved.

---

## What's Different from the Standard Setup?

| | Standard Setup | Docker Edition |
|---|---|---|
| **Install on Windows** | Node.js, Azure CLI, GitHub CLI, Claude Code, /make-it skills | WSL2 + Rancher Desktop |
| **Setup time** | 30-60 minutes | 15-20 minutes |
| **Terminal** | Windows PowerShell | Web browser |
| **Updates** | Manual (`npm update`, skill updates) | Automatic (every launch) |
| **Azure login** | Manual `az login` + pick from 37 subscriptions | Guided wizard, auto-selects subscription |
| **Troubleshooting** | Check each tool individually | Type `doctor` |

---

## Quick Reference: What Needs Local Admin?

| Action | Local Admin? | How Often? |
|--------|-------------|------------|
| Install WSL2 | Yes | Once ever |
| Install Rancher Desktop | No | Once ever |
| Run install.bat | No | Anytime |
| Daily use | No | Never |
| Updates | No | Automatic |

---

## Reference

- Claude Code Initial Setup Guide for Azure AI Foundry
- Enterprise AI Application Architecture Standards
- /make-it & /ship-it skill documentation

> Once you get all of the prerequisites -- *Done!* You're set up and ready to build. If you run into issues, reach out to the AI CoE team. Even present your app at the next company's invitational AI Hackathon to showcase what you built!
