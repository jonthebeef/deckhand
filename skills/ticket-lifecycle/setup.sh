#!/usr/bin/env bash
# First-run setup for the ticket-lifecycle + managing-project-backlog skills.
# Discovers your GitHub Projects v2 board IDs via `gh api graphql` and writes
# the populated config to both skills' board-config.md files.
#
# Re-run any time the board changes (new columns, renames, etc.).

set -euo pipefail

# --- Locate skill directories -------------------------------------------------

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SKILL_DIR="$SCRIPT_DIR"
# managing-project-backlog sits next to ticket-lifecycle when both are installed
BACKLOG_DIR="$( cd "$SCRIPT_DIR/.." && pwd )/managing-project-backlog"

if [[ ! -d "$BACKLOG_DIR" ]]; then
  echo "Note: managing-project-backlog skill not found at $BACKLOG_DIR"
  echo "      Will only write ticket-lifecycle/references/board-config.md."
  BACKLOG_DIR=""
fi

# --- Preflight ---------------------------------------------------------------

command -v gh >/dev/null 2>&1 || { echo "Error: gh CLI not found. Install: https://cli.github.com/"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "Error: python3 not found on PATH."; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Error: gh not authenticated. Run: gh auth login"; exit 1; }

echo "== Ticket Lifecycle + Managing Project Backlog — first-run setup =="
echo

# --- Gather user input -------------------------------------------------------

read -rp "GitHub owner (user or org login, e.g. 'octocat' or 'myteam'): " OWNER
read -rp "Repo name (e.g. 'my-app'): " REPO
read -rp "Project number (the integer in the project URL, e.g. 6): " PROJECT_NUMBER

# Detect whether the owner is a user or an org so we use the right GraphQL root.
OWNER_TYPE=$(gh api graphql -f query="query{repositoryOwner(login:\"$OWNER\"){__typename}}" --jq '.data.repositoryOwner.__typename' 2>/dev/null || echo "")
case "$OWNER_TYPE" in
  User) ROOT="user" ;;
  Organization) ROOT="organization" ;;
  *) echo "Error: could not resolve $OWNER as a User or Organization."; exit 1 ;;
esac

echo "Detected owner type: $OWNER_TYPE"
echo

# --- Discover project + status field -----------------------------------------

echo "Fetching project metadata..."
PROJECT_JSON=$(gh api graphql -f query="
query{
  $ROOT(login:\"$OWNER\"){
    projectV2(number:$PROJECT_NUMBER){
      id
      title
      fields(first:50){
        nodes{
          ... on ProjectV2SingleSelectField{
            id name options{id name}
          }
        }
      }
    }
  }
}")

PROJECT_ID=$(echo "$PROJECT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data']['$ROOT']['projectV2']['id'])")
PROJECT_TITLE=$(echo "$PROJECT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data']['$ROOT']['projectV2']['title'])")

echo "  Project: $PROJECT_TITLE (ID: $PROJECT_ID)"

STATUS_FIELD_JSON=$(echo "$PROJECT_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for f in d['data']['$ROOT']['projectV2']['fields']['nodes']:
    if f and f.get('name') == 'Status':
        print(json.dumps(f))
        break
")

if [[ -z "$STATUS_FIELD_JSON" ]]; then
  echo "Error: no 'Status' single-select field found on the project."
  echo "       Edit board-config.md by hand after this script exits."
  exit 1
fi

STATUS_FIELD_ID=$(echo "$STATUS_FIELD_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

echo "  Status field ID: $STATUS_FIELD_ID"
echo

# --- List columns and prompt for mapping -------------------------------------

echo "Detected status columns on this board:"
echo "$STATUS_FIELD_JSON" | python3 -c "
import json, sys
opts = json.load(sys.stdin)['options']
for i, o in enumerate(opts, 1):
    print(f'  [{i}] {o[\"name\"]} ({o[\"id\"]})')
"

# Note: avoid `mapfile`/`readarray` here — they're bash 4+, and macOS still
# ships bash 3.2 by default. Read line-by-line into arrays instead (3.2-safe).
COLUMN_NAMES=()
while IFS= read -r line; do
  COLUMN_NAMES+=("$line")
done < <(echo "$STATUS_FIELD_JSON" | python3 -c "
import json, sys
opts = json.load(sys.stdin)['options']
for o in opts:
    print(o['name'])
")

COLUMN_IDS=()
while IFS= read -r line; do
  COLUMN_IDS+=("$line")
done < <(echo "$STATUS_FIELD_JSON" | python3 -c "
import json, sys
opts = json.load(sys.stdin)['options']
for o in opts:
    print(o['id'])
")

echo
echo "Map each workflow term to one of the columns above by entering its number."
echo "Enter '-' to skip a term (no mapping; the skill will fall back to whatever fits)."
echo

# Note: no `declare -A` (bash 4+ associative arrays don't exist on macOS's
# bash 3.2). Store each mapping in a plain dynamically-named global via
# `printf -v` instead — e.g. MAP_Epics_name / MAP_Epics_id.
map_term() {
  local TERM="$1"
  local IDX
  while true; do
    read -rp "  $TERM: " IDX
    if [[ "$IDX" == "-" ]]; then
      printf -v "MAP_${TERM}_name" '%s' ""
      printf -v "MAP_${TERM}_id" '%s' ""
      return
    fi
    if [[ "$IDX" =~ ^[0-9]+$ ]] && (( IDX >= 1 && IDX <= ${#COLUMN_NAMES[@]} )); then
      printf -v "MAP_${TERM}_name" '%s' "${COLUMN_NAMES[$((IDX-1))]}"
      printf -v "MAP_${TERM}_id" '%s' "${COLUMN_IDS[$((IDX-1))]}"
      return
    fi
    echo "    Invalid; enter a number 1-${#COLUMN_NAMES[@]} or '-'."
  done
}

for TERM in Epics Backlog Prioritized Doing Review Done; do
  map_term "$TERM"
done

echo

# --- Render the board-config.md ----------------------------------------------

render_config() {
  cat <<EOF
# GitHub Projects Board Configuration — $PROJECT_TITLE

Generated by \`setup.sh\` on $(date -u '+%Y-%m-%d %H:%M:%SZ'). Re-run setup if the board structure changes.

## Project

- **Owner:** \`$OWNER\` (\`$OWNER_TYPE\`)
- **Repo:** \`$OWNER/$REPO\`
- **Project number:** \`$PROJECT_NUMBER\`
- **Project ID:** \`$PROJECT_ID\`

## Status Field

- **Field ID:** \`$STATUS_FIELD_ID\`
- **Field type:** \`ProjectV2SingleSelectField\`

## Column Mapping

The skills refer to columns by workflow term. This table maps each term to your actual board column.

| Skill term | Your column | Option ID |
|---|---|---|
| Epics | ${MAP_Epics_name:--} | ${MAP_Epics_id:--} |
| Backlog | ${MAP_Backlog_name:--} | ${MAP_Backlog_id:--} |
| Prioritized | ${MAP_Prioritized_name:--} | ${MAP_Prioritized_id:--} |
| Doing | ${MAP_Doing_name:--} | ${MAP_Doing_id:--} |
| Review | ${MAP_Review_name:--} | ${MAP_Review_id:--} |
| Done | ${MAP_Done_name:--} | ${MAP_Done_id:--} |

## All Status Options (for reference)

EOF
  for i in "${!COLUMN_NAMES[@]}"; do
    echo "- \`${COLUMN_NAMES[$i]}\` → \`${COLUMN_IDS[$i]}\`"
  done

  cat <<'EOF'

## Discovery Commands

Re-run if the board structure changes:

```bash
bash setup.sh
```

Or manually:

```bash
gh api graphql -f query='query{<USER_OR_ORG>(login:"<OWNER>"){projectV2(number:<NUM>){id title fields(first:50){nodes{... on ProjectV2SingleSelectField{id name options{id name}}}}}}}'
```

## Common Operations

Note: always pass `strict=False` when parsing `gh`'s JSON output with Python — issue bodies often contain tabs / control characters that break strict JSON parsing.

### Add issue to board

```bash
ITEM_ID=$(gh project item-add <PROJECT_NUMBER> --owner <OWNER> \
  --url "https://github.com/<OWNER>/<REPO>/issues/<N>" \
  --format json | python3 -c "import json,sys; print(json.load(sys.stdin, strict=False)['id'])")
```

### Move issue to a column

```bash
gh project item-edit \
  --project-id <PROJECT_ID> \
  --id "$ITEM_ID" \
  --field-id <STATUS_FIELD_ID> \
  --single-select-option-id <COLUMN_OPTION_ID>
```

### Find item ID for an existing issue

```bash
ITEM_ID=$(gh project item-list <PROJECT_NUMBER> --owner <OWNER> --limit 100 --format json | \
  python3 -c "import json,sys; d=json.load(sys.stdin, strict=False); print(next(i['id'] for i in d['items'] if i['content'].get('number')==<N>))")
```

### Get all issues in a column

```bash
gh project item-list <PROJECT_NUMBER> --owner <OWNER> --limit 100 --format json | \
  python3 -c "import json,sys; d=json.load(sys.stdin, strict=False); [print(i['content']['number']) for i in d['items'] if i.get('status')=='<COLUMN_NAME>']"
```

### Get sub-issues for an epic

```bash
gh api repos/<OWNER>/<REPO>/issues/<EPIC_NUMBER>/sub_issues | \
  python3 -c "import json,sys; d=json.load(sys.stdin, strict=False); [print(f'#{i[\"number\"]} {i[\"title\"]} ({i[\"state\"]})') for i in d]"
```
EOF
}

# --- Write the configs -------------------------------------------------------

mkdir -p "$SKILL_DIR/references"
render_config > "$SKILL_DIR/references/board-config.md"
echo "  ✓ Wrote $SKILL_DIR/references/board-config.md"

if [[ -n "$BACKLOG_DIR" ]]; then
  render_config > "$BACKLOG_DIR/board-config.md"
  echo "  ✓ Wrote $BACKLOG_DIR/board-config.md"
fi

echo
echo "Setup complete. The skills will pick up these IDs automatically next time they run."
