#!/usr/bin/env bash
# PreToolUse hook for Bash. Turns away commands that would stop on a permission prompt, before
# the prompt reaches the user (see rules/permissions.md). Exit 2 blocks the command and hands the
# message on stderr back to the agent. A JSON file as the first argument stands in for stdin
# when testing; no-prompts.test.sh holds the cases.

here="$(cd "$(dirname "$0")" && pwd)"
rules="$(cd "$here/.." && pwd)/rules/permissions.md"
# Without jq the call can't be read. An empty read would let everything through.
command -v jq >/dev/null 2>&1 || { echo "Blocked: jq isn't installed, so this guard can't read the call. Install jq." >&2; exit 2; }
command=$(jq -r '.tool_input.command // empty' "${1:-/dev/stdin}")

refuse() {
  echo "Blocked before it could ask for permission: $1 Follow $rules: edit files with the Edit or Write tools. Put anything longer than one line in a script file run by its path. Send one plain command per Bash call." >&2
  exit 2
}

# Single-quoted text is literal to the shell, so backticks and <( inside it are only words.
unquoted=$(printf '%s' "$command" | sed "s/'[^']*'//g")

if printf '%s' "$command" | grep -Eq '(^|[^[:alnum:]_.-])python[0-9.]*[[:space:]]+(-[[:alpha:]]+[[:space:]]+)*-[[:alpha:]]*c([[:space:]]|$)'; then
  refuse "inline python (python -c)."
fi
if printf '%s' "$unquoted" | grep -q '`'; then
  refuse "command substitution (backticks)."
fi
if printf '%s' "$unquoted" | grep -Eq '[<>]\('; then
  refuse "process substitution (<(...) or >(...))."
fi
if printf '%s' "$command" | grep -Eq '<<-?[[:space:]]*['"'"'"]?[[:alpha:]_]'; then
  refuse "a heredoc (<<)."
fi
if printf '%s' "$command" | grep -Eq '(^|[;&|])[[:space:]]*(env[[:space:]]+)?[[:alpha:]_][[:alnum:]_]*=[^[:space:]]*[[:space:]]+[^[:space:]]'; then
  refuse "an env-var prefix (VAR=x cmd)."
fi
if printf '%s' "$command" | grep -q '/dev/null'; then
  refuse "/dev/null (write scratch output to a file in the project's scratch folder instead)."
fi
if printf '%s' "$command" | grep -q '\$('; then
  refuse "command substitution (\$(...))."
fi
exit 0
