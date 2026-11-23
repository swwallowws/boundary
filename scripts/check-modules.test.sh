#!/usr/bin/env bash
# Checks that check-modules.mjs fails a module that doesn't parse, an import or export in it
# included, and passes ones that do. Run from anywhere; exits non-zero if any case is wrong.

script="$(cd "$(dirname "$0")" && pwd)/check-modules.mjs"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0
wrong() { echo "WRONG: $1"; failed=1; }

mkdir -p "$tmp/good/pages" "$tmp/good/node_modules/x" "$tmp/bad/pages"
printf 'import { b } from "./b.js";\nexport const a = () => b;\n' >"$tmp/good/a.js"
printf 'export const b = 1;\n' >"$tmp/good/b.js"
printf 'export default await Promise.resolve(1);\n' >"$tmp/good/pages/page.mjs"
# Never read: another package's code.
printf 'this is not javascript (\n' >"$tmp/good/node_modules/x/index.js"
printf 'not code, never read\n' >"$tmp/good/notes.txt"

node "$script" "$tmp/good" >"$tmp/out" 2>&1 && grep -qF "3 checked, 0 broken" "$tmp/out" \
  || { cat "$tmp/out"; wrong "modules that parse failed, or weren't all counted"; }

# The trap this script exists for: `node --check` passes this file, since it has an export.
printf 'export function f() { return 1 +; }\n' >"$tmp/bad/pages/broken.js"
printf 'export const fine = 1;\n' >"$tmp/bad/fine.js"
node "$script" "$tmp/bad" >"$tmp/out" 2>&1 && wrong "a broken module with an export passed"
grep -qF "broken.js doesn't parse" "$tmp/out" || { cat "$tmp/out"; wrong "the broken module wasn't named"; }
grep -qF "fine.js" "$tmp/out" && { cat "$tmp/out"; wrong "a module that parses was named"; }

node "$script" "$tmp/good" "$tmp/missing" >"$tmp/out" 2>&1 && wrong "a missing folder passed"
grep -qF "no folder" "$tmp/out" || { cat "$tmp/out"; wrong "the missing folder wasn't named"; }

node "$script" >"$tmp/out" 2>&1
[ $? -eq 2 ] || wrong "no folder given didn't exit 2"

[ "$failed" -eq 0 ] && echo "check-modules: all cases right"
exit "$failed"
