#!/usr/bin/env bash
# Checks merge-when-green.sh against a stand-in gh that logs every call, so nothing touches
# GitHub: green merges, red doesn't, a branch other pull requests build on stays, a repository
# with no CI merges and says so. Run from anywhere; exits non-zero if any case is wrong.

script="$(cd "$(dirname "$0")" && pwd)/merge-when-green.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0
wrong() { echo "WRONG: $1"; failed=1; }

mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
# What the script and wait-ci ask: the pull request's head, the repository's workflows, the
# commit, its runs, stacked pull requests, then the merge itself.
echo "$*" >>"$GH_LOG"
sha=abcdef1234567890abcdef1234567890abcdef12
case "$1 $2" in
  "pr view") echo "$sha feature" ;;
  "api repos/"*"/actions/workflows") echo "$WORKFLOWS" ;;
  "api repos/"*) echo "{\"sha\": \"$sha\"}" ;;
  "run list") echo "[{\"databaseId\": 1, \"headSha\": \"$sha\", \"status\": \"completed\", \"conclusion\": \"$CI\", \"workflowName\": \"checks\", \"displayTitle\": \"t\", \"url\": \"u\", \"event\": \"pull_request\"}]" ;;
  "pr list") echo "$STACKED" ;;
  "pr merge") ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" GH_LOG="$tmp/gh.log" WAIT_CI_PAUSE_SCALE=0

# try <workflows> <ci conclusion> <stacked count> <args...>: run the script with a fresh log.
try() {
  WORKFLOWS=$1 CI=$2 STACKED=$3
  export WORKFLOWS CI STACKED
  shift 3
  : >"$GH_LOG"
  "$script" "$@" >"$tmp/out" 2>&1
}

try 1 success 0 12 o/r || { cat "$tmp/out"; wrong "green CI didn't merge"; }
grep -q "^pr merge 12 --repo o/r --merge --delete-branch$" "$GH_LOG" || { cat "$GH_LOG"; wrong "green CI didn't merge #12 with a merge commit and its branch deleted"; }

try 1 failure 0 12 o/r && wrong "red CI returned success"
grep -q "^pr merge" "$GH_LOG" && { cat "$GH_LOG"; wrong "red CI still merged"; }

try 1 success 1 12 o/r || { cat "$tmp/out"; wrong "a stacked base didn't merge"; }
grep -q "^pr merge 12 --repo o/r --merge$" "$GH_LOG" || { cat "$GH_LOG"; wrong "a branch another pull request builds on was deleted"; }

try 0 failure 0 3 o/r || { cat "$tmp/out"; wrong "a repository with no CI didn't merge"; }
grep -q "^run list" "$GH_LOG" && { cat "$GH_LOG"; wrong "a repository with no CI still waited for runs"; }
grep -q "has no CI" "$tmp/out" || { cat "$tmp/out"; wrong "a merge with no CI didn't say so"; }

try 1 success 0 12 && wrong "a missing repository wasn't refused"
try 1 success 0 12 r && wrong "a repository without its owner wasn't refused"
[ -s "$GH_LOG" ] && { cat "$GH_LOG"; wrong "a bad repository still called gh"; }

[ "$failed" -eq 0 ] && echo "merge-when-green: all cases right"
exit "$failed"
