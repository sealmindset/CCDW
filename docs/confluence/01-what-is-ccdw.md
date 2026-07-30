# What Is CCDW?

**CCDW** stands for **Claude Code Docker Workspace**. It is a ready-to-run
workspace that puts Anthropic's Claude Code — an AI assistant that can actually
read, write, and run things on your computer — behind a set of simple web pages
you open in your browser.

You do not install Claude Code. You do not install Node.js, Python, or a Linux
environment. You run one installer, and you get five web pages at addresses like
`http://localhost:3000`.

> **Already using the Claude app, or heard of Claude Code?** They are related but
> different products, and which one you want depends on what you are trying to
> do. See **Claude app vs. Claude Code vs. CCDW** further down this page.

---

## The one-paragraph version

CCDW gives you an AI teammate that can see your files and do real work with them.
You describe what you want in plain English — "build me a page that tracks
returns by region", "read these three spreadsheets and tell me what changed",
"fix the typo on the login screen" — and it does the work, shows you the result,
and lets you ask for changes. Everything runs on your own machine.

---

## Why this exists

Claude Code is a powerful tool, but historically it has been a *developer* tool.
Using it meant installing a runtime, configuring a terminal, managing API
credentials, and knowing command-line syntax. That is a real wall, and most
people who could benefit from the tool never get past it.

CCDW removes the wall in three ways:

**It is packaged.** Everything Claude Code needs is bundled into a single
container image. If you can install a normal desktop application, you can install
CCDW. There is nothing to configure afterward.

**It is visual.** The most common tasks have a web page instead of a command.
Building an app has a page. Chatting has a page. Browsing files has a page. The
terminal is still there for people who want it, but it is now optional.

**It is connected to your real work.** CCDW can see your `Documents`, `Desktop`,
`Downloads`, and any external drives. It is not a sandbox with toy files. When it
edits a file, that is your actual file, and you will see the change in Finder or
File Explorer.

---

## What is "vibe coding," and how does CCDW help?

**Vibe coding** is building software by describing what you want rather than by
writing the code yourself. You bring the intent, the taste, and the judgment
about whether the result is right. The AI brings the syntax.

It works because the hard part of most small business tools was never the code —
it was the translation. You knew exactly what you needed. You just could not say
it in a language a computer understood. Vibe coding removes the translation step.

CCDW is built for this way of working:

| What you need to vibe code | How CCDW provides it |
|---|---|
| Somewhere to describe your idea | **Workshop** — a text box that turns a description into a working app |
| To see the result immediately | Workshop runs your app and gives you a link to open it |
| To ask for changes in plain English | Every page keeps a conversation; you say "make the button blue" and it does |
| To not lose your work | Projects and conversations are saved automatically and survive restarts |
| To not break anything important | Your work lives in ordinary folders you can copy, back up, or delete |
| To ask questions without committing | **Claude Chat** — talk about your files without starting a project |

**An honest note on expectations.** Vibe coding is very good at internal tools,
prototypes, one-off analyses, dashboards, scripts, and "I just need this one
thing" software. It is genuinely useful and often surprisingly fast. It is not a
replacement for engineering review on anything that handles customer data,
money, or production systems. Build freely; loop in an engineer before anything
goes live to people outside your team.

---

## What you get

Five pages, all in your browser:

| Page | Address | One-line purpose |
|---|---|---|
| **Dashboard** | `http://localhost:3000` | Home base. Health check, links to everything, list of apps you have built. |
| **Workshop** | `http://localhost:9200` | Build an app by describing it. No terminal. |
| **Claude Chat** | `http://localhost:3002` | Chat with Claude about any folder on your computer. |
| **VS Code** | `http://localhost:8080` | A real code editor in the browser, for when you want to look at files yourself. |
| **Terminal** | `http://localhost:7681` | The classic Claude Code command line, for power users. |

They are all the same underlying assistant, with the same access to your files.
They differ in how much of the machinery you see.

**Two things come switched on that are easy to miss:**

**The make-it framework is built in.** CCDW ships with a suite of skills that
handle building, testing, securing, and shipping software — you do not install
or enable them. Workshop is a front end for two of them. They keep themselves
updated. See **The make-it Framework**.

**It remembers you.** Provider, model, standing instructions, conversation
history, and project state all persist across restarts, reboots, and updates.
Set up once; carry on where you stopped. See **What CCDW Remembers**.

---

## Claude app vs. Claude Code vs. CCDW

People often hear "Claude" and picture three different things. They are three
different products, and the confusion is understandable — the same Claude is
underneath all of them. What differs is **where it runs, what it can touch, and
how much setup it takes.**

> **Before you choose:** which of these your organization permits, and for what
> kind of information, is a policy question — not a technical one. Check with
> your IT or security team before adopting any of them for work. This page
> describes what each one *can* do, not what you are *allowed* to do.

### The short version

- **Claude app** — a conversation. You bring text and attachments to Claude.
- **Claude Code** — a collaborator at a command line. Claude works inside your
  folders, on your machine, and you drive it by typing.
- **CCDW** — Claude Code with the setup already done and web pages on top.

### Side by side

| | **Claude app** (claude.ai — web, desktop, mobile) | **Claude Code** (installed yourself) | **CCDW** |
|---|---|---|---|
| **What it is** | A chat product | A developer tool for the command line | A packaged workspace containing Claude Code |
| **Where you use it** | Browser, desktop app, or phone | Your terminal | Five browser pages on your own machine |
| **Setup effort** | Sign in. That is all. | Install a runtime, configure credentials, learn the commands | Run one installer; it handles everything, including the container software |
| **Can it see your files?** | Only what you attach or upload, unless you deliberately configure a connector | Yes — whatever folder you point it at | Yes — `Documents`, `Desktop`, `Downloads`, and external drives. Nothing else. |
| **Can it change your files?** | No, in normal use | Yes | Yes |
| **Can it run programs and build apps?** | It can write code for you to copy out; it does not run on your machine | Yes | Yes, and it runs the finished app for you |
| **Needs a terminal?** | No | Yes | No — the terminal is there, but optional |
| **Works offline / off-VPN?** | Needs internet | Needs internet | Needs internet, plus corporate VPN if your provider is Azure AI Foundry or AWS Bedrock |
| **Where requests go** | To Anthropic | To whichever provider you configured | To whichever provider **your organization** configured |
| **Best at** | Thinking, writing, explaining, one-off questions | Deep work in a codebase, by someone comfortable at a command line | Getting non-developers doing real work on real files, fast |

### Pros and cons

**Claude app**

- **Pros.** Nothing to install. Works on your phone. Fastest possible start.
  Excellent for writing, analysis, explanation, and brainstorming. Nothing on
  your machine can be changed by accident.
- **Cons.** It cannot reach into your folders, so anything file-based becomes
  upload → get an answer → copy the result back by hand. It cannot run what it
  writes, so you never see the thing actually working. That round-trip is fine
  for one file and painful for twenty.

**Claude Code**

- **Pros.** The most capable of the three. Full, unmediated access. No layer
  between you and the tool. This is what professional developers use.
- **Cons.** You have to install and maintain it, configure credentials yourself,
  and be comfortable typing commands. For someone who has never used a terminal,
  the setup is a real wall — which is exactly the wall CCDW exists to remove.

**CCDW**

- **Pros.** One installer, no configuration. Claude works on your real files.
  It builds and runs apps, not just code samples. Credentials and provider
  settings come pre-wired by whoever set it up. The web pages mean you never
  need a terminal, and the terminal is still there when you want it.
- **Cons.** A heavier install — several gigabytes, and it runs container
  software in the background. It only reaches four folder locations by design.
  Only on the computer you installed it on: no phone, no browser tab from a
  different machine. And it can change your real files, which is the entire
  point and also the risk — see the caution below.

### Which one, by scenario

| Your situation | Use this |
|---|---|
| "Help me write this email / summarize this document I'm pasting in" | **Claude app** |
| "I'm on my phone and had an idea" | **Claude app** |
| "Explain this concept to me before a meeting" | **Claude app** |
| "Read these twelve spreadsheets in my Documents folder and tell me what changed" | **CCDW** (Claude Chat) |
| "Build me an internal tool that does X" | **CCDW** (Workshop) |
| "Rename and reorganize 300 files according to this rule" | **CCDW** (Claude Chat) |
| "I want to try building software without learning to code" | **CCDW** |
| "I'm a professional developer working in a large repository" | **Claude Code**, or **CCDW**'s Terminal page if you prefer the packaging |
| "I need this on a locked-down machine where I cannot install anything" | **Claude app** |
| "Anything involving customer data, payment records, or regulated information" | **Ask your security team first** — before any of the three |

**The dividing line is files.** If the work is *about* text you can paste into a
box, the Claude app is faster and simpler and you should use it. The moment the
work involves your actual files — many of them, or repeatedly, or changing them
rather than just reading them — CCDW earns its heavier install. Claude Code sits
at the same place as CCDW on that line; it simply asks more of you to get there.

### Where your information goes

This is the difference most worth understanding, and it is structural rather
than a matter of degree:

- **The Claude app** sends your conversation to Anthropic.
- **CCDW and Claude Code** send your requests to **whichever AI provider was
  configured** — commonly your organization's own Azure AI Foundry or AWS
  Bedrock account, and in that case the request goes to your company's cloud
  rather than to Anthropic. It can also be configured to talk to Anthropic
  directly. Your Dashboard shows which one you are on.

In all three, your files stay on your machine — what travels is the *content of
your request*, which may include the parts of files Claude needed to read to
answer you.

> **What that does and does not tell you.** Knowing where a request is routed is
> not the same as knowing what your organization permits, how long anything is
> retained, or which categories of data are approved. Those are policy questions
> with real answers — your security team has them. Ask before putting sensitive
> information into any of these tools.

### One caution unique to CCDW and Claude Code

The Claude app cannot damage anything on your computer, because it cannot reach
your computer. CCDW and Claude Code can — that access is what makes them useful,
and it cuts both ways. Both can overwrite or delete real files in the folders
they can reach, and they will do so confidently even when they have
misunderstood you.

Two habits make this a non-issue: keep work you care about backed up, and point
a conversation at the narrowest folder that contains what you need rather than
at everything.

---

## Who it is for

**You do not need to be a developer.** The Dashboard, Workshop, and Claude Chat
pages are designed for people who have never opened a terminal. If you are an
analyst, a product manager, a designer, a marketer, or an operations lead with an
idea for a tool, those three pages are your whole world.

**Developers get the full thing.** VS Code and the Terminal give you everything
Claude Code offers natively, plus the ability to run and test the apps you build
as real containers on your machine.

---

## When to use CCDW

**Good fits:**

- You have a repetitive manual task and suspect a small tool would kill it.
- You have files — spreadsheets, documents, exports — and questions about them.
- You want to prototype an idea to show someone, before asking for engineering time.
- You need to understand a codebase or a folder of documents you did not write.
- You want to learn how software gets built by watching it happen and asking why.

**Poor fits:**

- Anything that must be production-grade on day one without review.
- Work involving customer PII, payment data, or regulated records — check with
  your security team about what is allowed to pass through an AI provider first.
- Tasks where you cannot tell whether the answer is right. AI is confident even
  when it is wrong; you need enough context to catch mistakes.

---

## How it actually works, briefly

CCDW runs as a **container** — a self-contained, isolated copy of a small Linux
computer running on top of your Mac or Windows machine. Everything CCDW needs
lives inside it, which is why installation is one step and why removing it is
clean.

The container is given permission to see specific folders on your real machine:

- `Documents`
- `Desktop`
- `Downloads`
- External drives (macOS `/Volumes`)

Anything outside those folders is invisible to it.

The AI itself does not run on your machine — that would require enormous
hardware. Your requests are sent to an AI provider (your organization's Azure AI
Foundry, AWS Bedrock, or Anthropic directly — see **Getting Started**), and the
answers come back. The *work* happens locally; the *thinking* happens at the
provider.

---

## Related pages

- **Getting Started** — install it and make your first request. Step 2 covers the
  AI provider choice referenced above.
- **Which Page Should I Use?** — once you have settled on CCDW, a decision table
  for picking the right page inside it.
- **Claude Chat** — the page most of the file-based scenarios above point to.
- **The make-it Framework** — the built-in skills behind Workshop.
- **What CCDW Remembers** — what persists, and the one thing that does not.
- **Glossary** — plain-English definitions for every technical term used here.
