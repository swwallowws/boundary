#!/usr/bin/env bash
# Says whether a repository's next audit is due: when no issue is labelled `audit` yet, or the
# newest one is at least 30 days old, or 15 pull requests have merged since it was opened.
# Exits 1 while one is due, 0 otherwise, so it reads like a check.
#
#   <boundary>/scripts/audit-due.sh <owner/repo> [days] [pull-requests]
#
# An audit is fresh agents reading a project's parts with <boundary>/templates/audit.md. Each
# finding, checked against the code, becomes an issue labelled `audit`; the newest of those
# marks when the last audit ran. Needs a signed-in `gh` and `jq`.

repo=$1
days_due=${2:-30}
prs_due=${3:-15}
if [ -z "$repo" ]; then
  echo "usage: audit-due.sh <owner/repo> [days] [pull-requests]" >&2
  exit 2
fi

issues=$(gh issue list -R "$repo" --label audit --state all --limit 1 --json number,createdAt) || {
  echo "audit: can't read $repo's issues" >&2
  exit 2
}
last=$(printf '%s' "$issues" | jq -r '.[0].createdAt // empty')
if [ -z "$last" ]; then
  echo "audit: due for $repo (no issue is labelled audit yet)"
  exit 1
fi
number=$(printf '%s' "$issues" | jq -r '.[0].number')
age=$(jq -n --arg d "$last" '((now - ($d | fromdateiso8601)) / 86400) | floor')
merged=$(gh pr list -R "$repo" --state merged --search "merged:>=$last" --limit 200 --json number | jq length) || {
  echo "audit: can't read $repo's pull requests" >&2
  exit 2
}
since="$merged merged pull requests and $age days since the last audit (#$number)"
if [ "$age" -ge "$days_due" ] || [ "$merged" -ge "$prs_due" ]; then
  echo "audit: due for $repo: $since"
  exit 1
fi
echo "audit: not due for $repo: $since"
