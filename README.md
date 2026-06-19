# deckhand

*All hands on deck.* Two Claude Code skills that together automate a GitHub Projects v2 kanban workflow end-to-end.

- **`managing-project-backlog`** — the per-board operating manual. How to create epics, break them into sub-issues, move tickets through the kanban, assign owners, and keep the board healthy.
- **`ticket-lifecycle`** — the batch processing workflow on top. Take a set of issues, implement them in parallel, run isolated code review, fix feedback, watch CI, merge, and clean up the board.

The two pair best: `managing-project-backlog` defines the conventions; `ticket-lifecycle` applies them at speed across many tickets.

## Requirements

- [Claude Code](https://claude.com/claude-code) installed
- [`gh` CLI](https://cli.github.com/) authenticated (`gh auth status`)
- `python3` available on `PATH` (used for JSON parsing — both skills assume it)
- A GitHub Projects v2 board attached to a single repo
- A `CLAUDE.md` at your repo root with project standards (optional but strongly recommended — the review phases lean on it)

### Recommended (optional)

- **The `simplify` skill** — `ticket-lifecycle` Phase 2.5 runs it on each change before review, so PRs reach the reviewer already de-duplicated and free of dead code. If it isn't installed the phase is skipped automatically (Phase 3's review still catches the same issues), so it's a nice-to-have, not a hard dependency.
- **A code-reviewer subagent** (e.g. `superpowers:code-reviewer`) for Phase 3's isolated review. Without it, the skill falls back to a `general-purpose` agent with a strict review prompt.

## Install

Drop the two skill folders into your Claude Code skills directory:

```bash
cp -R ticket-lifecycle managing-project-backlog ~/.claude/skills/
```

## First-run setup

Both skills need to know your project's board IDs (project ID, status-field ID, column option IDs, etc.). The skills are configured per-board via a `board-config.md` file inside each skill folder — both ship as placeholder templates and need to be populated once before use.

**Two ways to do this:**

### Option A — Let Claude Code do it for you (recommended)

After dropping the folders into `~/.claude/skills/`, start a Claude Code session in your repo and say:

> "I've just installed the ticket-lifecycle and managing-project-backlog skills. Please set them up for this project."

Both skills have a first-invocation protocol baked into their `SKILL.md` files: when Claude reads either of them and sees that `board-config.md` still contains `<...>` placeholders, it will run the setup script (or do the equivalent GraphQL discovery inline) before doing anything else. You'll be asked for repo owner, repo name, and project number, then asked to map your columns to the six workflow states the skills use (Epics / Backlog / Prioritized / Doing / Review / Done).

### Option B — Run the script yourself

```bash
bash ~/.claude/skills/ticket-lifecycle/setup.sh
```

The script will:

1. Ask for the repo owner, repo name, and project number
2. Use `gh api graphql` to discover the project ID, status-field ID, and every column option ID
3. Ask you to map your column names to the workflow terms (your column names can be anything)
4. Write the populated config to **both** skills' `board-config.md` files

Re-run it any time the board structure changes (new columns, renames, etc.).

## What the skills assume about your kanban

The workflow expects columns that correspond to these six states. Your actual column names can differ — `setup.sh` maps your names to the skill terms.

| Workflow term | What it means |
|---|---|
| Epics | Top-level epic issues (groups of sub-issues) |
| Backlog | Planned work, not yet prioritized |
| Prioritized | Next up — ready to pick up |
| Doing | Actively being worked on |
| Review | PR raised, under review / QA |
| Done | Merged |

Extra columns (Icebox, Live, etc.) are fine — the skills just won't use them. Fewer columns also work; setup will let you point multiple terms at the same column if you collapse states.

## Usage

After install + setup, just talk to Claude Code naturally:

- **`managing-project-backlog`** fires automatically when you mention the board, the backlog, "#N", an epic, or moving tickets between states.
- **`ticket-lifecycle`** fires when you ask Claude to work through a batch of tickets ("iterate on #27 #28 #29", "process the prioritized column", "fix the feedback on PR #N").

You can also explicitly type `/ticket-lifecycle` or `/managing-project-backlog` to invoke them.

## Troubleshooting

- **`gh: command not found`** — install the GitHub CLI and `gh auth login`.
- **`addSubIssue` mutation fails** — your `gh` token may lack the right scopes. Re-run `gh auth refresh -s repo,project`.
- **`setup.sh` reports a missing field** — your board may not have a `Status` field, or it's named something else. Edit `board-config.md` manually after the script runs.
- **The skills can't find `board-config.md`** — `setup.sh` writes to `ticket-lifecycle/references/board-config.md` and `managing-project-backlog/board-config.md`. Confirm both exist.

## Adapting beyond GitHub

The skills are GitHub Projects-shaped today. If you use Linear / Jira / Plane / etc., the workflow discipline (Phase 0–7) still applies; the mechanics (the `gh` and GraphQL calls) would need rewriting against your API. The principles section of `ticket-lifecycle/SKILL.md` is platform-agnostic and worth keeping.

## License

[MIT](LICENSE) — open source, provided "as is" with no warranty. Use at your own risk; read the SKILL.md files before running them on a serious board.

## Credits

Built for personal-project use; sharing in case it's useful.
