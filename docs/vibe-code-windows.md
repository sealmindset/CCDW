# Vibe Code for Windows

This guide walks you through everything you need to go from zero to building your first app with Claude Code -- using Docker. No Node.js, no Azure CLI, no GitHub CLI. Just Docker and a browser.

> **Time estimate:** First-time setup takes about 15-20 minutes of hands-on work. Some access requests require approval and may take 1-2 business days, so start early.

> **Why Docker Edition?** The standard setup requires installing Node.js, Azure CLI, GitHub CLI, and other tools directly on your Windows machine. The Docker Edition packages everything into a single container -- you just install Rancher Desktop and double-click a file. Everything else happens in your browser.

---

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

- Navigate to [https://sleepnumber.identitynow.com/ui/d/requestcenter/request-access](https://sleepnumber.identitynow.com/ui/d/requestcenter/request-access)
- Select "Request for Myself"
- Click "Entitlements" on the left menu
- Search for `VPNPRD_USER_SSO`
- "Select" the group, enter a comment like "Need to install software libraries to support", then click "Save"
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

> You will receive an email with your temporary admin credentials. **Save this email** -- you'll need the password during install.

> **Important:** You must be on the VPN to receive the credentials email.

### 3. Zscaler DevOps Group

Zscaler is a security tool on your computer. This access is a safety net in case it interferes during setup.

- Navigate to [https://sleepnumber.identitynow.com/ui/d/requestcenter/request-access](https://sleepnumber.identitynow.com/ui/d/requestcenter/request-access)
- Select "Request for Myself"
- Click "Entitlements" on the left menu
- Search for `ZscalerPRD_DevopsZTunnel_AppC`
- "Select" the group, enter a comment like "Need to install software libraries to support", then click "Save"
- Click "Review Request", then "Submit Request"

> **Note:** You probably won't need to disable Zscaler. This is just insurance in case something blocks during install.

### 4. Azure Subscription

Azure is the cloud platform that powers Claude Code at Sleep Number.

- Navigate to [https://sleepnumber.identitynow.com/ui/d/requestcenter/request-access](https://sleepnumber.identitynow.com/ui/d/requestcenter/request-access)
- Select "Request for Myself"
- Click "Entitlements" on the left menu
- Search for `AIFoundryDEV_User_AppC`
- "Select" the group, enter a comment like "Need access to AI Foundry for Claude Code", then click "Save"
- Click "Review Request", then "Submit Request"

> This requires approval from Sandarsh Sridhar and Lukas Menne. You'll get an email when approved.

### 5. GitHub

GitHub is where Sleep Number stores all code. Think of it like a shared drive for software projects.

- Navigate to [https://sleepnumber.identitynow.com/ui/d/requestcenter/request-access](https://sleepnumber.identitynow.com/ui/d/requestcenter/request-access)
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

### Step 1: Connect your VPN

Before starting, make sure your VPN is connected:

1. Look for the **GlobalProtect** icon in the system tray (bottom-right corner, near the clock)
2. Click it and make sure it says **"Connected"**
3. If you don't see it, search for "GlobalProtect" in the Start menu and open it

> The setup will check your VPN connection and pause with instructions if it's not connected. But it's faster to connect first.

### Step 2: Download the setup file

Download **setup-claude.bat** from the link below.

> *[Attach setup-claude.bat to this Confluence page]*

Save it anywhere you can find it -- your Desktop or Downloads folder works fine.

### Step 3: Double-click setup-claude.bat

Find the file you downloaded and **double-click it**. A black window appears with progress messages.

> **Do NOT right-click and "Run as administrator"** -- just double-click normally.

The setup file does everything automatically. It will walk you through a few steps:

#### What you'll see: Internet & VPN check

The setup first checks that you can reach the internet and Sleep Number's network. If your VPN isn't connected, it will pause and show you how to connect before continuing.

```
[OK]  Internet connection.
[OK]  VPN connected.
```

#### What you'll see: Git

If Git isn't installed yet, the setup installs it for you. You'll see:

```
[...]  Checking for Git...
[...]  Git is not installed. Installing now...
[OK]   Git installed.
```

#### What you'll see: WSL2

If WSL2 isn't installed, the setup installs it. **Windows will ask for an admin password:**

Enter the SSMITH admin credentials from your Local Admin email (Phase 1, step 2).

After WSL2 installs, your computer **must restart**. The setup will try to resume automatically after restart. If it doesn't, just double-click setup-claude.bat again -- it picks up where it left off.

> After restarting, a Ubuntu window may pop up asking you to create a username. **Just close it** -- you don't need it.

#### What you'll see: Rancher Desktop

If Rancher Desktop isn't installed, the setup installs it. No admin password needed.

The setup waits for the installation to finish completely before continuing. You'll see:

```
[...]  Installing Rancher Desktop...
         (this may take a few minutes)
[...]  Verifying installation...
[OK]   Rancher Desktop installed.
```

After it installs, **restart your computer**. Setup resumes automatically after restart. If it doesn't, double-click setup-claude.bat again.

After restarting, look for the Rancher Desktop icon in your system tray (bottom-right corner, near the clock):

**Wait for the icon to stop spinning** before continuing. This means Docker is ready.

> **Tip:** Rancher Desktop starts automatically with Windows. You'll see this icon every day -- it just means Docker is running in the background.

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
[OK]  Image downloaded via registry.
[OK]  Container started.
[OK]  Dashboard: http://localhost:3000
```

Your browser opens automatically. It will redirect you to **Workshop** -- the app builder where you'll create your projects.

**You're installed.** A "Claude Code" shortcut is on your desktop for next time.

---

### Step 4: Connect to GitHub (one time)

You need to connect to GitHub once so Claude can save your work.

1. Open [http://localhost:3000?dashboard](http://localhost:3000?dashboard) to get to the dashboard
2. Click **Web Terminal**
3. In the terminal, type `gh auth login` and press Enter
4. Use the arrow keys to select **GitHub.com** and press Enter
5. Select **HTTPS** and press Enter
6. Select **Login with a web browser** and press Enter
7. The terminal shows a one-time code (like `A1B2-C3D4`). **Copy this code.**
8. The terminal also shows a link. **Click the link** or open it in your browser
9. Paste the code on the GitHub page
10. Sign in with your Sleep Number GitHub account
11. Click "Authorize"
12. Come back to the terminal -- it shows "Logged in" when done

> You only do this once. Your GitHub login is saved permanently.

---

## Vibe Coding

You're ready to build your first app. No coding experience needed.

> Describe your idea the way you'd explain it to a coworker. What problem does it solve? Who uses it? What should it do? Claude will ask follow-up questions to fill in the gaps.

### Build Your App (Workshop -- recommended)

Workshop is the easiest way to build. No terminal needed.

**Step 1:** Open Workshop -- your browser should already be there. If not, go to [http://localhost:9200](http://localhost:9200)

**Step 2:** Click **New Project** and give it a name

**Step 3:** Describe what you want to build. Be as brief or detailed as you want. Examples:
- "A team dashboard that tracks our sprint progress"
- "A form where customers submit feedback and we can review it"
- "An inventory tracker for our warehouse"

**Step 4:** Workshop interviews you to clarify your idea, then shows a summary. Review and confirm.

**Step 5:** Watch Claude build your app. You'll see progress on the Bifrost bar as it moves through each phase.

**Step 6:** When done, click **Try It** to see your app. Explore it, click around, and try logging in with the test accounts Claude provides.

### Build Your App (Terminal -- advanced)

If you prefer the terminal:

**Step 1:** Open [http://localhost:3000?dashboard](http://localhost:3000?dashboard) and click **Web Terminal**

**Step 2:** Type `claude` and press Enter

**Step 3:** At the Claude prompt (you'll see a `>` cursor), type `/make-it` and press Enter

**Step 4:** Claude interviews you:
- "What problem do you want to solve?"
- "Who's going to use it?"
- "What should it do?"
- "What do you want to call it?"

Answer in plain English. Be as brief or detailed as you want.

**Step 5:** Claude shows you a summary of what it will build. Review and confirm.

**Step 6:** Watch Claude build your app. You'll see progress updates.

**Step 7:** When done, your app opens in the browser. Explore it, click around, and try logging in with the test accounts Claude provides.

### Deploy Your App

When you're happy with your app and ready to share it:

**Step 1:** In the same Claude session, type `/ship-it`

**Step 2:** Claude commits your code, pushes it to GitHub, and creates a pull request.

> **That's it.** You describe what you want, Claude builds it, and /ship-it gets it to your team.

> Before you can /ship-it, make sure you completed the GitHub login in Step 4 above.

---

## Daily Use

After the one-time setup, your daily workflow is:

1. **Double-click "Claude Code"** on your desktop
2. Your browser opens to Workshop
3. Create a new project or continue an existing one
4. Start building

> The desktop shortcut automatically starts Rancher Desktop (Docker) if it isn't running. You don't need to start it manually -- just wait about a minute for the browser to open.

### Health Banners

Workshop monitors your connection in the background. If something needs attention, a banner appears at the top:

| Banner | What it means | What to do |
|--------|--------------|------------|
| **Network unreachable** | VPN disconnected | Connect GlobalProtect |
| **Session expired** | Azure sign-in timed out | Click "Sign in" to refresh |
| **Session expiring soon** | Token expires in < 30 minutes | Click "Refresh" to extend |
| **Low disk space** | Container storage nearly full | Contact AI CoE team |

### Dashboard

The dashboard shows system health and diagnostics. Access it by:
- Clicking the **grid icon** (top-right of Workshop), or
- Going to [http://localhost:3000?dashboard](http://localhost:3000?dashboard)

The dashboard shows:
- AI provider status with token expiry countdown
- Docker status
- Quick links to Web Terminal, VS Code, and Workshop

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

### Self-Service Tools

These are .bat files in your CCDW folder (usually `Documents\CCDW`):

| File | What it does |
|------|-------------|
| `help-claude.bat` | Generates a diagnostic report on your Desktop. **Send this file when asking for help.** It collects system info, logs, and health checks. Secrets are automatically removed. |
| `reset-claude.bat` | Resets everything to a clean state. Removes container data but **keeps your project files**. Use this if something is badly broken and you want to start fresh. |

---

## Troubleshooting

### "Something is not working"

Type `doctor` in the terminal. It checks everything and tells you exactly what's wrong and how to fix it.

If you need help, **double-click help-claude.bat** in your CCDW folder. It creates a file called `claude-diagnostic.txt` on your Desktop. Send this file to the AI CoE team -- it contains everything they need to help you.

### Setup says "restart your computer"

This is normal during first-time install. You may need to restart up to 2 times:

1. After WSL2 installs
2. After Rancher Desktop installs

Setup resumes automatically after restart. If it doesn't, just double-click setup-claude.bat again -- it picks up where it left off.

### VPN not connected

If you see "VPN is not connected" or "Network unreachable":

1. Look for the **GlobalProtect** icon in the system tray (bottom-right, near the clock)
2. Click it and make sure it says "Connected"
3. If you don't see it, search for "GlobalProtect" in the Start menu and open it
4. After connecting, press any key to continue (during setup) or wait 60 seconds (during use)

### Can't reach AI service

If you see "Can't reach the AI service" but your internet is working, connect to the Sleep Number VPN on your Windows machine, then try again.

### Session expired

Your Azure sign-in expires periodically. When you see "Session expired" or "Token expired":

1. Workshop shows a banner at the top -- click **"Sign in"**
2. Or go to the dashboard ([http://localhost:3000?dashboard](http://localhost:3000?dashboard)) and follow the sign-in instructions
3. Or open the web terminal and type `login`

### Container won't start

Make sure Rancher Desktop is running (check for the icon in your system tray). If it's not running:

1. **Double-click the "Claude Code" shortcut** on your desktop -- it starts Rancher Desktop automatically
2. Wait about 1-2 minutes for the icon to stop spinning
3. Your browser will open when it's ready

If the shortcut doesn't work:

1. Open the Start menu
2. Search for "Rancher Desktop"
3. Click to open it
4. Wait for the icon to stop spinning (1-2 minutes)
5. Then double-click the "Claude Code" shortcut again

### install.bat can't find Docker

1. Make sure Rancher Desktop is running (system tray icon should be present)
2. Make sure Rancher Desktop was installed under **your** Windows account, not the SSMITH admin account
3. If it was installed under the wrong account, uninstall it, then double-click `setup-claude.bat` -- it will reinstall under your account

### Reset everything

If nothing else works, you can start completely fresh:

1. Open your CCDW folder (usually `Documents\CCDW`)
2. Double-click **reset-claude.bat**
3. It removes all container data but keeps your project files
4. Then double-click **setup-claude.bat** to set up again
