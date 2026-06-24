#!/usr/bin/env bash
# Bump the deckhand version across all VERSION files in one go.
#
#   ./bump.sh patch     # 1.0.0 -> 1.0.1  (a fix)
#   ./bump.sh minor     # 1.0.0 -> 1.1.0  (new behaviour)
#   ./bump.sh major     # 1.0.0 -> 2.0.0  (breaking change)
#   ./bump.sh 1.4.2     # set explicitly
#   ./bump.sh           # show current version and usage
#
# Writes VERSION, ticket-lifecycle/VERSION and managing-project-backlog/VERSION,
# then prints the git commands to publish. It does NOT commit or push for you.

set -euo pipefail

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

FILES="
$ROOT/VERSION
$ROOT/skills/ticket-lifecycle/VERSION
$ROOT/skills/managing-project-backlog/VERSION
"

CURRENT=$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || echo "")
[ -z "$CURRENT" ] && CURRENT="0.0.0"

usage() {
  echo "deckhand version bump  (current: $CURRENT)"
  echo
  echo "usage:"
  echo "  ./bump.sh patch     # next patch  ($CURRENT -> fix)"
  echo "  ./bump.sh minor     # next minor  (new behaviour)"
  echo "  ./bump.sh major     # next major  (breaking change)"
  echo "  ./bump.sh X.Y.Z     # set explicitly"
}

if [ $# -eq 0 ]; then
  usage
  exit 0
fi

# Split current version into parts (bash 3.2 safe; here-string appends a newline
# so read returns cleanly under set -e).
IFS='.' read -r MAJ MIN PAT <<< "$CURRENT"
MAJ=${MAJ:-0}; MIN=${MIN:-0}; PAT=${PAT:-0}

case "$1" in
  patch) NEW="$MAJ.$MIN.$((PAT + 1))" ;;
  minor) NEW="$MAJ.$((MIN + 1)).0" ;;
  major) NEW="$((MAJ + 1)).0.0" ;;
  *)
    if echo "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      NEW="$1"
    else
      echo "Error: '$1' is not 'patch', 'minor', 'major', or an X.Y.Z version." >&2
      exit 1
    fi
    ;;
esac

echo "Bumping $CURRENT -> $NEW"
for f in $FILES; do
  echo "$NEW" > "$f"
  echo "  wrote $f"
done

# Keep the plugin manifest version in sync (marketplaces read it from here).
PLUGIN_JSON="$ROOT/.claude-plugin/plugin.json"
if [ -f "$PLUGIN_JSON" ]; then
  TMP="$PLUGIN_JSON.tmp"
  sed -E 's/("version"[[:space:]]*:[[:space:]]*")[^"]*(")/\1'"$NEW"'\2/' "$PLUGIN_JSON" > "$TMP" && mv "$TMP" "$PLUGIN_JSON"
  echo "  updated $PLUGIN_JSON"
fi

echo
echo "Next, publish it:"
echo "  git add VERSION skills/*/VERSION .claude-plugin/plugin.json"
echo "  git commit -m \"release: v$NEW\""
echo "  git push"
