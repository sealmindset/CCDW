# Vibe Code for Windows

## Overview

> **Keep In Mind:** This document is being updated on a daily basis as we work to refine it and improve the setup experience. And you can help. If you copy and paste the errors you have encountered in the comments section of this page (at the bottom), this will enable us to accelerate fixing the issues and bugs.

> **Note:** The bugs you are encountering is not something you are doing incorrectly. It's likely an issue with leveraging AI on Windows and the application of the Sleep Number's applied safeguards.

This guide walks you through everything you need to go from zero to building your first app with Claude Code -- using Docker. No Node.js, no Azure CLI, no GitHub CLI. Just Docker and a browser.

> **Time estimate:** First-time setup takes about 15-20 minutes of hands-on work. Some access requests require approval and may take 1-2 business days, so start early.

> **Why Docker Edition?** The standard setup requires installing Node.js, Azure CLI, GitHub CLI, and other tools directly on your Windows machine. The Docker Edition packages everything into a single container -- you just install Rancher Desktop and double-click a file. Everything else happens in your browser.

There are two phases. **Phase 1** is access requests you submit now (some need approval). **Phase 2** is the actual install -- you'll do this **after** your access is approved.

| Phase | What you do | Time |
|---|---|---|
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

- Navigate to Service Portal ( https://sleepnumber.service-now.com/sp )
- Search for `Local Admin Rights`
- Complete the form:
  - Select your system you need local admin
  - Enter the justification as "Need to enable WSL2 for Rancher Desktop and local development"
- Click "Submit"

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

> **Never open any terminal or PowerShell as Admin.** When Windows asks for an admin password during setup, use the credentials from your Local Admin email (the SSMITH account). But always open terminals normally -- never right-click "Run as administrator."

### Step 1: VPN in Sleep Number

Whenever you want to use the AI Services offered by Sleep Number, always start with logging into VPN.

### Step 2: Download the setup file

Download the **setup-claude.bat** file from the link provided below.

Save it anywhere you can find it -- your Desktop or Downloads folder works fine.

### Step 3: Double-click setup-claude.bat

Find the file you downloaded and **double-click it**. A black window appears with progress messages.

> **Do NOT right-click and "Run as administrator"** -- just double-click normally.

The setup file does everything automatically. It will walk you through a few steps:

#### What you'll see: Git

If Git isn't installed yet, the setup installs it for you. You'll see:

```
[...] Checking for Git...
[...] Git is not installed. Installing now...
[OK]  Git installed.
```

If it asks you to restart after installing Git, do so, then double-click `setup-claude.bat` again.

#### What you'll see: WSL2

The setup checks whether WSL2 (Windows Subsystem for Linux) is working. WSL2 is a Windows feature that Docker needs to run containers. Here's what may happen:

**If WSL2 is already working:** The setup skips ahead -- you won't see anything about WSL2 at all. This is common on newer machines with clean Windows 11 installs.

**If Windows features need to be enabled (common on older or corporate machines):** The setup detects that two required Windows features ("Virtual Machine Platform" and "Windows Subsystem for Linux") are not turned on. You'll see:

```
[INFO] Windows feature "Virtual Machine Platform" is not enabled.
[INFO] Windows feature "Windows Subsystem for Linux" is not enabled.
[INFO] Enabling required Windows features (admin required)...
```

**Windows will ask for an admin password.** Enter the SSMITH admin credentials from your Local Admin email (Phase 1, step 2).

After enabling the features, your computer **must restart**. The setup handles this automatically -- you'll see a 10-second countdown:

```
[INFO] Windows features enabled. A reboot is required.
[INFO] This setup will resume automatically after restart.
[INFO] Rebooting in 10 seconds...
```

**You don't need to do anything.** After restarting, the setup resumes on its own -- no need to double-click the file again. It picks up right where it left off.

> After restarting, a Ubuntu window may pop up asking you to create a username. **Just close it** -- you don't need it.

**If features are already enabled but WSL still isn't working:** The setup falls back to running `wsl --install` and `wsl --update` to repair it. Windows may ask for an admin password again. After this completes, you **must restart your computer**. Then double-click `setup-claude.bat` again.

#### What you'll see: Rancher Desktop

If Rancher Desktop isn't installed, the setup installs it. No admin password needed.

After it installs, **restart your computer one more time**. Then double-click `setup-claude.bat` again.

After restarting, look for the Rancher Desktop icon in your system tray (bottom-right corner, near the clock).

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

> **The passphrase is `ccdw`** (all lowercase). This activates Claude so it works immediately. If you don't have it, ask your team lead or the AI CoE team.

#### What you'll see: Finishing up

The installer downloads everything it needs, starts the container, and opens your browser:

```
[OK] Image downloaded via registry.
[OK] Container started.
[OK] Dashboard: http://localhost:3000
```

Your browser opens automatically to the Claude Code dashboard.

**You're installed.** A "Claude Code" shortcut is on your desktop for next time.

---

### Step 4: Connect to GitHub (one time)

You need to connect to GitHub once so Claude can save your work.

1. On the dashboard, click **Web Terminal**
2. In the terminal, type `gh auth login` and press Enter
3. Use the arrow keys to select **GitHub.com** and press Enter
4. Select **HTTPS** and press Enter
5. Select **Login with a web browser** and press Enter
6. The terminal shows a one-time code (like `A1B2-C3D4`). **Copy this code.**
7. The terminal also shows a link. **Click the link** or open it in your browser
8. Paste the code on the GitHub page
9. Sign in with your Sleep Number GitHub account
10. Click "Authorize"
11. Come back to the terminal -- it shows "Logged in" when done

> You only do this once. Your GitHub login is saved permanently.

---

## Vibe Coding

You're ready to build your first app. No coding experience needed.

> Describe your idea the way you'd explain it to a coworker. What problem does it solve? Who uses it? What should it do? Claude will ask follow-up questions to fill in the gaps.

### Build Your App

**Step 1:** In the web terminal, type `claude` and press Enter

**Step 2:** At the Claude prompt (you'll see a `>` cursor), type `/make-it` and press Enter

**Step 3:** Claude interviews you:

- "What problem do you want to solve?"
- "Who's going to use it?"
- "What should it do?"
- "What do you want to call it?"
