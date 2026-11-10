#!/usr/bin/env bash
# Checks what no-prompts.sh turns away and what it lets through. Run from anywhere; exits
# non-zero if any case is wrong.

hook="$(cd "$(dirname "$0")" && pwd)/no-prompts.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

# check <blocked|allowed> <command>
check() {
  jq -n --arg command "$2" '{tool_name: "Bash", tool_input: {command: $command}}' >"$tmp/input"
  "$hook" "$tmp/input" >"$tmp/output" 2>&1
  code=$?
  if { [ "$1" = blocked ] && [ "$code" -ne 2 ]; } || { [ "$1" = allowed ] && [ "$code" -ne 0 ]; }; then
    echo "WRONG: expected $1, exit $code: $2"
    failed=1
  fi
}

check blocked 'python -c "print(1)"'
check blocked 'python3 -c "import sys"'
check blocked 'python3 -I -c "x"'
check blocked 'cat <<EOF'
check blocked "cat <<'EOF'"
check blocked 'git commit -F - <<-END'
check blocked 'FOO=1 npm test'
check blocked 'env FOO=1 npm test'
check blocked 'git status && FOO=1 npm test'
check blocked 'cd a; BAR=2 make'
check blocked 'curl -s -o /dev/null https://example.com'
check blocked 'echo $(date)'
check blocked 'echo `date`'
check blocked 'git commit -m "uses `x`"'
check blocked 'diff <(ls a) <(ls b)'
check blocked '.venv/bin/python -c "print(1)"'
check blocked 'python3 -Ic "print(1)"'
check blocked "sed -i '' 's/a/b/' file.js"
check blocked 'sed -n 1,20p file.js'
check blocked 'gsed -i s/a/b/ file.js'
check blocked '/usr/bin/sed -n 3p file.js'
check blocked 'git status; sed -n 1p a'
check blocked 'find . -name x -exec sed -i s/a/b/ {} +'
check blocked 'xargs sed -i s/a/b/'

check allowed 'python3 scripts/check.py'
check allowed 'python3 -I scripts/check.py'
check allowed 'git status'
check allowed 'npm test -- --grep FOO=1'
check allowed 'grep -n "a<b" file.txt'
check allowed 'echo $HOME'
check allowed "git commit -m 'uses \`x\` and <(y)'"
check allowed 'python3 -m pytest -c setup.cfg'
check allowed '.venv/bin/python scripts/run.py'
check allowed 'git commit -m "sed is blocked now"'
check allowed 'grep -n used file.txt'
check allowed 'ls based'

# Without jq the hook refuses instead of reading nothing and letting the call through.
mkdir -p "$tmp/nojq"
printf '{"tool_name":"Bash","tool_input":{"command":"git status"}}' >"$tmp/plain.json"
PATH="$tmp/nojq" "$BASH" "$hook" "$tmp/plain.json" >"$tmp/output" 2>&1
[ $? -eq 2 ] || { echo "WRONG: without jq the hook let a call through"; failed=1; }

if [ "$failed" -eq 0 ]; then
  echo "no-prompts: all cases right"
fi
exit "$failed"
