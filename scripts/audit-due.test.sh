#!/usr/bin/env bash
# Checks when audit-due.sh says an audit is due. A stand-in gh answers with the last audit issue
# and the merged pull requests a case sets, so nothing touches the network. Run from anywhere;
# exits non-zero if any case is wrong.

script="$(cd "$(dirname "$0")" && pwd)/audit-due.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0
wrong() { echo "WRONG: $1"; failed=1; }

mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
# The two calls audit-due.sh makes: the newest audit issue and the pull requests merged since.
echo "$*" >>"$GH_LOG"
case "$1 $2" in
  "issue list") cat "$GH_ISSUES" ;;
  "pr list") cat "$GH_PRS" ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" GH_LOG="$tmp/gh.log" GH_ISSUES="$tmp/issues" GH_PRS="$tmp/prs"

# audit <days ago> <merged pull requests>: the last audit issue and what merged since.
audit() {
  jq -n --argjson d "$1" '[{number: 7, createdAt: ((now - $d * 86400) | todate)}]' >"$GH_ISSUES"
  jq -n --argjson n "$2" '[range($n) | {number: .}]' >"$GH_PRS"
}
due() {
  "$script" o/r >"$tmp/out" 2>&1 && { cat "$tmp/out"; wrong "$1: said not due"; }
  grep -qF -- "${2:-due for o/r}" "$tmp/out" || { cat "$tmp/out"; wrong "$1: didn't say ${2:-due for o/r}"; }
}
not_due() {
  "$script" o/r >"$tmp/out" 2>&1 || { cat "$tmp/out"; wrong "$1: said due"; }
  grep -qF "not due" "$tmp/out" || { cat "$tmp/out"; wrong "$1: didn't say not due"; }
}

printf '[]\n' >"$GH_ISSUES"
printf '[]\n' >"$GH_PRS"
due "no audit yet" "no issue is labelled audit yet"

audit 40 2
due "40 days, 2 pull requests" "2 merged pull requests and 40 days since the last audit (#7)"

audit 5 20
due "5 days, 20 pull requests" "20 merged pull requests"

audit 5 3
not_due "5 days, 3 pull requests"

# The limits can be set: a busy project audits sooner.
audit 5 3
"$script" o/r 30 3 >"$tmp/out" 2>&1 && wrong "3 pull requests with a limit of 3 said not due"

grep -qF -- "--label audit" "$GH_LOG" || wrong "the last audit wasn't found by its label"
grep -qF -- "merged:>=" "$GH_LOG" || wrong "pull requests weren't counted from the last audit"

"$script" >"$tmp/out" 2>&1
[ $? -eq 2 ] || wrong "no repository given didn't exit 2"

[ "$failed" -eq 0 ] && echo "audit-due: all cases right"
exit "$failed"
