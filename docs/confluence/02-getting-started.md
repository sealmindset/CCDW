# Getting Started

This page takes you from nothing installed to your first working request. Budget
about 20 minutes, most of which is waiting for downloads.

---

## Before you begin

**You need:**

- A Mac or a Windows PC.
- Free disk space for the download. The installer's own check warns below 1 GB
  and recommends at least 4 GB; leaving more headroom than that is wise, since
  the apps you build take space too.
- Administrator rights on the machine. On a managed corporate laptop you may need
  to request these from IT.
- If your organization uses Azure AI Foundry or AWS Bedrock: be connected to the
  corporate VPN.

**You do not need:** Docker, Node.js, Python, WSL, a terminal, or any prior
setup. The installer handles all of it.

---

## Step 1 — Run the installer

The installer downloads and configures everything, including the container
software itself (Rancher Desktop). Re-running it later is how you update.

### macOS

Open the **Terminal** app (press `Cmd + Space`, type "Terminal", press Enter),
then paste this line and press Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/SleepNumberInc/CCDW/main/bootstrap.sh | bash
```

### Windows

Open **PowerShell as Administrator** (press the Windows key, type "PowerShell",
right-click it, choose "Run as administrator"), then run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
winget install --id GitHub.cli --source winget
wsl --install
gh auth login
iex (gh api repos/SleepNumberInc/CCDW/contents/bootstrap.ps1 -H "Accept: application/vnd.github.raw")
```

> **Windows note:** `wsl --install` may ask you to restart. That is normal.
> Restart, then re-run the last line.

### What you will see

The installer prints its progress as it goes. It will:

1. Install or upgrade Rancher Desktop (the container software).
2. Download the CCDW image (this is the long part — several GB).
3. Ask you to pick an AI provider (see Step 2).
4. Start the container.
5. Put a **Claude Code** shortcut on your desktop.

Everything it prints is also saved to `~/Desktop/claude-setup.log`. If something
goes wrong, that file is what to share when you ask for help.

---

## Step 2 — Choose your AI provider

CCDW needs to talk to Claude, and there are three ways to do that. The installer
shows a menu; pick whichever your organization uses.

| Option | Choose this if | What you will need |
|---|---|---|
| **Azure AI Foundry** | Your company hosts Claude inside its own Azure account. Most common for corporate use. | Corporate VPN connected, and an Azure account with Foundry access |
| **AWS Bedrock** | Your company hosts Claude inside its own AWS account. | AWS SSO access to a Bedrock-enabled account |
| **Anthropic API key** | You are using a personal or team key directly from Anthropic. | An API key that starts with `sk-ant-` |

**If you do not know which one to pick, ask whoever asked you to install CCDW.**
This is an organizational decision, not a personal preference — it determines
where your prompts are sent and who is billed.

You can also skip the menu by naming the provider up front:

```bash
# macOS
./install.command --ai=foundry
./install.command --ai=bedrock
./install.command --ai=anthropic
```

```powershell
# Windows
install.bat --ai=foundry
install.bat --ai=bedrock
install.bat --ai=anthropic
```

---

## Step 3 — Sign in

**If you chose Anthropic API key**, you are already done — skip to Step 4.

**If you chose Azure AI Foundry or AWS Bedrock**, you sign in with your normal
work credentials. There are two ways:

### The easy way — from the Dashboard

Open `http://localhost:3000`. If sign-in is needed, a banner appears at the top
with a short code (like `76FC-280C`) and an **Open Sign-in Page** button. Click
the button, enter the code, and approve with your usual work login. The banner
disappears on its own once you are in.

### The manual way — from the Terminal page

Open `http://localhost:7681` and type:

```
login
```

Follow the prompts. For Azure this runs `az login --use-device-code`; for AWS it
runs `aws sso login`.

> **Sign-ins expire.** Typically after 8–12 hours. When that happens, pages will
> tell you the provider is not configured, or the token has expired. Just sign in
> again — type `login` in the Terminal page. Nothing is lost.

---

## Step 4 — Open the Dashboard

Double-click the **Claude Code** shortcut on your desktop, or open a browser and
go to:

```
http://localhost:3000
```

You will see a startup screen for a few seconds while services come up, then the
Dashboard. Green dots mean healthy.

If you get "this site can't be reached," the container is not running yet. Give
it another 30 seconds and refresh. If it still fails, see **Troubleshooting**.

---

## Step 5 — Your first request

Two good first requests, depending on what you want to feel out.

### Option A — Ask a question about your own files (2 minutes)

1. Click **Claude Chat** in the top navigation.
2. Click the folder chip next to the model dropdown (it says something like
   `Documents`).
3. Pick a folder that has some files in it. Click **Use this folder**.
4. Type: `What's in this folder? Summarize what you find.`
5. Press Enter.

You will see Claude work — small grey chips appear saying things like
"Ran `ls`" or "Read report.xlsx" — and then a plain-English answer.

**Why this is a good first test:** it proves the connection works, it proves
Claude can see your real files, and it costs almost nothing.

### Option B — Build something (10–20 minutes)

1. Click **Workshop** in the top navigation.
2. Click **+ New Project**.
3. Give it a short name, like `expense-tracker`.
4. Describe what you want in plain English. Be specific about what it should
   *do*, not how it should be built. For example:

   > A single-page tool where I paste in a list of expenses, one per line, in the
   > format "date, description, amount". It shows them in a sortable table, a
   > running total, and a bar chart of spending by month.

5. Watch it build. This takes a while — it is writing real code.
6. When it says **Demo Ready**, click **See your app**.

---

## Where your work is saved

| What | Where | Survives a restart? |
|---|---|---|
| Projects you build in Workshop | Your `Documents` folder | Yes |
| Chat conversations | Inside the container | Yes |
| Files Claude edits | Wherever they already were | Yes — they are your real files |
| Sign-in sessions | Inside the container | Yes, until they expire |

Nothing lives only in the browser. Closing a tab loses nothing.

---

## Updating

Re-run the installer. It pulls the newest version and restarts. Your projects,
conversations, and settings are untouched.

The desktop shortcut also checks for updates each time you launch, so in normal
use you stay current without doing anything.

---

## Uninstalling

Stop and remove the container, then delete the folder. Your projects stay in
`Documents` — removing CCDW does not delete your work.

---

## Related pages

- **Which Page Should I Use?** — now that it is running, where do you go?
- **Troubleshooting** — if any step above did not work.
- **Glossary** — for any word on this page you had to skip past.
