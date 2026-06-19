---
name: ticket-lifecycle
description: "DEFAULT workflow for any ticket / PR / fix work in a GitHub-Projects repo. Use when the user asks to 'iterate on tickets', 'fix these issues', 'work through the backlog', 'run ticket lifecycle', 'process these tickets', or provides issue numbers / an epic / a board column. ALSO use — in adapted form — for any single ticket, single PR, or fix where the full Phase 1→7 lifecycle (or any meaningful subset of it) applies. The skill is modular: use only the phases that fit. Do not refuse to invoke just because you can't run every phase, can't dispatch subagents, or are in a constrained environment (single thread, sequential, no worktrees). Pick the phases that apply and run them; skip the rest explicitly."
---

# Ticket Lifecycle

Automated batch ticket processing for any GitHub-Projects-driven repo. Take a set of GitHub issues, implement fixes, run code review, address feedback, watch CI, merge when green, and move tickets across the Kanban board.

> **⛔ Invocation rule — this is the DEFAULT, and it is MODULAR.**
>
> Ticket Lifecycle is the default operating mode for ticket / PR / fix work in this codebase. The full Phase 0→7 sequence describes the **ideal** run: many tickets in parallel worktrees, fresh-context reviewers, the lot. But the value of the skill is the **discipline of the phases**, not the parallelism. Most sessions will use a subset:
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
> When in doubt — invoke, then state which phases you're using.

> **⚠ First-invocation protocol (read this BEFORE running any phase).**
>
> Before doing anything else, read `references/board-config.md`. If it still contains placeholder values (any of `<OWNER>`, `<REPO>`, `<PROJECT_NUMBER>`, `<PROJECT_ID>`, `<STATUS_FIELD_ID>`, `<EPICS_OPTION_ID>`, etc.), the skill is not configured for this project yet. **You — the assisting Claude — must run setup before any board operation.**
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
3. **Check existing assignees** — if an issue is already assigned to someone other than the current `gh` user, STOP and ask before taking it over. The other person may already be working on it.
4. **Read all affected source files** — understand the code before dispatching agents
5. **Read the learnings files** — load current review patterns to include in agent prompts
6. **Create task list** — one task per issue for progress tracking
7. **Assign each issue to the picking-up user, then move to Doing** — assignment is mandatory and must happen before the status flip. Use `GH_USER=$(gh api user --jq .login)` and `gh issue edit N --add-assignee "$GH_USER"`. See the "Assigning the picker" section in `managing-project-backlog` for the full rule.

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

Once all implementation agents complete:

1. Dispatch one **code review agent** per PR in parallel (use Agent tool with `subagent_type: "superpowers:code-reviewer"` if you have the superpowers plugin installed; otherwise use `subagent_type: "general-purpose"` with a strict review prompt)
2. Each reviewer runs `gh pr diff {n}` and reviews against `CLAUDE.md` standards
3. Collate all review results

**CRITICAL: Review isolation.** The review agent MUST be a fresh agent with NO context from the implementation session. This is non-negotiable. The review agent should:
- Have NO knowledge of what the implementation agent was asked to do or why
- See ONLY the diff (`gh pr diff`) and project standards (CLAUDE.md, lessons doc)
- Form its own judgement about code quality, completeness, and correctness
- NOT be swayed by the implementation agent's reasoning or trade-offs

The review agent prompt must NEVER include:
- The implementation agent's prompt or output
- Summaries of what was built or why
- Justifications for design decisions
- "The agent did X because Y" context

The review agent prompt SHOULD include:
- The PR number and repo
- A one-sentence factual description of what the PR does (e.g., "adds a files dashboard at /files")
- Instructions to read CLAUDE.md and the lessons doc
- Specific areas to check (security, input validation, auth, tests, YAGNI, etc.)

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
4. Dispatch a **fresh** code review agent on the updated PR (same isolation rules as Phase 3 — no context from prior rounds, no knowledge of what was fixed or why)
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
