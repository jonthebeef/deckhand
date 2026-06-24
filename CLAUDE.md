# deckhand

A Claude Code **plugin** bundling two skills, `ticket-lifecycle` and `managing-project-backlog`. The same skills also run standalone on Codex and Cursor, so keep everything platform-agnostic (plain Markdown plus `gh` / `curl`, no Claude-Code-only hooks).

## Layout

- `.claude-plugin/plugin.json` - the plugin manifest (name, version, license, etc.). Only this file lives in `.claude-plugin/`.
- `skills/ticket-lifecycle/` and `skills/managing-project-backlog/` - the two skills, each a `SKILL.md` plus supporting files. Skills live at `skills/<name>/`, not inside `.claude-plugin/`.
- Root: `VERSION`, `bump.sh`, `README.md`, `CHANGELOG.md`, `CLAUDE.md`, `LICENSE`.

## Versioning and releases

- The version lives in four places, kept in sync: the root `VERSION`, `skills/ticket-lifecycle/VERSION`, `skills/managing-project-backlog/VERSION`, and the `version` field in `.claude-plugin/plugin.json`. They share a single number.
- **Do not edit those by hand.** Use the helper: `./bump.sh patch | minor | major` (or `./bump.sh X.Y.Z`). It writes all four and prints the publish commands.
- Bump whenever you ship a user-facing change to either skill: patch for fixes, minor for new behaviour, major for breaking changes. Add a `CHANGELOG.md` entry too.
- A change is not "released" until the bump is on `main`. That triggers the standalone-skills update offer, and the plugin manager picks up the new `plugin.json` version. The check compares version strings, so the published number must only ever go up.

## How updates reach users

- Each skill's first-invocation protocol runs a throttled (once / 24h), opt-out version check and offers an update only when the local copy is behind. Stay-quiet-otherwise is the intended behaviour.
- Updates are agent-driven and applied in place. They MUST preserve the user's populated `board-config.md` (it holds their real board IDs). If you ever touch the update or check instructions, keep that preservation rule intact and keep it working the same on Claude Code, Codex, and Cursor.

## Repo conventions

- Keep `README.md` free of em dashes and en dashes (use plain hyphens), and use UK English in prose.
- Shell scripts (`setup.sh`, `bump.sh`) must stay bash 3.2 safe (the macOS default). No `mapfile`/`readarray`, `declare -A`, or other bash 4+ features.
- Ship `board-config.md` only as the placeholder template. Never commit a populated copy. The runtime markers `.last-update-check` and `.no-update-check` are gitignored; don't commit them.
- Each skill must stay self-contained, so it still works when installed on its own.
- Skill `description` frontmatter controls auto-triggering. Keep it conditional (clear GitHub Projects board intent plus a configured board), not eager, so the plugin does not over-fire in other people's repos. The slash commands stay the explicit path.
- Run `claude plugin validate .` before publishing or submitting to a marketplace.
