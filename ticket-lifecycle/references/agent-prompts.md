# Writing Effective Agent Prompts

## Implementation Agent Prompts

The quality of the implementation depends entirely on the quality of the prompt. Never delegate understanding — prove comprehension by including specifics.

### Structure

Every implementation agent prompt must include:

1. **Context** — what repo, what branch to create from, what branch name to use
2. **Epic context** — the parent epic's user-facing goal in a sentence or two, plus any sibling tickets that overlap this work, so the agent understands how its ticket serves the product (keep it short — a summary, not the whole epic)
3. **The problem** — what's wrong, with file paths and line numbers
4. **The fix** — exactly what to change, with code snippets where helpful
5. **Test / verification expectations** — what to test or how to verify manually
6. **Known pitfalls** — relevant patterns from the learnings files (see below)
7. **Verification steps** — commands to run locally before pushing
8. **Git operations** — exact commit message, PR title, PR body

### Example Prompt

```
You are implementing GitHub issue #32 in the <OWNER>/<REPO> repo. Branch from `main`. Branch name: `feat/32-files-dashboard`.

## Epic Context
This ticket is part of epic #21 — [one or two sentence summary of the epic's user-facing goal]. Related sibling tickets: #30 ([what it delivers]), #31 ([what it delivers]). Build this so it fits that larger goal and stays consistent with the siblings; don't duplicate what they cover.

## The Problem
[Concrete description of what's broken or missing, with file paths and line numbers]

## The Fix
1. [Exact change 1, with file path]
   [code snippet if helpful]

2. [Exact change 2, with file path]
   [code snippet if helpful]

## Verification Steps
- Manually test: [specific user flow]
- Run: [project's test command — e.g., `npm test`, `pytest`, etc.]
- Check: [edge cases]

## Known Pitfalls (from past reviews)
- [Pattern 1 relevant to this fix]
- [Pattern 2 relevant to this fix]
- [Pattern 3 relevant to this fix]

## Git Operations
- Commit: `feat: short description (#32)`
- Push, create PR titled "feat: short description"
- PR body includes: summary, test plan, `Closes #32`
```

### Including Learnings (Known Pitfalls)

Every agent prompt must include a "Known pitfalls" section drawn from the learnings files. Select the patterns most relevant to the specific fix. Examples of the kinds of patterns worth including (your project will have its own):

```
## Known Pitfalls (from past reviews)
- Sanitize any HTML before DOM insertion to prevent XSS
- Auth tokens must be read from headers, never query params
- Use parameterized queries for all database access
- New API routes need rate limiting
- Search for existing helpers before creating new ones (DRY)
- Errors returned to clients must not leak `err.message`
```

Do not dump the entire learnings files — select the 3-5 patterns most relevant to the specific implementation task. This prevents agents from repeating mistakes that past reviews have already caught.

### Anti-patterns

- "Fix the bug described in issue #32" — agent has no context
- "Based on your findings, implement the fix" — delegates understanding
- "Look at the share handler and improve it" — vague, no specifics
- Missing verification expectations — agent may skip testing
- Missing commit/PR instructions — agent may not create the PR

## Code Review Agent Prompts

### Isolation is non-negotiable

The review agent MUST be a cold reviewer with ZERO context from the implementation session. It must NOT know what the implementation agent was asked to do, why decisions were made, or what trade-offs were considered. It sees only the diff and project standards.

**NEVER include in the review prompt:**
- The implementation agent's prompt or output
- Summaries of implementation reasoning
- "The agent did X because Y" context
- Design justifications

**ALWAYS include in the review prompt:**
- PR number and repo
- One factual sentence: what the PR does (not why or how)
- Instructions to read `CLAUDE.md` and the project lessons doc
- Specific areas to check
- Instructions to post the review as a comment on the PR

### Structure

```
Review PR #{n} in the <OWNER>/<REPO> repo.
[One factual sentence — what the PR does, not why].
Run `gh pr diff {n}` to see the diff.
Read CLAUDE.md for project standards.
Read [path/to/lessons.md] for historical engineering lessons.
Focus especially on: [project-specific concerns — security, auth, input validation, tests, etc.].
Post your review as a comment on the PR.
```

### Use a code reviewer agent type

If you have a code-reviewer subagent (e.g., from the superpowers plugin: `subagent_type: "superpowers:code-reviewer"`), use it. Otherwise use `general-purpose` with a strict review prompt. Either way the agent type ensures a fresh context with no bleed from the implementation session.

### What to ask reviewers to check

Adapt this to your stack. Common universal checks:

- **Security** (auth/session/token handling, database query construction, sensitive data exposure)
- **Input validation** at trust boundaries
- **XSS** — any HTML going into DOM must be sanitized
- **Rate limiting** on new endpoints
- **Tests** — missing or inadequate test coverage (or manual verification steps in PR body)
- **YAGNI violations** — speculative abstractions, unused code paths
- **DRY violations** — duplicated logic
- **Error handling** — leaked stack traces or internals to clients
- **Consistency with existing patterns** in the codebase
- **Whether the fix actually addresses the issue**

## Fix Feedback Agent Prompts

When sending an agent to fix review feedback:

1. **Reference the worktree path** — the code is already there
2. **List every fix needed** — numbered, specific
3. **Include the exact changes** — don't say "fix it", say what to change
4. **Include verification steps** — manual test, project test suite, commit, push, CI watch

### Example

```
You need to fix code review feedback on an existing PR branch.
The worktree is at: /path/to/worktree
The branch is: feat/32-files-dashboard

## Fix 1: [Specific issue]
In `[file]`, [exact change required]:
[code snippet]

## Fix 2: [Specific issue]
In `[file]`, [exact change required]:
[code snippet]

After making all changes:
- Manually re-test [the affected flow]
- Run [project test command]
- Commit: `fix: address PR review — [short description]`
- Push, watch CI
```

## Parallelisation Rules

- **Independent fixes** → parallel worktrees (most cases)
- **Dependent fixes** (e.g., one PR modifies schema another uses) → sequential, or handle conflicts during merge
- **Reviews** → always parallel (read-only operations)
- **Merges** → sequential (each merge changes main, next PR may conflict)
- **Fix feedback** → parallel per PR (each is in its own worktree)

## Handling Merge Conflicts

When merging sequentially and a later PR conflicts:

1. Checkout the conflicting branch locally
2. Rebase on latest main: `git rebase origin/main`
3. Resolve conflicts — understand what both sides intended
4. Run verification (project test suite + manual smoke) to confirm the resolution
5. Force-push with lease: `git push --force-with-lease`
6. Wait for CI to go green
7. Merge
