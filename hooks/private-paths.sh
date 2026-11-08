#!/usr/bin/env bash
# PreToolUse hook for every tool that reads, writes or fetches (matcher
# "Bash|Read|Edit|Write|NotebookEdit|Grep|Glob|WebFetch|mcp__.*"). Turns away the usual ways an
# agent reaches what a project keeps from it. Exit 2 blocks the call and hands the message on
# stderr back to the agent. A JSON file as the first argument stands in for stdin when testing;
# private-paths.test.sh holds the cases.
#
# What is private is listed in `.claude/private-paths` files. Lists are read from the folder the
# session started in ($CLAUDE_PROJECT_DIR), from the repository the session runs in and from
# every folder above either. One rule per line:
#
#   path: <regex>     a file, folder, route or URL, matched against the command and against any
#                     path, pattern, glob or URL a tool names
#   command: <regex>  a command that reads private data, matched against each part of a command
#                     (split at ; & |) that isn't a git command, so `git log scripts/export`
#                     stays open
#   tool: <regex>     a tool, by name (an MCP tool that serves the data)
#   folder: <name>    a folder that holds private files next to open ones: no search, listing
#                     or copy of all of it and no recursive search that could reach it
#
# Regexes are extended (grep -E). This guard reads text, so it catches honest mistakes. A script
# that opens files on its own gets past it. Data that truly mustn't be read needs encryption or
# permissions the agent can't change.

# Without jq the call can't be read. An empty read would let everything through.
command -v jq >/dev/null 2>&1 || { echo "Blocked: jq isn't installed, so this guard can't read the call. Install jq." >&2; exit 2; }
input=$(jq -c '.' "${1:-/dev/stdin}")
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
# Whatever else the call names: a file, a search path, pattern or glob, a URL.
named=$(printf '%s' "$input" | jq -r '[.tool_input.file_path, .tool_input.notebook_path, .tool_input.path, .tool_input.pattern, .tool_input.glob, .tool_input.url] | map(select(. != null)) | join(" ")')
all="$command $named"

refuse() {
  echo "Blocked: $1 This project keeps it from agents. Work from fixtures or ask the user." >&2
  exit 2
}

# A whole-folder search, listing or copy reaches every file in it without naming one.
folder_rules() {
  local name=$1
  local quoted whole
  quoted=$(printf '%s' "$name" | sed 's/[.[\*^$()+?{|]/\\&/g')
  # The folder itself, quoted or not, alone or as `name/`, `name/.` or `name/*`.
  whole="[\"']?${quoted}[\"']?(/\\.?)?(\\*[^[:space:]]*)?([[:space:]\"']|\$)"
  case "$tool" in
    Grep|Glob)
      if printf '%s' "$named" | grep -Eq "(^|[[:space:]/])${whole}"; then
        refuse "a search over all of $name."
      fi
      ;;
  esac
  # Naming the folder to leave it out (--exclude-dir, find's -path or -name before -prune) is fine.
  local rest
  rest=$(printf '%s' "${command//--exclude-dir=$name/}" | sed -E 's/-(path|ipath|name|iname|wholename)[[:space:]]+[^[:space:]]+([[:space:]]+-prune)/\2/g')
  if printf '%s' "$command" | grep -Eq '(^|[[:space:]/])(grep|egrep|rg|ag|ack|find|tar|zip|cp|rsync|cat|strings|ls|du|xargs)[[:space:]]' &&
     printf '%s' "$rest" | grep -Eq "(^|[[:space:]/=])${whole}"; then
    refuse "a command over all of $name."
  fi
  # A plain recursive grep ignores .gitignore, so from any folder above it reaches the folder.
  if printf '%s' "$command" | grep -Eq '(^|[[:space:]/])e?grep[[:space:]]+([^|;&]*[[:space:]])?(-[[:alpha:]]*[rR][[:alpha:]]*|--recursive|--dereference-recursive)([[:space:]]|$)' &&
     ! printf '%s' "$command" | grep -qF -- "--exclude-dir=$name"; then
    refuse "a recursive grep that could reach $name (add --exclude-dir=$name)."
  fi
  # So does an rg that skips .gitignore, unless a glob leaves the folder out.
  if printf '%s' "$command" | grep -Eq '(^|[[:space:]/])rg[[:space:]]+([^|;&]*[[:space:]])?(-[[:alpha:]]*u[[:alpha:]]*|--no-ignore[^[:space:]]*|--unrestricted)([[:space:]]|$)' &&
     ! printf '%s' "$command" | grep -qF -- "!$name"; then
    refuse "an rg that skips .gitignore and could reach $name (add -g '!$name')."
  fi
  # And a find that runs a command on what it finds, unless it names the folder (to prune it).
  if printf '%s' "$command" | grep -Eq '(^|[[:space:]/])find[[:space:]][^;&|]*-(exec|execdir|ok|okdir)([[:space:]]|$)|(^|[[:space:]/])find[[:space:]][^;&]*\|[[:space:]]*xargs' &&
     ! printf '%s' "$command" | grep -qF -- "$name"; then
    refuse "a find that runs a command on files it could reach in $name (prune $name)."
  fi
}

# Every .claude/private-paths from these folders up to the root, each read once.
lists=()
seen=' '
add_lists() {
  local dir=$1
  while [ -n "$dir" ]; do
    case "$seen" in *" $dir "*) ;; *)
      seen="$seen$dir "
      [ -f "$dir/.claude/private-paths" ] && lists+=("$dir/.claude/private-paths")
    esac
    [ "$dir" = / ] && break
    dir=$(dirname "$dir")
  done
}
[ -n "$CLAUDE_PROJECT_DIR" ] && add_lists "$CLAUDE_PROJECT_DIR"
top=$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null)
[ -n "$top" ] && add_lists "$top"

parts=$(printf '%s' "$command" | tr ';&|' '\n\n\n')
for list in "${lists[@]}"; do
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    kind=${line%%: *}
    rule=${line#*: }
    case "$kind" in
      path)
        if printf '%s' "$all" | grep -Eq -- "$rule"; then
          refuse "a private path ($rule)."
        fi
        ;;
      command)
        if printf '%s\n' "$parts" | grep -Ev '^[[:space:]]*git[[:space:]]' | grep -Eq -- "$rule"; then
          refuse "a command that reads private data ($rule)."
        fi
        ;;
      tool)
        if printf '%s' "$tool" | grep -Eq -- "^($rule)\$"; then
          refuse "a tool that serves private data ($tool)."
        fi
        ;;
      folder)
        folder_rules "$rule"
        ;;
    esac
  done <"$list"
done
exit 0
