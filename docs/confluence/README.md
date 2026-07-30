# CCDW Documentation — Confluence Source Files

These are the source files for the CCDW space in Confluence. Each `.md` file is
one Confluence page. They are written in plain, portable Markdown so you can
copy the file contents and paste them straight into the Confluence editor
without cleanup.

## Suggested page tree

```
CCDW
├── What Is CCDW?                    01-what-is-ccdw.md
├── Getting Started                  02-getting-started.md
├── Which Page Should I Use?         03-which-page-should-i-use.md
├── Pages
│   ├── Dashboard                    04-dashboard.md
│   ├── Workshop                     05-workshop.md
│   ├── Claude Chat                  06-claude-chat.md
│   ├── VS Code                      07-vs-code.md
│   └── Terminal                     08-terminal.md
├── The make-it Framework            11-make-it-framework.md
├── What CCDW Remembers              12-what-ccdw-remembers.md
├── Troubleshooting                  09-troubleshooting.md
└── Glossary                         10-glossary.md
```

> **Note on numbering:** files 11 and 12 were added after the original ten. In
> Confluence, order the pages as shown in the tree above — the filename numbers
> are creation order, not reading order.

## A related doc set

The **make-it framework** bundled into CCDW maintains its own Confluence pages —
one overview plus one per skill. They live inside the container at
`~/.claude/make-it/confluence-docs/` and are refreshed on every container start.

`11-make-it-framework.md` is the CCDW-side bridge: what the framework is, that
it is built in rather than optional, and how each CCDW page exposes it. Publish
the per-skill pages from the container as a child space or sibling tree rather
than copying them here — they update upstream, and a copy in this repo would
drift.

## How to paste into Confluence

1. Create the page in Confluence.
2. Open the `.md` file, select all, copy.
3. Paste into the Confluence editor. Confluence Cloud detects Markdown on paste
   and converts headings, tables, bullets, bold, and code blocks automatically.
4. If your Confluence does not auto-convert, use **`+` → Other macros → Markdown**,
   or the `/markdown` slash command, and paste there instead.

## Images

Screenshots live in `img/`. Markdown image links like `![Dashboard](img/dashboard.png)`
will **not** resolve in Confluence — Confluence needs the file as a page attachment.

For each page that has images:

1. Paste the Markdown as above. The image line will come through as broken or as
   plain text; that is expected.
2. Delete the broken image line.
3. Drag the matching PNG from `img/` into the editor at that spot.

| Image | Used on |
|---|---|
| `img/dashboard.png` | Dashboard |
| `img/workshop.png` | Workshop |
| `img/workshop-tour.png` | Workshop |
| `img/claude-chat.png` | Claude Chat |
| `img/claude-chat-turn.png` | Claude Chat |
| `img/claude-chat-tool-expanded.png` | Claude Chat |
| `img/vs-code.png` | VS Code |
| `img/terminal.png` | Terminal |

## Keeping these current

The docs describe the product as of the container image published to
`ghcr.io/sealmindset/claude-code-docker:latest`. When a page changes materially,
update the `.md` file here first, then re-paste into Confluence, so the repo
stays the source of truth.
