#!/usr/bin/env bash
# Checks that spec-checks.sh finds requirements without a check and passes complete specs. Run
# from anywhere; exits non-zero if any case is wrong.

script="$(cd "$(dirname "$0")" && pwd)/spec-checks.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0
wrong() { echo "WRONG: $1"; failed=1; }

cat >"$tmp/complete.md" <<'EOF'
# Sync

## Requirements

- R1. Older phones keep syncing. Check: `cargo test -p core serde`
- R2. The seal never leaves the phone. Check: manual: read the outbox rows
- R3. Nothing reads the logs yet. Check: none, no log reader exists

## Passes

- 1. Fields: R1 (no check needed here, this isn't a requirement)
EOF

cat >"$tmp/gaps.md" <<'EOF'
# Sync

## Requirements

- R1. Older phones keep syncing. Check: `cargo test -p core serde`
- R2. The seal never leaves the phone.
* R3. A wrong passphrase opens nothing. Check:

## Today

- a list item outside Requirements is never a requirement
EOF

"$script" "$tmp/complete.md" >"$tmp/out" 2>&1 || { cat "$tmp/out"; wrong "a complete spec failed"; }

"$script" "$tmp/gaps.md" >"$tmp/out" 2>&1 && wrong "a spec with gaps passed"
grep -q ":6: no check: R2" "$tmp/out" || { cat "$tmp/out"; wrong "R2 (no check at all) not reported"; }
grep -q ":7: no check: R3" "$tmp/out" || { cat "$tmp/out"; wrong "R3 (an empty Check:) not reported"; }
[ "$(grep -c "no check" "$tmp/out")" -eq 2 ] || { cat "$tmp/out"; wrong "reported something outside Requirements"; }

"$script" "$tmp/missing.md" >"$tmp/out" 2>&1 && wrong "a missing file passed"

printf '# Prose only\n\nEverything that must hold is in paragraphs.\n' >"$tmp/prose.md"
"$script" "$tmp/prose.md" >"$tmp/out" 2>&1 && wrong "a spec with no Requirements section passed"
grep -q "no ## Requirements section" "$tmp/out" || { cat "$tmp/out"; wrong "a spec with no Requirements section wasn't named"; }
"$script" "$(dirname "$script")/../templates/design.md" >"$tmp/out" 2>&1 || { cat "$tmp/out"; wrong "the template's own example requirements fail"; }

[ "$failed" -eq 0 ] && echo "spec-checks: all cases right"
exit "$failed"
