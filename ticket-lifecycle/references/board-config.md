# GitHub Projects Board Configuration

> **This is a placeholder.** Run `bash setup.sh` (one level up) to auto-populate this file with your project's IDs. Alternatively, fill in the values by hand below.

## Project

- **Owner:** `<OWNER>`
- **Repo:** `<OWNER>/<REPO>`
- **Project number:** `<PROJECT_NUMBER>`
- **Project ID:** `<PROJECT_ID>`

## Status Field

- **Field ID:** `<STATUS_FIELD_ID>`
- **Field type:** `ProjectV2SingleSelectField`

## Column Mapping

The skills refer to columns by workflow term. Map each term to your actual board column.

| Skill term | Your column | Option ID |
|---|---|---|
| Epics | `<EPICS_COLUMN_NAME>` | `<EPICS_OPTION_ID>` |
| Backlog | `<BACKLOG_COLUMN_NAME>` | `<BACKLOG_OPTION_ID>` |
| Prioritized | `<PRIORITIZED_COLUMN_NAME>` | `<PRIORITIZED_OPTION_ID>` |
| Doing | `<DOING_COLUMN_NAME>` | `<DOING_OPTION_ID>` |
| Review | `<REVIEW_COLUMN_NAME>` | `<REVIEW_OPTION_ID>` |
| Done | `<DONE_COLUMN_NAME>` | `<DONE_OPTION_ID>` |

## Discovery Commands

Use these to look up IDs manually if `setup.sh` isn't suitable:

```bash
OWNER=<OWNER>
PROJECT_NUMBER=<PROJECT_NUMBER>

# List projects on the owner
gh project list --owner $OWNER

# Project ID + all single-select fields + their options
# (replace "user" with "organization" if the owner is an org)
gh api graphql -f query="query{
  user(login:\"$OWNER\"){
    projectV2(number:$PROJECT_NUMBER){
      id title
      fields(first:50){nodes{... on ProjectV2SingleSelectField{id name options{id name}}}}
    }
  }
}" | python3 -m json.tool
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
