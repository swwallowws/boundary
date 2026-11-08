#!/usr/bin/env bash
# Sets a project up with boundary: an AGENTS.md from the template when it has none and the hooks
# wired into .claude/settings.json when it has no settings file yet. Never overwrites. When a file
# exists, it prints what to add instead.
#   <boundary>/init.sh <project folder>
set -euo pipefail

boundary="$(cd "$(dirname "$0")" && pwd)"
project="${1:?usage: init.sh <project folder>}"
project="$(cd "$project" && pwd)"

if [ -e "$project/AGENTS.md" ]; then
  echo "AGENTS.md exists: compare it with $boundary/templates/AGENTS.md"
else
  cp "$boundary/templates/AGENTS.md" "$project/AGENTS.md"
  echo "wrote AGENTS.md: fill in the map, the rules you know and the checks you run"
fi

# Hook commands run through a shell, so the path is quoted for a clone whose path has spaces.
settings=$(jq -n --arg b "$boundary" '{
  hooks: {
    PreToolUse: [
      { matcher: "Bash", hooks: [
        { type: "command", command: ("\"" + $b + "/hooks/no-prompts.sh\"") },
        { type: "command", command: ("\"" + $b + "/hooks/user-only.sh\"") }
      ] },
      { matcher: "Bash|Read|Edit|Write|NotebookEdit|Grep|Glob|WebFetch|mcp__.*", hooks: [
        { type: "command", command: ("\"" + $b + "/hooks/private-paths.sh\"") }
      ] }
    ]
  }
}')

mkdir -p "$project/.claude"
if [ -e "$project/.claude/settings.json" ]; then
  echo ".claude/settings.json exists: merge these hooks into it"
  printf '%s\n' "$settings"
else
  printf '%s\n' "$settings" >"$project/.claude/settings.json"
  echo "wrote .claude/settings.json with boundary's hooks"
fi

echo "optional: list deploys and releases in .claude/user-only, private data in .claude/private-paths"
echo "(formats at the top of $boundary/hooks/user-only.sh and private-paths.sh)"
