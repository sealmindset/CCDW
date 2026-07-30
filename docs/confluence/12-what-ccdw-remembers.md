# What CCDW Remembers

**Short answer: set it up once, and it stays set up.**

Your provider, your model choice, your standing instructions, your conversation
history, your projects, your sign-ins, your skills — all of it survives closing
the browser, restarting the container, rebooting your machine, and updating to
a new version of CCDW.

The one thing that does *not* last is your sign-in token, and that is by
design. Everything else persists until you deliberately reset it.

---

## The rule of thumb

CCDW keeps three separate kinds of memory, in three places:

| Kind | Where it lives | Survives what |
|---|---|---|
| **Your settings and history** | A storage area belonging to the container | Restart, reboot, and update |
| **Your actual work** | Your real `Documents` folder | Everything — including removing CCDW entirely |
| **Your sign-in** | Borrowed from your Mac or PC | Restart — but expires on its own after 8–12 hours |

Because your projects live in `Documents`, they are the safest of the three.
Uninstalling CCDW does not delete a single thing you built.

---

## What is remembered

### Settings you set once

| Setting | Where you set it |
|---|---|
| Which AI provider you use (Foundry, Bedrock, or Anthropic) | The installer, on first run |
| Which Claude model is the default | Dashboard, or `/model` in the Terminal |
| Light or dark theme | Terminal |
| Standing instructions for every conversation | Claude Chat's gear icon, or a `CLAUDE.md` file |
| Any plugins or custom skills you have added | Terminal |

You configure these once. They are read back every time CCDW starts.

### Standing instructions — the one worth knowing about

CCDW keeps a file of instructions that get applied to *every* conversation,
everywhere in the product. Things like:

> Always explain your reasoning before making a change.
>
> Assume I am not a developer. Skip the jargon.
>
> This company uses British English.

Set them once and every page obeys them from then on — Workshop builds, Chat
conversations, Terminal sessions.

There are two levels, and both persist:

- **Global** — applies everywhere. Set it in Claude Chat's settings, or edit
  `~/.claude/CLAUDE.md` in the Terminal.
- **Per-folder** — a `CLAUDE.md` file inside a project folder, applying only to
  work in that folder. Create one by typing `/init` in the Terminal while
  inside the folder.

Per-folder instructions are the more useful of the two once you have a few
projects. "This project's data comes from the returns warehouse, and dates are
always DD/MM/YYYY" is worth writing down once.

### Conversations and history

| What | Persists? |
|---|---|
| Claude Chat conversations, all of them | Yes |
| Which folder each conversation was pointed at | Yes |
| Terminal sessions, mid-scroll and mid-task | Yes — closing the browser does not end them |
| Workshop project history and change requests | Yes |
| The per-folder record of what Claude has done before | Yes |

That last one matters more than it sounds. Claude Code keeps a history per
folder, so returning to a project after two weeks means it can pick up context
rather than meeting the work cold.

### Your projects, and their memory of themselves

Anything built in Workshop lands in your real `Documents` folder, and each
project keeps its own notes alongside the code:

| File | What it holds |
|---|---|
| `.make-it-state.md` | Where the project got to, what is outstanding, what to do next |
| `.make-it/app-context.json` | The design decisions made when it was built |
| `CHANGELOG.md` | What changed and when |
| `TODO.md` | The running to-do list |
| `handoff.md` | A mid-session checkpoint, written by `/clear-it` |

This is why "continue where I left off" works. You are not relying on the AI to
remember — the project wrote down its own state. Open it in Workshop weeks
later and it reads those files first.

### Sign-ins, and the exception

| What | Persists? |
|---|---|
| GitHub sign-in | Yes |
| Git identity — your name and email on commits | Yes, inherited from your machine |
| Azure or AWS sign-in | Partly — see below |

Your Azure and AWS credentials are *shared with your Mac or PC* rather than
copied into CCDW. Sign in on either side and both see it.

**But the token they issue expires, typically after 8 to 12 hours.** This is a
security control set by your organization, not a CCDW limitation, and it cannot
be extended from inside CCDW. When it lapses, pages report "AI provider not
configured" or "token has expired."

The fix takes fifteen seconds: open the Terminal page and type

```
login
```

Nothing is lost when a token expires. Conversations, projects, and settings are
all still there — the connection to the provider is simply asleep.

---

## What happens when you update

Re-running the installer pulls a new version. **It does not reset you.**

On each start, CCDW compares what ships in the new version against what you
already have, and adds only what is missing. Files you have — your settings,
your instructions, your history — are left exactly as they are. New defaults
introduced by an update appear alongside them.

| On update | Result |
|---|---|
| Settings you changed | Kept |
| Your `CLAUDE.md` instructions | Kept |
| Conversations and project history | Kept |
| Custom skills you added | Kept |
| Bundled skills | Updated to the newest version |
| New defaults from the update | Added |

The make-it skills also check for their own updates every time the container
starts, independently of the CCDW version. You stay current without doing
anything.

---

## What clears it

Only two things, and both are deliberate:

| Action | What goes |
|---|---|
| Running the reset script (`reset-claude.bat` on Windows) | Settings, conversation history, GitHub sign-in, custom skills. **Projects in `Documents` survive.** |
| Manually deleting the container's storage area | The same |

Ordinary operations are safe. Stopping the container, restarting it, rebooting,
updating, closing every browser tab — none of these clear anything.

---

## Practical advice

**Set your standing instructions on day one.** Five minutes writing down how
you want Claude to talk to you pays back over every conversation afterwards.
Most people discover this feature far too late.

**Write a `CLAUDE.md` in any project you will return to.** Put the things you
would otherwise re-explain every time — where the data comes from, what the
odd column names mean, which conventions to follow.

**Let `/wrap-it` end your day.** It writes down where you got to, so tomorrow
starts from a note rather than from memory.

**Treat "token expired" as routine.** It is the single most common CCDW
message, it means nothing is wrong, and `login` fixes it.

**Back up `Documents` anyway.** CCDW persists your work faithfully, but
persistence is not backup. Claude can also overwrite files, confidently, when
it has misunderstood you.

---

## Common questions

**Do I have to pick my AI provider again after a restart?**
No. Chosen once during install.

**Will my chat history still be there tomorrow?**
Yes. Conversations are stored, not held in the browser tab.

**I closed my browser mid-task in the Terminal. Did I lose it?**
No. Reopen `localhost:7681` and you are back where you were, scroll history
included.

**Does updating CCDW wipe my settings?**
No. Updates add; they do not replace what you have customized.

**If I uninstall CCDW, do I lose the apps I built?**
No. They are ordinary folders in `Documents` and stay there.

**Why do I keep having to sign in?**
Because your organization's tokens are short-lived on purpose. Type `login`.

**Can I move my setup to a new laptop?**
Your projects move by copying `Documents`. Settings and conversation history
live in container storage and do not come along automatically — expect to
re-run the installer and re-set your preferences on the new machine.

---

## Related pages

- **Getting Started** — the one-time setup this page is about preserving.
- **Troubleshooting** — where "token has expired" is the most common entry.
- **The make-it Framework** — the skills that keep your projects' own notes.
- **Glossary** — plain-English definitions for the terms above.
