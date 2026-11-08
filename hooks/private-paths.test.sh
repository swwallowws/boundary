#!/usr/bin/env bash
# Checks what private-paths.sh turns away and what it lets through, with a list modelled on a
# journal app whose entries stay with the user. Run from anywhere; exits non-zero if any case is
# wrong.

hook="$(cd "$(dirname "$0")" && pwd)/private-paths.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/ws/.claude" "$tmp/ws/app" "$tmp/elsewhere"
cat >"$tmp/ws/.claude/private-paths" <<'EOF'
# Journal entries stay with the user.
path: /api/v1/(entries|sync)
path: \.local/(export|entr)
command: (^|[[:space:]/])(scripts/)?(export-entries|read-entries)([[:space:]]|$)
command: (sqlite3|ssh|psql).*[Ee]ntries
tool: mcp__.*[Ee]ntr.*
folder: .local
EOF
export CLAUDE_PROJECT_DIR="$tmp/ws/app"
failed=0

# check <blocked|allowed> <tool> <field> <value>
check() {
  jq -n --arg tool "$2" --arg field "$3" --arg value "$4" --arg cwd "$tmp/ws/app" \
    '{tool_name: $tool, cwd: $cwd, tool_input: {($field): $value}}' >"$tmp/input"
  "$hook" "$tmp/input" >"$tmp/output" 2>&1
  code=$?
  if { [ "$1" = blocked ] && [ "$code" -ne 2 ]; } || { [ "$1" = allowed ] && [ "$code" -ne 0 ]; }; then
    echo "WRONG: expected $1, exit $code: $2 $3=$4"
    failed=1
  fi
}

# Named outright (the list sits in the workspace, above the project).
check blocked Bash command 'curl http://host/api/v1/entries'
check blocked WebFetch url 'http://host/api/v1/sync'
check blocked Read file_path '/x/app/.local/entries/one.json'
check blocked Read file_path '.local/export/list.txt'
check blocked Edit file_path '.local/entries/one.json'
check blocked Write file_path '.local/entries/new.json'
check blocked Bash command 'ls .local/entries-old'
check blocked Bash command 'scripts/export-entries'
check blocked Bash command 'git status && scripts/export-entries'
check blocked Bash command 'ssh host sqlite3 app.db "select * from entries"'
check blocked mcp__app__list_entries query 'x'

# Reached without being named.
check blocked Grep path '.local'
check blocked Grep path '/x/app/.local/'
check blocked Grep glob '.local/**'
check blocked Glob pattern '.local/**'
check blocked Bash command 'grep -rl love .local'
check blocked Bash command 'cat .local/*'
check blocked Bash command 'cat ".local"/*'
check blocked Bash command 'cp -R .local/. /x/copy'
check blocked Bash command 'ls .local'
check blocked Bash command 'find /x/app/.local -name a'
check blocked Bash command 'find . -type f -exec cat {} +'
check blocked Bash command 'grep -r love /x/app'
check blocked Bash command 'grep -nR love .'
check blocked Bash command 'rg --no-ignore love /x/app'
check blocked Bash command 'rg -uu love'
check blocked Bash command "rg --no-ignore -g '.local/**' love ."

# Ordinary work stays open.
check allowed Read file_path '/x/app/.local/mockups/garden-1.html'
check allowed Grep path '.local/mockups'
check allowed Grep path 'server/crates'
check allowed Grep glob '*.rs'
check allowed Edit file_path 'src/entries.rs'
check allowed Bash command 'ls .local/mockups'
check allowed Bash command 'grep -n entries server/src/entries.rs'
check allowed Bash command 'grep -r --exclude-dir=.local todo .'
check allowed Bash command "rg -uu -g '!.local' todo"
check allowed Bash command "find . -path ./.local -prune -o -type f -exec wc -l {} +"
check allowed Bash command 'find src -name "*.rs"'
check allowed Bash command 'rg entries server'
check allowed Bash command 'git log scripts/export-entries'
check allowed Bash command 'cargo test --workspace'
check allowed mcp__app__list_paths query 'x'

# Outside the workspace, nothing is private.
unset CLAUDE_PROJECT_DIR
jq -n --arg cwd "$tmp/elsewhere" '{tool_name: "Bash", cwd: $cwd, tool_input: {command: "curl http://host/api/v1/entries"}}' >"$tmp/input"
"$hook" "$tmp/input" >"$tmp/output" 2>&1 || { echo "WRONG: blocked outside the workspace"; failed=1; }

# A list in the repository the session runs in counts, with no workspace list above it.
git init -q -b main "$tmp/repo"
mkdir -p "$tmp/repo/.claude" "$tmp/repo/sub"
printf '%s\n' 'path: \.secret/' >"$tmp/repo/.claude/private-paths"
jq -n --arg cwd "$tmp/repo/sub" '{tool_name: "Read", cwd: $cwd, tool_input: {file_path: ".secret/a.txt"}}' >"$tmp/input"
"$hook" "$tmp/input" >"$tmp/output" 2>&1
[ $? -eq 2 ] || { echo "WRONG: the repository's own list didn't count"; failed=1; }
jq -n --arg cwd "$tmp/elsewhere" '{tool_name: "Read", cwd: $cwd, tool_input: {file_path: ".secret/a.txt"}}' >"$tmp/input"
"$hook" "$tmp/input" >"$tmp/output" 2>&1
[ $? -eq 0 ] || { echo "WRONG: the repository's list reached outside it"; failed=1; }

# Without jq the hook refuses instead of reading nothing and letting the call through.
mkdir -p "$tmp/nojq"
printf '{"tool_name":"Read","tool_input":{"file_path":"src/x.rs"}}' >"$tmp/plain.json"
PATH="$tmp/nojq" "$BASH" "$hook" "$tmp/plain.json" >"$tmp/output" 2>&1
[ $? -eq 2 ] || { echo "WRONG: without jq the hook let a call through"; failed=1; }

if [ "$failed" -eq 0 ]; then
  echo "private-paths: all cases right"
fi
exit "$failed"
