#!/usr/bin/env bash
# Checks which commit wait-ci.mjs asks GitHub about. A stand-in gh answers from a list of commits
# "GitHub has" and logs every call, so nothing touches the network. Run from anywhere; exits
# non-zero if any case is wrong.

script="$(cd "$(dirname "$0")" && pwd)/wait-ci.mjs"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0
wrong() { echo "WRONG: $1"; failed=1; }

mkdir -p "$tmp/bin" "$tmp/elsewhere"
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
# The calls wait-ci.mjs makes: a commit lookup, and a run list by commit or on main.
echo "$*" >>"$GH_LOG"
if [ "$1" = api ]; then
  want=${2##*/}
  # Like GitHub: HEAD is the default branch's head, whatever the caller has checked out.
  [ "$want" != HEAD ] || want=$MAIN_SHA
  full=$(grep -i "^$want" "$GH_KNOWN" | head -n 1)
  [ -n "$full" ] || { echo "HTTP 422: No commit found for SHA: $want" >&2; exit 1; }
  echo "{\"sha\": \"$full\"}"
  exit 0
fi
if [ "$1 $2" = "run list" ]; then
  sha=$(printf '%s\n' "$@" | grep -A1 -x -- --commit | tail -n 1)
  [ "$sha" != --commit ] || sha=$MAIN_SHA
  echo "[{\"databaseId\": 1, \"headSha\": \"$sha\", \"status\": \"completed\", \"conclusion\": \"success\", \"workflowName\": \"checks\", \"displayTitle\": \"run for $sha\", \"url\": \"u\", \"event\": \"push\"}]"
  exit 0
fi
echo "unexpected gh call: $*" >&2
exit 1
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" GH_LOG="$tmp/gh.log" GH_KNOWN="$tmp/known" WAIT_CI_PAUSE_SCALE=0

# A checkout on a branch one commit ahead of main. GitHub has both commits, and main's head is
# also what GitHub would give for HEAD.
git init -q -b main "$tmp/repo"
g() { git -C "$tmp/repo" -c user.name=t -c user.email=t@example.com "$@"; }
g commit -q --allow-empty -m one
main=$(g rev-parse HEAD)
g switch -q -c work
g commit -q --allow-empty -m two
work=$(g rev-parse HEAD)
printf '%s\n%s\nabcdef1234567890abcdef1234567890abcdef12\n' "$main" "$work" >"$tmp/known"
export MAIN_SHA=$main

# run <dir> <args...>: wait-ci from that folder, with a fresh log.
run() { : >"$GH_LOG"; (cd "$1" && shift && node "$script" "$@") >"$tmp/out" 2>&1; }

run "$tmp/repo" --sha HEAD o/r || { cat "$tmp/out"; wrong "--sha HEAD on a branch failed"; }
grep -q "commits/$work" "$GH_LOG" || { cat "$GH_LOG"; wrong "--sha HEAD didn't ask GitHub about this checkout's HEAD"; }
grep -q "commits/HEAD" "$GH_LOG" && wrong "--sha HEAD went to GitHub as HEAD, which GitHub reads as main"
grep -q "run for $main" "$tmp/out" && { cat "$tmp/out"; wrong "--sha HEAD on a branch reported main's run"; }

run "$tmp/repo" --sha main o/r || { cat "$tmp/out"; wrong "--sha main failed"; }
grep -q "commits/$main" "$GH_LOG" || { cat "$GH_LOG"; wrong "--sha main wasn't resolved in the checkout"; }

run "$tmp/repo" --sha abcdef1 o/r || { cat "$tmp/out"; wrong "a short hash the checkout doesn't have failed"; }
grep -q "commits/abcdef1" "$GH_LOG" || { cat "$GH_LOG"; wrong "a short hash the checkout doesn't have didn't go to GitHub"; }

run "$tmp/elsewhere" --sha HEAD o/r
[ $? -eq 2 ] || { cat "$tmp/out"; wrong "--sha HEAD outside a checkout wasn't refused"; }
[ -s "$GH_LOG" ] && { cat "$GH_LOG"; wrong "--sha HEAD outside a checkout still asked GitHub"; }

run "$tmp/repo" --sha no-such-branch o/r
[ $? -eq 2 ] || { cat "$tmp/out"; wrong "an unknown name wasn't refused"; }

g commit -q --allow-empty -m "three, never pushed"
run "$tmp/repo" --sha HEAD o/r && { cat "$tmp/out"; wrong "a commit GitHub doesn't have passed"; }
grep -q "GitHub has no commit" "$tmp/out" || { cat "$tmp/out"; wrong "a commit GitHub doesn't have wasn't named"; }

[ "$failed" -eq 0 ] && echo "wait-ci: all cases right"
exit "$failed"
