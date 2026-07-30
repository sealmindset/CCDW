# Which Page Should I Use?

All five CCDW pages talk to the same assistant with the same access to your
files. The difference is how much machinery you see and how much structure you
get. This page helps you pick.

---

## The short answer

| If you want to... | Use |
|---|---|
| Build a working app or tool | **Workshop** |
| Ask questions about files or folders | **Claude Chat** |
| Change files across a project, conversationally | **Claude Chat** |
| Check that everything is running | **Dashboard** |
| Look at files yourself, or make a small manual edit | **VS Code** |
| Use Claude Code the way developers do | **Terminal** |

---

## Workshop vs. Claude Chat — the one that actually confuses people

These two overlap the most. Both let you describe what you want in plain English.
Both do real work on real files. The difference is **structure**.

| | Workshop | Claude Chat |
|---|---|---|
| **Mental model** | "Build me a thing" | "Let's talk about my stuff" |
| **Produces** | A named project you can run and show people | An answer, or edits to files you already have |
| **Organized as** | A list of projects, each with its own change history | A list of conversations, like a messaging app |
| **Scope** | One project per conversation | Any folder; switch folders any time |
| **Runs your app for you** | Yes — gives you a link to open it | No |
| **Best for** | Something that did not exist before | Something that already exists |

**Rules of thumb:**

- If the output is *an app someone will open*, use **Workshop**.
- If the output is *an answer, an edit, or a decision*, use **Claude Chat**.
- If you are not sure, start in **Claude Chat**. It is lower commitment, and you
  can always move to Workshop once you know what you want built.

**A concrete pair:**

> "Build me a dashboard showing weekly returns by region."
> → **Workshop.** You want a thing that runs.

> "Look at these three returns exports and tell me which region got worse."
> → **Claude Chat.** You want an answer.

---

## Full comparison

| | Dashboard | Workshop | Claude Chat | VS Code | Terminal |
|---|---|---|---|---|---|
| **Address** | `:3000` | `:9200` | `:3002` | `:8080` | `:7681` |
| **Terminal knowledge needed** | None | None | None | A little | Yes |
| **Can build a new app** | No | Yes | Yes, but unstructured | Manually | Yes |
| **Can edit your existing files** | No | Within a project | Anywhere you point it | Manually | Anywhere |
| **Keeps a conversation history** | No | Per project | Yes, searchable | No | Per session |
| **Shows what it is doing** | Service health | Progress steps | Collapsible activity chips | You do it yourself | Full detail, always |
| **Good for non-technical users** | Yes | Yes | Yes | Somewhat | No |

---

## By role

**Analyst / operations**
Start with **Claude Chat** pointed at your data folder. Ask questions, get
summaries, have it produce cleaned-up files. Graduate to **Workshop** when you
find yourself asking the same question every week and want a tool for it.

**Product manager / designer**
**Workshop.** Build the prototype yourself instead of writing a spec about it.
Show it in the review. Use **Claude Chat** to read through existing docs or
codebases you need to understand.

**Manager / executive**
**Claude Chat** for reading and summarizing. **Dashboard** to confirm things are
running. You will likely never need the other three.

**Developer**
**Terminal** or **VS Code** for real work. **Workshop** is genuinely faster for
scaffolding something new. **Claude Chat** is useful for exploring an unfamiliar
repository without polluting your terminal session.

---

## A note on switching between pages

You are not locked in. Everything writes to the same files, and Claude Chat
conversations can be picked up in the Terminal (see the **Claude Chat** page for
how). A common pattern is:

1. Explore and decide in **Claude Chat**.
2. Build in **Workshop**.
3. Inspect the result in **VS Code**.
4. Ask for refinements back in **Workshop**.

---

## Related pages

- **Dashboard**, **Workshop**, **Claude Chat**, **VS Code**, **Terminal** — the
  detail page for each.
- **What Is CCDW?** — background on why these five exist.
- **The make-it Framework** — the built-in skills all five pages share.
- **What CCDW Remembers** — settings and history persist across all five.
