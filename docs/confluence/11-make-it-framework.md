# The make-it Framework

Everything CCDW does when it *builds* something is powered by a set of skills
called the **make-it framework**. It is not an add-on you install, a plugin you
enable, or a setting you turn on. **It is baked into CCDW by design** and is
already running the moment you open the Dashboard.

Most people never need to know it exists. This page is for when you want to
know what is happening under the hood — or when you want to reach the parts of
it that the buttons do not expose.

---

## What it is

The make-it framework is a family of **skills**. A skill is a long, detailed
set of instructions that tells Claude how to do one job properly, every time —
in what order, with what checks, and what to refuse to skip.

Each skill has a name that starts with a slash: `/make-it`, `/try-it`,
`/wrap-it`. Where CCDW gives you a button, the button is running one of these
for you.

An analogy that holds up: **Claude on its own is a very capable generalist.
make-it is the set of standard operating procedures that turns the generalist
into a specialist who does not forget steps.** Left to itself, an AI asked to
"build me an app" will produce something plausible. Asked through `/make-it`,
it works through ideation, then design, then fourteen numbered build steps,
then verification — and it will not hand you an app with the login missing,
because a step in the procedure says otherwise.

---

## It is built in — here is what that means on each page

The framework lives inside the container image, at `~/.claude/commands/`. Every
page in CCDW is talking to the same Claude Code installation, so every page has
it available. What differs is **how much of it is automatic**.

| Page | How make-it shows up |
|---|---|
| **Workshop** | Fully automatic and invisible. You never type a command. |
| **Terminal** | Fully available and manual. Type `/make-it` and press Enter. |
| **VS Code** | Same as the Terminal — VS Code opens with Claude Code already running in a panel at the bottom, so slash commands work there. |
| **Dashboard** | Not a place you run skills, but it reports on them — the **/make-it Efficiency** card shows the token and cost savings from prompt caching during builds. |
| **Claude Chat** | Not the place for these. Chat is for conversation about files; use Workshop or the Terminal for skills. |

### Workshop *is* `/make-it`

This is the part worth internalizing. When you click **+ New Project** in
Workshop and type a description, Workshop starts `/make-it` for you and drives
it to completion. When you open a project that already has code in it, Workshop
starts `/resume-it` instead. It chooses between them by looking for traces of a
previous build — a `.make-it-state.md` file, an `app-context.json`, a
`CHANGELOG.md`.

Workshop also explicitly instructs Claude never to tell you to "run
`/make-it`" or "type a command," because in Workshop you cannot. The GUI is the
skill, wearing a friendlier face.

So: **you have been using make-it since your first Workshop project, whether or
not you knew the name.**

---

## The skills

Fourteen are installed. You will only ever need a handful.

### The ones a non-developer would actually use

| Skill | What it does |
|---|---|
| `/make-it` | Build a brand-new app from an idea, through plain-English Q&A. This is what Workshop runs. |
| `/resume-it` | Come back to an app you already built — add a feature, fix a bug, test it. Workshop runs this automatically for existing projects. |
| `/try-it` | Start your app with fake stand-in services and test it automatically, so you can click around without setting anything up. |
| `/wrap-it` | End your session cleanly. Saves progress, updates your to-do list, shuts the app down. |
| `/clear-it` | Mid-session checkpoint. Writes everything important to a `handoff.md` file so the conversation can be reset without losing the thread. |

### The ones aimed at developers and operations

| Skill | What it does |
|---|---|
| `/retrofit-it` | Add production foundations — login, permissions, Docker, security — to an app that already exists. |
| `/nemo-it` | Security scan. Checks the app against the OWASP Testing Guide and AI-safety tests, and writes a report. Reports only; changes nothing. |
| `/fix-it` | Fixes what `/nemo-it` found, then re-scans to confirm. |
| `/debug-it` | Structured debugging that insists on finding the root cause before touching anything. |
| `/git-it` | Day-to-day version control done correctly — commits, branches, cleanup. |
| `/argo-it` | Deploy to Kubernetes, generating the manifests and pipeline. |
| `/demo-it` | Create and expire branded demo environments for prospects. |
| `/dispatch-it` | Work several unrelated problems in parallel, each in its own isolated context. |
| `/subagent-it` | Execute an approved multi-step plan task by task, with a review after each one. |

> **A note on `/ship-it`.** Some documentation refers to a `/ship-it` skill for
> deployment. It is not among the skills installed in the current CCDW image.
> If you need to deploy, use `/argo-it`, or talk to your platform team.

---

## What `/make-it` actually does when it builds

Useful to know, because it explains why a Workshop build takes as long as it
does. It is not one request to an AI — it is a sequenced procedure.

**Five phases:**

1. **Preflight** — checks the machine has what it needs.
2. **Ideation** — asks you plain-language questions about what you want. No
   code, no framework choices, no jargon.
3. **Design** — makes roughly thirteen architectural decisions on your behalf,
   derived from your answers: how login works, how permissions work, what the
   technology stack is, whether it needs multi-tenancy, how AI features are
   handled if any.
4. **Build** — runs fourteen numbered generation steps in order: project
   structure, UI, stack, architecture, infrastructure, Docker, login,
   permissions, AI wiring, safety controls, security hardening, mock services,
   sample data, standard UI components.
5. **Verify and hand off** — confirms the thing runs, then gives it to you.

**Security is not optional in it.** Every project gets a mandatory baseline:
no secrets committed to files, no hardcoded configuration, input validated at
the boundaries, sensitive data masked in output, current dependencies. Web apps
get more on top — proper OIDC login rather than homemade passwords,
database-driven permissions, secure cookies, security headers.

This is the real reason to prefer Workshop over asking a general-purpose AI to
"write me an app." The procedure carries the standards with it.

---

## Using the skills yourself, from the Terminal

If you want to run one directly, open the **Terminal** page at
`http://localhost:7681`, move into the folder you care about, and type the
command:

```bash
cd Documents/my-project
```

```
/try-it
```

Answer the questions it asks. That is the whole interaction.

**When it is worth doing this instead of using Workshop:**

- You want a skill Workshop does not have a button for — `/nemo-it`,
  `/git-it`, `/debug-it`.
- You are working in a project that was not created by Workshop.
- You want to watch every step as it happens.

---

## Keeping itself current

The skills update themselves. Every time the container starts, CCDW checks
whether a newer version of the framework has been published and installs it if
so. You do not maintain this and cannot fall behind.

If the machine is offline at startup it skips the check and carries on with the
version already installed.

Your own customizations are never overwritten by an update — see
**What CCDW Remembers**.

---

## Common questions

**Do I have to learn these commands?**
No. Workshop covers the two that matter for building — `/make-it` and
`/resume-it` — with no typing at all.

**Is this Anthropic's, or ours?**
The make-it framework is a separate open project that CCDW bundles. Claude Code
itself is Anthropic's. CCDW packages both together so you get them wired up.

**Can I add my own skills?**
Yes — files placed in `~/.claude/commands/` inside the container become
available as slash commands, and they survive restarts and updates. That is a
developer-level customization.

**Why did my Workshop build take twenty minutes?**
Because it ran fourteen build steps and verified the result. Compare it to the
alternative — the same work as a ticket in an engineering backlog.

**Where do I read about a specific skill in depth?**
Each skill has its own detailed page maintained with the framework itself, in
`~/.claude/make-it/confluence-docs/` inside the container.

---

## Related pages

- **Workshop** — the button-driven front end for `/make-it` and `/resume-it`.
- **Terminal** — where you run any of the fourteen by hand.
- **What CCDW Remembers** — what survives a restart, including skills and settings.
- **Glossary** — plain-English definitions for the terms above.
