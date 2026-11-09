#!/usr/bin/env bash
# Merges a pull request once its CI is green, with a merge commit. The user's to run: the
# user-only hook turns it away from agents, as it does `gh pr merge`.
#   scripts/merge-when-green.sh <number> <owner/repo>
#
# 1. Reads the pull request's head commit and branch.
# 2. A repository with no workflows has nothing to wait for: it says nothing checked the pull
#    request and goes on. Otherwise wait-ci.mjs waits for every run on that commit, and anything
#    but green stops here.
# 3. Keeps the branch when another open pull request is based on it, since deleting a pull
#    request's base branch closes it. Otherwise deletes the branch after merging.
# A required check on GitHub holds against every way of merging; this holds only when it's used.
# Private repositories can't require checks without a paid plan, which is why it exists.

pr=$1
repo=$2
if [ -z "$pr" ] || [ -z "$repo" ] || [ "${repo#*/}" = "$repo" ]; then
  echo "usage: merge-when-green.sh <number> <owner/repo>" >&2
  exit 2
fi
here="$(cd "$(dirname "$0")" && pwd)"

head=$(gh pr view "$pr" --repo "$repo" --json headRefOid,headRefName --jq '.headRefOid + " " + .headRefName') || exit 1
sha=${head%% *}
branch=${head#* }

workflows=$(gh api "repos/$repo/actions/workflows" --jq .total_count) || exit 1
if [ "$workflows" -eq 0 ]; then
  echo "$repo has no CI, so nothing checked #$pr before this merge." >&2
elif ! node "$here/wait-ci.mjs" --sha "$sha" "$repo"; then
  echo "Not merging #$pr: its CI isn't green." >&2
  exit 1
fi

stacked=$(gh pr list --repo "$repo" --base "$branch" --state open --json number --jq length) || exit 1
if [ "$stacked" -gt 0 ]; then
  echo "Keeping $branch: $stacked open pull request(s) build on it." >&2
  exec gh pr merge "$pr" --repo "$repo" --merge
fi
exec gh pr merge "$pr" --repo "$repo" --merge --delete-branch
