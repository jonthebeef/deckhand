# deckhand

Two Claude Code skills, `ticket-lifecycle` and `managing-project-backlog`, distributed as a public repo. They also run on Codex and Cursor, so keep everything platform-agnostic (plain Markdown plus `gh` / `curl`, no Claude-Code-only hooks).

## Versioning and releases

- The version lives in three `VERSION` files: the repo root, `ticket-lifecycle/`, and `managing-project-backlog/`. They share a single number.
- **Do not edit those files by hand.** Use the helper: `./bump.sh patch | minor | major` (or `./bump.sh X.Y.Z` to set explicitly). It writes all three and prints the publish commands.
- Bump whenever you ship a user-facing change to either skill: patch for fixes, minor for new behaviour, major for breaking changes.
- A change is not "released" until the bumped `VERSION` is on `main`. That is what triggers users' update offer. The check compares version strings, so the published number must only ever go up.

## How updates reach users

- Each skill's first-invocation protocol runs a throttled (once / 24h), opt-out version check and offers an update only when the local copy is behind. Stay-quiet-otherwise is the intended behaviour.
- Updates are agent-driven and applied in place. They MUST preserve the user's populated `board-config.md` (it holds their real board IDs). If you ever touch the update or check instructions, keep that preservation rule intact and keep it working the same on Claude Code, Codex, and Cursor.

## Repo conventions

- Keep `README.md` free of em dashes and en dashes (use plain hyphens), and use UK English in prose.
- Shell scripts (`setup.sh`, `bump.sh`) must stay bash 3.2 safe (the macOS default). No `mapfile`/`readarray`, `declare -A`, or other bash 4+ features.
- Ship `board-config.md` only as the placeholder template. Never commit a populated copy. The runtime markers `.last-update-check` and `.no-update-check` are gitignored; don't commit them.
- Each skill must stay self-contained, so it still works when installed on its own.
