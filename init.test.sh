#!/usr/bin/env bash
# Checks that init.sh sets up an empty project and never overwrites one that has its files.
# Run from anywhere; exits non-zero if anything is wrong.

boundary="$(cd "$(dirname "$0")" && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0
wrong() { echo "WRONG: $1"; failed=1; }

mkdir -p "$tmp/fresh"
"$boundary/init.sh" "$tmp/fresh" >"$tmp/out" 2>&1 || wrong "init failed on an empty project"
cmp -s "$boundary/templates/AGENTS.md" "$tmp/fresh/AGENTS.md" || wrong "AGENTS.md isn't the template"
jq -e --arg b "$boundary" '[.hooks.PreToolUse[].hooks[].command] == [("\"" + $b + "/hooks/no-prompts.sh\""), ("\"" + $b + "/hooks/user-only.sh\""), ("\"" + $b + "/hooks/private-paths.sh\"")]' \
  "$tmp/fresh/.claude/settings.json" >"$tmp/out" 2>&1 || wrong "settings.json doesn't wire the three hooks"

# A clone whose path has a space: the wired command still runs the hook.
mkdir -p "$tmp/with space"
cp -R "$boundary/hooks" "$boundary/templates" "$boundary/init.sh" "$tmp/with space/"
mkdir -p "$tmp/spaced"
"$tmp/with space/init.sh" "$tmp/spaced" >"$tmp/out" 2>&1 || wrong "init failed from a path with a space"
hook=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$tmp/spaced/.claude/settings.json")
printf '{"tool_name":"Bash","tool_input":{"command":"git status"}}' >"$tmp/input"
bash -c "$hook \"$tmp/input\"" >"$tmp/out" 2>&1 || wrong "the wired hook didn't run from a path with a space"

mkdir -p "$tmp/kept/.claude"
printf 'mine\n' >"$tmp/kept/AGENTS.md"
printf '{"mine": true}\n' >"$tmp/kept/.claude/settings.json"
"$boundary/init.sh" "$tmp/kept" >"$tmp/out" 2>&1 || wrong "init failed on a project with its files"
[ "$(cat "$tmp/kept/AGENTS.md")" = mine ] || wrong "AGENTS.md was overwritten"
[ "$(cat "$tmp/kept/.claude/settings.json")" = '{"mine": true}' ] || wrong "settings.json was overwritten"
grep -q 'merge these hooks' "$tmp/out" || wrong "no hooks printed to merge"

if [ "$failed" -eq 0 ]; then
  echo "init: all cases right"
fi
exit "$failed"
