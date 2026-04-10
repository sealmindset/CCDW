# Vibe Code Quick Start -- Docker Edition (Windows)

This guide walks you through everything you need to go from zero to building your first app with Claude Code -- using Docker. No WSL, no Node.js, no Linux setup. Just Docker and a browser.

> **Time estimate:** First-time setup takes about 15-20 minutes of hands-on work. Some access requests require approval and may take 1-2 business days, so start early.

> **Why Docker Edition?** The standard setup requires installing Node.js, Azure CLI, GitHub CLI, and other tools directly on your Windows machine. The Docker Edition packages everything into a single container -- you just install Rancher Desktop and double-click a file. Everything else happens in your browser.

Here is what we need to do to get started.

- [Prerequisites](#prerequisites) -- Access requests (start these first, some need approval)
- [Install Rancher Desktop](#install-rancher-desktop) -- The only thing you install on your machine
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

Your work computer normally prevents you from installing new software. This request gives you temporary permission to install Rancher Desktop. The permission expires automatically, so you'll need to submit a new request when it runs out.

<details>
<summary>Request Local Admin</summary>

- Navigate to [Service Portal](https://sleepnumber.service-now.com/sp)
- Search for `Local Admin Rights`
- Complete the form:
  - Select your system you need local admin
  - Enter the justification as "Need to install Rancher Desktop for local development"
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

## Install Rancher Desktop

This is the **only software you need to install** on your Windows machine. Everything else runs inside the container.

Rancher Desktop is free, open-source, and provides the Docker engine that powers Claude Code Docker.

1. Download Rancher Desktop from https://rancherdesktop.io/
2. Run the installer (you'll need Local Admin privileges -- see prerequisite #2)
3. When prompted, select **dockerd (moby)** as the container engine
4. Wait for Rancher Desktop to finish starting up (the icon in your system tray will stop spinning)

> **Tip:** Rancher Desktop needs to be running whenever you want to use Claude Code Docker. It starts automatically with Windows, so you usually don't need to think about it.

---

## Launch Claude Code Docker

Once Rancher Desktop is running:

1. Download `install.bat` from your team's shared location (or the CCDW repository)
2. **Double-click `install.bat`**

That's it. The installer will:
- Check that Rancher Desktop is running
- Download the latest Claude Code Docker image
- Create your projects folder (`Documents\GitHub`)
- Start the container
- Create a **"Claude Code"** shortcut on your desktop
- Open the dashboard in your browser

> **Next time:** Just double-click the **"Claude Code"** shortcut on your desktop. If there's an update, it downloads automatically.

---

## First-Time Setup

When the dashboard opens in your browser, you'll see three options. Click **Web Terminal** to open the terminal.

On your first visit, you'll see a welcome walkthrough. Follow these steps:

### Step 1: Log in to Azure

This connects Claude Code to the AI service. Type:

```
az login --use-device-code
```

You'll see a message like:

```
To sign in, use a web browser to open the page https://microsoft.com/devicelogin
and enter the code XXXXXXXXX to authenticate.
```

1. Open the URL in a new browser tab on your Windows machine
2. Enter the code shown in the terminal
3. Sign in with your Sleep Number account
4. Come back to the terminal -- it will confirm you're logged in

> **Important:** Make sure you're connected to the Sleep Number VPN before doing this.

### Step 2: Log in to GitHub

This lets Claude Code save and share your work. Type:

```
gh auth login
```

When prompted:
1. Select **GitHub.com**
2. Select **HTTPS**
3. Select **Login with a web browser**
4. Copy the one-time code shown
5. Open the URL in your browser, paste the code, and authorize

> You only need to do Steps 1 and 2 once. Your login is saved and survives container restarts.

### Step 3: You're ready!

The terminal will show your connection status:

```
  AI Provider:   Azure AI Foundry
  Azure Token:   Valid (55 min remaining)
  Docker:        Connected
  Skills:        v1.6.0
```

If anything shows red or yellow, type `doctor` to run the troubleshooter.

---

## Vibe Coding

You're ready to build your first app. No coding experience needed -- just describe what you want in plain English, and Claude does the rest.

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
| `doctor` | Check if everything is working (troubleshooter) |
| `backup` | Save all your settings to a file |
| `restore <file>` | Restore settings from a backup |

---

## Troubleshooting

### "Something is not working"

Type `doctor` in the terminal. It checks everything and tells you exactly what's wrong and how to fix it.

### Azure token expired

You'll see a yellow or red warning in the terminal. Just type:

```
az login --use-device-code
```

Follow the same steps as the first-time setup. Tokens typically last about 1 hour and need periodic refresh.

### Can't reach AI service (VPN)

If you see "Can't reach the AI service" but your internet is working, connect to the Sleep Number VPN on your Windows machine, then try again.

### Container won't start

Make sure Rancher Desktop is running (check for the icon in your system tray). If it's not running, start it and wait for it to finish loading, then double-click `install.bat` again.

### Need to start fresh

Double-click `install.bat` again. It automatically stops the old container and starts a fresh one. Your projects in `Documents\GitHub` are preserved.

---

## What's Different from the Standard Setup?

| | Standard Setup | Docker Edition |
|---|---|---|
| **Install on Windows** | Node.js, Azure CLI, GitHub CLI, Claude Code, /make-it skills | Rancher Desktop only |
| **Setup time** | 30-60 minutes | 15-20 minutes |
| **Terminal** | Windows PowerShell | Web browser |
| **Updates** | Manual (`npm update`, skill updates) | Automatic (every launch) |
| **Troubleshooting** | Check each tool individually | Type `doctor` |

---

## Reference

- Claude Code Initial Setup Guide for Azure AI Foundry
- Enterprise AI Application Architecture Standards
- /make-it & /ship-it skill documentation

> Once you get all of the prerequisites -- *Done!* You're set up and ready to build. If you run into issues, reach out to the AI CoE team. Even present your app at the next company's invitational AI Hackathon to showcase what you built!
