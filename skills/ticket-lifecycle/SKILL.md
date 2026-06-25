---
name: ticket-lifecycle
description: "Run the deckhand ticket lifecycle: take GitHub issues from a GitHub Projects board through implementation, isolated adversarial review, a fix-loop, CI gating, and merge. Use eagerly when working a board: 'iterate on these tickets', 'work through the backlog', 'pick up #N', 'process the prioritized column', a batch of issue numbers, an epic, or /ticket-lifecycle. The skill is board-aware: it confirms a GitHub Projects board is in play (configured for this repo, or present on it) before acting, and steps aside if there is no board, so it never barges into an unrelated repo. Modular: use whichever of the Phase 1 to 7 steps fit (single ticket, single PR, cleanup-only, and constrained single-thread environments all work)."
---

# Ticket Lifecycle

Automated batch ticket processing for any GitHub-Projects-driven repo. Take a set of GitHub issues, implement fixes, run code review, address feedback, watch CI, merge when green, and move tickets across the Kanban board.

> **⛔ Invocation rule — this skill is MODULAR.**
>
> Ticket Lifecycle is for running a GitHub Projects board's tickets through their full lifecycle; reach for it when that is what the user wants, not for every passing mention of a bug or issue. The full Phase 0→7 sequence describes the **ideal** run: many tickets in parallel worktrees, fresh-context reviewers, the lot. But the value of the skill is the **discipline of the phases**, not the parallelism. Most sessions will use a subset:
>
> - **Solo / single ticket, sequential, no worktrees** → still use this skill. Drop Phase 2's parallelism, run one Implement → Simplify → Review → Fix-loop → Merge cycle. Phase 0 (load learnings) and Phase 3.5 (capture learnings) still apply.
> - **Fixing review feedback on an existing PR** → start at Phase 4. You already have implementation; just run the fix-and-review loop until clean, then Phase 6 (Merge) and Phase 7 (Cleanup).
> - **Already-merged ticket, board cleanup pending** → jump to Phase 7.
> - **Can't dispatch subagents at all** → run the phases yourself in the main thread. The review-isolation rule (Phase 3) becomes "open a fresh Claude Code session for the review" instead of "dispatch an isolated agent". The discipline still holds.
> - **Tiny one-line fix** → Phases 1 (read), 2 (implement + test), 6 (merge), 7 (board move) are usually enough. Skip Simplify and Review only if the change is genuinely trivial and the user has signalled they don't want a fresh-eyes review.
>
> **Do not skip this skill because you can't run all of it.** The wrong move is "I can't do Phase 2 in parallel worktrees, therefore I won't use Ticket Lifecycle at all" — that throws away Phases 0, 3, 3.5, 4, 5, 6, 7 along with it. Instead: announce which phases apply, which you're skipping, and why. Then run the applicable phases properly.
>
> **Phases are independently valuable.** Phase 3 (isolated review) on its own catches bugs. Phase 4 (review loop) on its own raises PR quality. Phase 5 (sub-issue linking) on its own keeps the backlog navigable. Use what fits.
>
> When the user wants the board-driven lifecycle, invoke and state which phases you're using.

> **⚠ First-invocation protocol (read this BEFORE running any phase).**
>
> deckhand only operates on a GitHub Projects board, so first establish which situation you're in by reading `references/board-config.md`:
>
> - **Configured** — `board-config.md` has no `<...>` placeholders (`<OWNER>`, `<REPO>`, `<PROJECT_NUMBER>`, `<PROJECT_ID>`, `<STATUS_FIELD_ID>`, `<EPICS_OPTION_ID>`, etc.). Proceed with the workflow as normal — this is the everyday case, and "pick up #N" / "process prioritized" should just work.
> - **Not configured, but a board is in play** — placeholders remain, but the user is clearly doing GitHub Projects board work, or the repo's owner has a board (a quick `gh project list --owner <owner>` returns one). Offer to wire deckhand up: run setup (below), then proceed. Ask first; don't force it.
> - **No board in play** — placeholders remain AND there is no GitHub Projects board to drive (not a GitHub repo, or `gh project list` comes back empty, and the user only said something generic). Step aside: briefly say deckhand runs off a GitHub Projects board and you don't see one here, offer to set one up if they'd like, and otherwise do nothing. Do NOT run board operations or push setup on someone who has no board.
>
> When a board is in play but not yet configured, set it up before any board operation. **You — the assisting Claude — must run setup before any board operation.**
>
> Two options, in order of preference:
>
> 1. **Run the bundled script:** `bash <path-to-skill>/setup.sh`. It's interactive — it will ask the user for owner, repo, and project number, auto-discover the rest via `gh api graphql`, and write the populated config to this skill's `references/board-config.md` (and to `managing-project-backlog/board-config.md` if it's installed alongside). When invoking from Claude Code, ask the user the three questions in chat, then call the script and pipe the answers in — or perform the equivalent GraphQL discovery yourself and write `board-config.md` directly.
>
> 2. **Do it inline:** if the user can't run an interactive script, you can do the discovery yourself. Ask the user for owner / repo / project number, then run:
>    ```bash
>    gh api graphql -f query='query{user(login:"<OWNER>"){projectV2(number:<NUM>){id title fields(first:50){nodes{... on ProjectV2SingleSelectField{id name options{id name}}}}}}}'
>    ```
>    (swap `user` for `organization` if the owner is an org). Show the user the discovered column list, ask them to map each of the six workflow terms (Epics / Backlog / Prioritized / Doing / Review / Done) to one of their actual columns, then write the populated `references/board-config.md` yourself.
>
> Do not invent IDs. Do not skip setup and hope it works — every Phase that touches the board needs real IDs. Only proceed to the rest of the workflow once `board-config.md` has no `<...>` placeholders left.
>
> The skill assumes the **logical** workflow columns Epics / Backlog / Prioritized / Doing / Review / Done. Your actual column names can be anything — setup maps your column names to these terms. The skill also assumes a `CLAUDE.md` at repo root with project standards and (optionally) a lessons doc.

> **🔄 Staying up to date (quiet by default).**
>
> On your **first invocation in a session**, run a throttled version check from the folder this skill is installed in (the one holding this `SKILL.md` and its `VERSION`). Suggested one-liner — adapt the path; on Codex/Cursor it's wherever this skill actually lives:
>
> ```bash
> DIR="<this skill's folder>"
> [ -f "$DIR/.no-update-check" ] && exit 0                                                                        # user opted out
> [ -f "$DIR/.last-update-check" ] && [ -z "$(find "$DIR/.last-update-check" -mtime +0 2>/dev/null)" ] && exit 0  # checked < 24h ago
> touch "$DIR/.last-update-check"
> LOCAL=$(cat "$DIR/VERSION" 2>/dev/null)
> REMOTE=$(curl -fsS --max-time 3 https://raw.githubusercontent.com/jonthebeef/deckhand/main/skills/ticket-lifecycle/VERSION 2>/dev/null)
> [ -n "$REMOTE" ] && [ "$REMOTE" != "$LOCAL" ] && echo "deckhand update available: $LOCAL -> $REMOTE"
> ```
>
> - **If a newer version is reported:** tell the user once, briefly (*"deckhand $REMOTE is available, you have $LOCAL — want me to update it?"*), then get on with their actual request. Never block on it.
> - **If current, offline, or the check errors:** say nothing. Silence is the default.
> - Don't offer twice in one session — if `managing-project-backlog` already offered, skip.
> - To disable: the user drops an empty `.no-update-check` file in this folder, or just asks. See the README's "Staying up to date" section.

> **⬆️ Updating (only on request or an accepted offer) — update in place, don't break anything.**
>
> 1. **Confirm** with the user first.
> 2. **Fetch latest:** download the repo (e.g. `curl -fsSL https://codeload.github.com/jonthebeef/deckhand/tar.gz/refs/heads/main` to a temp dir, extract).
> 3. **Overwrite in place** — replace `SKILL.md`, `setup.sh`, `VERSION`, and everything under `references/` in this skill's installed folder with the new copies.
> 4. **PRESERVE — never overwrite:** `references/board-config.md` (the user's real board IDs), the `.no-update-check` / `.last-update-check` markers, and anything else populated locally.
> 5. **Verify:** confirm `board-config.md` is untouched, confirm the new `VERSION`, list what changed. If anything would clobber the user's config, STOP and ask.
> 6. **Report** the new version and that config was preserved. Do the same for `managing-project-backlog` if it's installed alongside.
>
> Same procedure on Claude Code, Codex, and Cursor — just write to wherever this skill actually lives on that platform.

## Trigger Examples

- `"Work through #27, #28, #29"`
- `"Iterate on the auth epic"`
- `"Process all prioritized tickets"`
- `"Run ticket lifecycle on the backlog"`

## Input Formats

Accept any of:
1. **Issue numbers**: `#27 #28 #29` or `27, 28, 29`
2. **Epic reference**: `auth epic` or `epic #21` — fetch sub-issues
3. **Board column**: `prioritized` — pull all issues from that column
4. **Current PR feedback**: `fix the review feedback on PR #N`

## Workflow

### Phase 0: Load Learnings

Before any implementation work, read both (if they exist):

1. **Durable project lessons** — typically `docs/lessons.md` (or wherever your project keeps engineering standards / postmortems)
2. **Iteration-driven PR review patterns** — a memory file at `~/.claude/projects/<your-project-slug>/memory/feedback_pr_review_lessons.md` if Claude Code is configured to use per-project memory, or anywhere else your team keeps PR-review lessons (create if missing). The `<your-project-slug>` is whatever directory name Claude Code uses for this repo's memory.

The first captures broad engineering lessons (migration safety, search-before-changing, etc.). The memory file captures PR-review-specific patterns that compound from iteration to iteration. Feed both into every implementation agent prompt so the same issues don't recur. For example, if past reviews flagged "missing tests" repeatedly, every agent prompt should explicitly require tests.

If neither file exists yet, this is fine — start one as you go. Capture findings in Phase 3.5.

### Phase 1: Gather and Prepare

1. **Resolve input to issue numbers** — fetch from epic sub-issues or board column if needed
2. **Read every issue** — `gh issue view {n}` for each, understand the full scope
3. **Read each issue's parent epic and sibling sub-issues** — for every ticket, fetch its parent epic (the user-facing goal, the "What's Been Built" / "What's Next" sections) and list its sibling sub-issues, so you understand how the piece fits the bigger picture before dispatching. `managing-project-backlog` §4 (Context Gathering) has the exact `gh` commands. Distil what you learn into a short **epic-context summary per ticket** to hand the worker agent — don't make every worker re-read the whole epic; gather it once here and pass down only what's relevant, keeping each agent's context tight.
4. **Check existing assignees** — if an issue is already assigned to someone other than the current `gh` user, STOP and ask before taking it over. The other person may already be working on it.
5. **Read all affected source files** — understand the code before dispatching agents
6. **Read the learnings files** — load current review patterns to include in agent prompts
7. **Create task list** — one task per issue for progress tracking
8. **Assign each issue to the picking-up user, then move to Doing** — assignment is mandatory and must happen before the status flip. Use `GH_USER=$(gh api user --jq .login)` and `gh issue edit N --add-assignee "$GH_USER"`. See the "Assigning the picker" section in `managing-project-backlog` for the full rule.

Board details are in `references/board-config.md`.

### Phase 2: Parallel Implementation

Dispatch one Agent per issue, each in its own **worktree** (`isolation: "worktree"`), running in background:

Each agent must:
1. Create a branch from `main` (naming: `fix/{issue-number}-short-description` or `feat/{issue-number}-short-description`)
2. Implement the change with tests where applicable (security-sensitive code and API endpoints get integration tests; pure UI work gets manual verification steps)
3. Run verification locally — adapt to your stack:
   - Frontend: open the app and verify the change works (or run the dev server)
   - Backend / API: run the project's test suite (e.g. `npm test`, `pytest`, etc.)
   - CLI / scripts: run them locally with sample input
4. Commit with a message referencing the issue: `fix: description (#N)` or `feat: description (#N)`
5. Push the branch
6. Create a PR with `gh pr create` — include summary, test plan, and `Closes #N`
7. Watch CI with `gh run list --branch {branch} --limit 1` until green
8. Move the issue to **Review** on the board when the PR is raised
9. Report the result

Write detailed, specific agent prompts. See `references/agent-prompts.md` for structure, examples, and anti-patterns. Never delegate understanding — include file paths, line numbers, and exact changes in every prompt.

**Include epic context in every agent prompt.** Add a short "Epic context" section summarising the parent epic's goal and any sibling tickets that touch the same area (from the per-ticket summary you gathered in Phase 1). This gives each worker enough big-picture awareness to build the right thing — how its ticket serves the product — without loading the full epic into its window. Tight brief, clear purpose.

**Include learnings in every agent prompt.** Append a "Known pitfalls" section to each prompt summarising the relevant patterns from the learnings files. This prevents agents from repeating mistakes that past reviews have already caught.

### Phase 2.5: Simplify

> **Optional phase — depends on the `simplify` skill being installed.** If it isn't available, skip this phase: announce that you're skipping it (Phase 3's review still catches the same cleanup concerns, just later) and move straight to Phase 3. Do not fail or stall the run because `simplify` is missing.

Before raising the PR for review, each implementation agent should run the **`simplify`** skill on its own changes *if it's installed*. This catches reuse opportunities, dead code, and over-abstraction *before* a reviewer ever sees the diff — meaning Phase 3 reviews focus on real concerns instead of cleanup nits.

Add this to every implementation agent prompt, between "verification passes locally" and "create the PR":

```
If the `simplify` skill is available, invoke it on the files you touched and apply the suggested simplifications (consolidate duplicates, remove dead code, drop premature abstractions, prefer existing helpers), then re-run verification. If `simplify` is not installed, skip this step and proceed. Only then commit and create the PR.
```

If simplify produces non-trivial changes, fold them into the same commit (or a follow-up `refactor:` commit on the same branch) before pushing. The PR description should not need to mention simplify ran — the diff should just be cleaner.

### Phase 3: Code Review

Once all implementation agents complete, review each PR with a small set of **adversarial lenses** rather than one generalist pass. Each lens is its own cold review agent (isolation rules below), reviewing the same diff with a different job and a sceptical default: find the worst real problem, and if there genuinely isn't one, say so explicitly.

**Why lenses, not one reviewer:** a fresh cold reviewer removes *context* bias (it isn't swayed by the implementer's reasoning), but a same-model reviewer running a generic prompt still shares the implementer's *attention* blind spots — it glosses over the same things. Giving each reviewer a distinct adversarial job decorrelates where they look, which recovers most of the benefit of an independent reviewer at no loss of review power. (You don't need a weaker model; you need a differently-pointed one.)

**The lens set — tiered by risk, so you don't pay for more than the diff needs:**

| Diff | Lenses to run |
|---|---|
| Trivial (typo, copy, config one-liner) | **Breaker** only |
| Normal (the default) | **Breaker** + **Tests** |
| Sensitive (touches auth, API, input handling, secrets, payments, or a security-labelled ticket) | **Breaker** + **Tests** + **Security** |
| High-stakes | all three, and if you have a second capable model available, run one lens on it for true model-level decorrelation |

The lenses:

- **Breaker (correctness)** — actively try to make it fail: edge cases, bad input, unhandled states, and whether it *actually* satisfies the ticket rather than just looking like it does. The workhorse; always runs.
- **Tests** — is the right thing tested, and do the assertions check *correct* behaviour rather than rubber-stamping whatever the code currently does? (A reviewer sharing the implementer's blind spot will happily approve a test that asserts the bug. This lens is the guard against that.)
- **Security** (sensitive diffs only) — assume hostile input: auth/session/token handling, injection, secret/credential exposure, data leakage.

Per-lens prompt templates are in `references/agent-prompts.md`.

1. **Dispatch the lens set for each PR in parallel** (use Agent tool with `subagent_type: "superpowers:code-reviewer"` if installed; otherwise `subagent_type: "general-purpose"` with the lens prompt). Pick the tier from the table by inspecting the diff. Each lens runs `gh pr diff {n}` and reviews against `CLAUDE.md` standards through its own lens.
2. **Merge and dedupe across lenses** — the same issue may surface from two lenses; collapse it to one finding, keeping the most serious framing.
3. Collate the merged results per PR.

**CRITICAL: Review isolation.** Every lens reviewer MUST be a fresh agent with NO context from the implementation session. This is non-negotiable, and it applies to each lens independently. Each lens reviewer should:
- Have NO knowledge of what the implementation agent was asked to do or why
- See ONLY the diff (`gh pr diff`) and project standards (CLAUDE.md, lessons doc)
- Form its own judgement about code quality, completeness, and correctness
- NOT be swayed by the implementation agent's reasoning or trade-offs

A lens reviewer prompt must NEVER include:
- The implementation agent's prompt or output
- Summaries of what was built or why
- Justifications for design decisions
- "The agent did X because Y" context

A lens reviewer prompt SHOULD include:
- The PR number and repo
- A one-sentence factual description of what the PR does (e.g., "adds a files dashboard at /files")
- Instructions to read CLAUDE.md and the lessons doc
- **The lens's specific adversarial job and checklist** (see the per-lens templates in `references/agent-prompts.md`)

This ensures the review is a genuine independent assessment, not a rubber stamp of the implementation.

Categorise findings:
- **Must fix** — blocking issues to address before merge
- **Follow-up tickets** — non-blocking improvements, create as new GitHub issues in Backlog
- **Observations** — note but don't action

### Phase 3.5: Capture Learnings

After collating all review results, analyse the findings for **new patterns** — recurring issues or novel mistakes not already captured in the learnings files.

1. **Read the current learnings files** — both the project lessons doc and the memory file (create if missing)
2. **Compare review findings against existing patterns** — identify what is new
3. **Decide where the lesson belongs:**
   - **Project lessons doc** — durable, domain-agnostic engineering lessons (e.g., migration checklists, git worktree patterns)
   - **Memory file** — PR-review-specific patterns that emerge from iteration (e.g., "Sanitize user-provided HTML before DOM insertion", "Auth checks missing on API routes")
4. **(Optional) Update a stats file** — track total PRs reviewed, issues found, review rounds across iterations

Only add genuinely new patterns. If a review catches an issue that's already a known pattern, don't duplicate. But if a new category of issue appears, add it.

The goal: every iteration makes the next iteration cleaner. The learnings file is the flywheel.

### Phase 4: Fix Review Feedback — Review Loop

For any PR with "must fix" items, run a **review loop** until the reviewer returns clean. A single fix pass is not enough — fixes themselves often introduce new issues, and reviewers regularly surface concerns on a second pass that they missed on the first.

**The loop:**

1. Dispatch a fix agent to the existing worktree/branch
2. Agent addresses ALL "must fix" feedback from the latest review
3. Agent commits, pushes, and watches CI until green
4. Re-review the updated PR by **re-running only the lens(es) that raised the must-fix** — usually **Breaker**; add **Tests** if a test issue was the blocker, or **Security** for a sensitive diff. A fresh agent per lens each round (same isolation rules as Phase 3 — no context from prior rounds, no knowledge of what was fixed or why). Re-running the whole lens set every round is rarely worth the cost; the lens that found the problem is the one that confirms the fix.
5. Categorise the new findings using the same buckets as Phase 3:
   - **Must fix** → another fix-and-review round
   - **Follow-up tickets** → defer to Phase 5 (do NOT block the loop on these)
   - **Observations** → note only
6. If there are any new "must fix" items, return to step 1. If the review is clean of "must fix" items, exit the loop for this PR.

**Loop termination:**
- Exit when the reviewer returns zero "must fix" findings.
- Hard cap: **5 rounds per PR**. If round 5 still has "must fix" items, stop the loop, report the situation to the user, and ask how to proceed (the change may need rescoping or splitting). Do not silently merge a PR with unresolved must-fix findings.
- Track the round count per PR and report it in the final summary table ("Review Rounds" column).

**What stays a follow-up ticket, not a loop iteration:** non-blocking suggestions, nice-to-haves, refactor opportunities, and out-of-scope improvements always become Phase 5 tickets — they never re-enter the fix loop. Only blocking correctness, security, or standards-violation findings drive another round.

Each PR runs its own loop independently. Don't gate one PR's merge on another PR's loop unless they're genuinely coupled.

### Phase 5: Create Follow-up Tickets

For all non-blocking review suggestions:

1. Create GitHub issues with clear descriptions
2. **Link them to the appropriate epic as sub-issues — MANDATORY, not optional.** Use the GraphQL `addSubIssue` mutation (preferred — works reliably across token scopes) or the `sub_issues` REST endpoint:
   ```bash
   # GraphQL (preferred)
   gh api graphql -f query='mutation{addSubIssue(input:{issueId:"<EPIC_NODE_ID>",subIssueId:"<SUB_NODE_ID>"}){subIssue{number}}}'
   # or REST
   gh api "repos/<OWNER>/<REPO>/issues/<EPIC_NUM>/sub_issues" -X POST -F sub_issue_id=<SUB_NUMERIC_ID>
   ```
3. **Verify the link** — fetch the parent immediately after and assert it matches the intended epic:
   ```bash
   gh api graphql -f query='query{repository(owner:"<O>",name:"<R>"){issue(number:<SUB_NUM>){parent{number}}}}'
   ```
   A title like `"(#XYZ follow-up)"` is NOT a sub-issue link. Without the structural parent, the epic won't auto-close, board grouping breaks, and future agents lose the trail.
4. Add them to the board in the **Backlog** column
5. Report what was created **and the verified parent epic for each**

This is critical — discovered work must not be lost. Every non-blocking suggestion that has merit becomes a tracked ticket, and every ticket has a verified parent epic before Phase 5 ends.

### Phase 6: Merge

Once all PRs have:
- Exited the Phase 4 review loop with a clean review (zero "must fix" findings)
- Green CI on the latest commit

Merge sequentially:
1. `gh pr merge {n} --squash --delete-branch` for each PR
2. If a merge fails due to conflicts, rebase on main and resolve
3. After all merges, watch the final main branch CI run
4. If main CI fails, diagnose and fix immediately — main must always be stable, especially if it auto-deploys to production

### Phase 7: Board Cleanup

1. Move all completed issues to **Done** on the board
2. Close the issues with a comment linking to the merged PR
3. Update the parent epic's "What's Been Built" section
4. Clean up worktrees: `git worktree remove` + `git worktree prune`
5. Delete local branches
6. Report final summary

## Key Principles

- **Parallelise aggressively** — all independent fixes run simultaneously in worktrees
- **Review everything** — no PR merges without code review, even "trivial" fixes
- **Create tickets for discovered work** — anything found during review that isn't fixed in this iteration gets a tracked issue in Backlog, linked to its epic
- **Watch every pipeline** — never assume CI passes; always verify
- **Fix conflicts inline** — if merging causes conflicts, resolve them immediately rather than asking the user
- **Treat main as production** — broken main blocks everyone (and may break a live deploy); main CI failures are highest priority
- **Report concisely** — status updates at milestones, not play-by-play

## Error Recovery

- **CI fails on PR branch**: Read logs with `gh run view --log-failed`, diagnose, fix, push, re-watch
- **CI fails on main after merge**: Fix immediately
- **Agent fails or times out**: Read the agent output file, diagnose, dispatch a new agent
- **Merge conflicts**: Checkout the branch, rebase on main, resolve conflicts, force-push with lease
- **Review finds critical issues**: Fix before merging, never merge with known critical issues

## Summary Report Template

After completion, report:

```
## Ticket Lifecycle Complete

| Issue | PR | Status | Review Rounds |
|---|---|---|---|
| #N | #M | Merged, CI green, live | X |

**Follow-up tickets created:** #A, #B, #C (in Backlog, linked to epic #E)
**Main branch CI:** Green
**Board:** All issues moved to Done
```

## Additional Resources

- **`references/board-config.md`** — GitHub Projects board IDs, column option IDs, field IDs (fill these in for your project)
- **`references/agent-prompts.md`** — Detailed guidance on writing effective agent prompts for implementation and review
