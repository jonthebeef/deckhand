# Changelog

All notable changes to deckhand are recorded here. Versions follow [semantic versioning](https://semver.org): patch for fixes, minor for new behaviour, major for breaking changes.

## 1.0.0

First public release. Packaged as a Claude Code plugin while remaining usable as standalone skills on Claude Code, Codex, and Cursor.

### Skills

- **`managing-project-backlog`** - plan and maintain a GitHub Projects v2 board: create epics, break them into linked sub-issues, prioritise, assign owners, and move tickets across the kanban.
- **`ticket-lifecycle`** - take tickets from a board through the full lifecycle: parallel implementation in git worktrees, isolated code review, a fix-loop (up to 5 rounds), CI gating, merge, and board cleanup.

### Notable features

- **Adversarial review lenses** - review runs as separate cold lenses (Breaker for correctness, Tests for assertion quality, Security on sensitive diffs) so a same-model reviewer does not share the implementer's blind spots.
- **Tight context, big-picture awareness** - each worker gets a single ticket plus a distilled summary of its parent epic and sibling tickets.
- **Quiet update check** - a throttled, opt-out version check offers an update only when behind, and updates in place without clobbering your populated `board-config.md`.
- **Cross-platform** - plain Markdown plus `gh` and `curl`; runs anywhere an agent can run a shell.
