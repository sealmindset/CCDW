# Glossary

Plain-English definitions for every technical term used in the CCDW
documentation. No prior knowledge assumed.

---

## The essentials

**CCDW**
Claude Code Docker Workspace. The whole thing — the container, the five web
pages, and the installer.

**Claude**
Anthropic's AI assistant. The intelligence behind everything in CCDW.

**Claude Code**
The version of Claude that can actually *do* things on a computer — read files,
write files, run programs — rather than only talk. CCDW is a friendly wrapper
around it.

**Container**
A self-contained, isolated mini-computer running on top of your real one.
Everything CCDW needs lives inside it. It is why installation is one step and
removal is clean. Think of it as a sealed box with a few windows cut into it
looking at specific folders.

**Docker / Rancher Desktop**
The software that runs containers. Rancher Desktop is the specific one CCDW
installs for you. You will rarely interact with it directly.

**Image**
The downloadable blueprint a container is created from. "Pulling the latest
image" means downloading the newest version of CCDW.

**Localhost**
Your own computer, as seen from a web browser. `http://localhost:3000` means
"port 3000 on this machine." Nobody else can reach it.

**Port**
A numbered door on your computer. CCDW uses 3000 (Dashboard), 3002 (Claude Chat),
7681 (Terminal), 8080 (VS Code), and 9200 (Workshop). If another program has
already taken one, CCDW will say so.

---

## Getting set up

**AI provider**
The service that actually runs Claude and answers your requests. CCDW supports
three: **Azure AI Foundry**, **AWS Bedrock**, and **Anthropic** directly. Which
one you use is an organizational decision.

**Azure AI Foundry**
Microsoft's platform for hosting AI models inside a company's own Azure account.
Common in corporate environments because usage stays within the company's cloud.

**AWS Bedrock**
Amazon's equivalent — Claude hosted inside a company's own AWS account.

**API key**
A long secret string that identifies you to an AI service. Anthropic's start with
`sk-ant-`. Treat one like a password.

**SSO (Single Sign-On)**
Signing in with your normal work credentials instead of a separate password.

**Token**
A temporary pass issued after you sign in, typically valid 8–12 hours. When it
expires you sign in again. "Token has expired" is the most common CCDW error and
the fix is always the same.

**Device code**
The short code (like `76FC-280C`) shown during sign-in. You enter it on a
Microsoft or Amazon sign-in page to prove the request came from you.

**VPN**
The corporate network connection. If your organization uses Azure AI Foundry or
AWS Bedrock, CCDW cannot reach them without it.

**Installer / bootstrap**
The one-line command that sets everything up. Re-running it is how you update.

---

## Using it

**Prompt**
What you type. Your question, request, or description.

**Model**
Which version of Claude is answering. Bigger models are more capable and slower.
The default is a sensible choice.

**System prompt**
Standing instructions applied to every conversation — "always answer in British
English," "assume I am not a developer." Set via the gear icon in Claude Chat.

**Tool / tool call**
When Claude does something rather than just says something — reads a file, runs a
command, searches. In Claude Chat these appear as small grey activity chips.

**Activity chip**
The one-line grey box in Claude Chat showing a piece of work: `Read report.md`,
`Ran ls`. Click it to expand and see the detail.

**Turn**
One exchange — your message plus Claude's complete response, including whatever
work it did along the way.

**Session**
An ongoing conversation with its own memory. Claude Chat conversations and
Terminal sessions are both sessions.

**Context**
Everything Claude can currently "see" — your messages so far, plus any files it
has read. Long conversations use more context and eventually get slower.

**Vibe coding**
Building software by describing what you want instead of writing the code
yourself. The core idea behind Workshop.

**Claude app**
Anthropic's chat product at claude.ai — browser, desktop, and phone. Related to
CCDW but separate: it is a conversation, not a workspace, and it cannot reach
the files on your computer unless you deliberately connect it.

**Skill**
A detailed, reusable procedure that tells Claude how to do one job properly
every time. CCDW ships fourteen of them.

**make-it framework**
The suite of skills built into CCDW that handles building, testing, securing,
and shipping software. Not optional and not installed separately — it is part
of the image. Workshop is a button-driven front end for two of its skills.

**`/make-it`, `/resume-it`**
The two skills Workshop runs. `/make-it` for a brand-new project,
`/resume-it` for one that already has code.

**CLAUDE.md**
A file of standing instructions Claude reads before every conversation. One
global, and optionally one per project folder. Survives restarts and updates.

**handoff.md**
A checkpoint file written by `/clear-it`, recording where you got to so a fresh
session can pick the thread back up.

---

## Files and folders

**Directory**
Another word for folder.

**Path**
A folder's full address, like `/home/coder/Documents/my-project`. Inside the
container, your `Documents` folder is called `/home/coder/Documents`.

**Mount**
A folder on your real computer that the container has been given permission to
see. CCDW mounts `Documents`, `Desktop`, `Downloads`, and external drives —
nothing else.

**Working directory / working folder**
The folder a conversation is currently pointed at. In Claude Chat this is the
folder chip at the top.

**Repository (repo)**
A folder tracked by version control, keeping a history of every change. Marked
with a small `git` badge in the Claude Chat folder picker.

**Git**
The software that does that tracking. Its main benefit for non-developers: if
something goes wrong, you can undo it.

**GitHub**
A website that stores repositories online, so teams can share them.

**Markdown**
A simple way of writing formatted text using plain characters — `**bold**`,
`# Heading`. These documentation files are written in it, and Claude Chat exports
in it.

---

## Building things

**Project**
In Workshop, one thing you are building. It has a name, a folder, and a change
history.

**Build**
The process of turning your description into working code.

**Demo Ready**
A Workshop status meaning the project has been built and can be opened.

**Deploy / ship**
Putting an app somewhere other people can reach it. Workshop apps run only on
your machine until someone deploys them — that is a conversation with your
platform team.

**App**
A running program. Apps you build appear in the **Your Apps** grid on the
Dashboard.

---

## The terminal

**Terminal / command line / CLI**
A text-only way of talking to a computer. You type a command, press Enter, read
the result.

**Command**
A single instruction, like `ls` (list files) or `cd` (change folder).

**Slash command**
A Claude Code instruction starting with `/`, like `/model` or `/clear`.

**Ctrl + C**
The universal "stop what you are doing" in a terminal.

**tmux**
The software that keeps your Terminal session alive after you close the browser.
You never interact with it directly.

**Shell / bash**
The program that interprets what you type in a terminal.

---

## Occasionally seen

**Sibling container**
An app you built running as its own container next to CCDW rather than inside it.
Why your apps keep running independently and get their own ports.

**Host bridge**
The small piece of CCDW that lets the container talk to your Mac for
copy/paste and "open in Finder."

**Volume**
Storage that belongs to the container and survives restarts. Your chat history,
settings, and standing instructions live in one — which is why CCDW remembers
you across restarts and updates.

**Log**
A running record of what a program did. `~/Desktop/claude-setup.log` is the
installer's.

**Doctor mode**
CCDW's built-in self-check: `--doctor`. Diagnoses without changing anything.

**Prompt caching**
An optimization that reuses parts of previous requests to cut cost and latency.
Automatic; nothing to configure.

---

## Related pages

- **What Is CCDW?** — the overview.
- **Getting Started** — installation.
- **Troubleshooting** — where several of these terms show up in error messages.
