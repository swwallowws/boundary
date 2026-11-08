#!/usr/bin/env bash
# Checks that check-layout.mjs passes a page whose text changes without moving anything, and
# fails the two ways layouts break: a label that flips and resizes its button, and text that
# wraps and pushes what's below. Skips (and says so) when no Chrome is installed.

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/check-layout.mjs"
pages="$here/check-layout"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0
wrong() { echo "WRONG: $1"; failed=1; }

node "$script" --settle 400 "$pages/still.html" >"$tmp/out" 2>&1
status=$?
if [ "$status" -eq 2 ] && grep -q "no Chrome found" "$tmp/out"; then
  echo "check-layout: skipped, no Chrome on this machine"
  exit 0
fi
[ "$status" -eq 0 ] || { cat "$tmp/out"; wrong "a page that holds still failed"; }

node "$script" --settle 400 "$pages/label-flips.html" >"$tmp/out" 2>&1
[ $? -eq 1 ] || { cat "$tmp/out"; wrong "a label that flips its button's width passed"; }
grep -q 'button#play ("Go → Come back")' "$tmp/out" || { cat "$tmp/out"; wrong "the button that resized isn't named"; }
grep -q 'input#p ("How far") went from' "$tmp/out" || { cat "$tmp/out"; wrong "the slider it pushed isn't named"; }

node "$script" --settle 400 "$pages/text-pushes.html" >"$tmp/out" 2>&1
[ $? -eq 1 ] || { cat "$tmp/out"; wrong "text that pushes the page down passed"; }
grep -q 'after "press Save": p:nth-of-type(2) ("Below everything.")' "$tmp/out" || { cat "$tmp/out"; wrong "the paragraph pushed down isn't named"; }

node "$script" --settle 400 "$pages/writes.html" >"$tmp/out" 2>&1
[ $? -eq 0 ] || { cat "$tmp/out"; wrong "a button marked data-no-press was pressed"; }
grep -q "held back (never sent): POST https://example.invalid/messages" "$tmp/out" || { cat "$tmp/out"; wrong "a request that writes wasn't held back and named"; }

node "$script" >"$tmp/out" 2>&1
[ $? -eq 2 ] || wrong "no page given didn't exit 2"

[ "$failed" -eq 0 ] && echo "check-layout: all cases right"
exit "$failed"
