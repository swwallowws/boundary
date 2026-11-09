#!/usr/bin/env bash
# PreToolUse hook for Bash. Turns away what only the user does and what collides with another
# session. Exit 2 blocks the command and hands the message on stderr back to the agent. Commands
# the user runs themselves with `!` don't pass through here. A JSON file as the first argument
# stands in for stdin when testing; user-only.test.sh holds the cases.
#
# Merging a pull request is always the user's, through gh or boundary's own
# scripts/merge-when-green.sh. Anything else (deploys, releases, pushes to a
# public repo) is listed in a `.claude/user-only` file. Lists are read from the folder the session
# started in ($CLAUDE_PROJECT_DIR), from the repository the command runs in, from any repository
# it names with `git -C`, from a worktree's main checkout and from every folder above these. So
# a workspace's list covers all of its projects and a repository's list covers its worktrees.
# A `.claude/user-only.repo` list, same format, holds only for the repository it sits in.
# One command per line, `<what>: <extended regex>`, matched at the start of a command:
#
#   deploying: nixos-rebuild([[:space:]]|$)
#   releasing: ([^[:space:];&|]*/)?release\.sh([[:space:]]|$)
#
# Only commands at the start of a line of work count (the start or after ; & |), so a commit
# message that mentions one of these isn't taken for it.

# Without jq the call can't be read. An empty read would let everything through.
command -v jq >/dev/null 2>&1 || { echo "Blocked: jq isn't installed, so this guard can't read the call. Install jq." >&2; exit 2; }
input=$(jq -c '.' "${1:-/dev/stdin}")
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')

refuse() {
  echo "Blocked: $1" >&2
  exit 2
}

# A command may come after sudo, a wrapper (env, command, exec, nohup, time) or a shell that runs
# it (bash x.sh, sh -c "x"), so those count as its start too.
assign='[[:alpha:]_][[:alnum:]_]*=[^[:space:];&|]*[[:space:]]+'
at_start="(^|[;&|])[[:space:]]*(sudo[[:space:]]+)?(${assign})*((env|command|exec|nohup|time)[[:space:]]+(${assign})*)*((ba|z|da|k)?sh[[:space:]]+(-[[:alpha:]]+[[:space:]]+)*[\"']?)?"
gh='([^[:space:];&|]*/)?gh'

if printf '%s' "$command" | grep -Eq "${at_start}${gh}[[:space:]]+pr[[:space:]]+merge([[:space:]]|\$)" ||
   printf '%s' "$command" | grep -Eq "${at_start}${gh}[[:space:]]+api[[:space:]][^;&|]*(pulls/[0-9]+/merge|mergePullRequest)" ||
   printf '%s' "$command" | grep -Eq "${at_start}([^[:space:];&|]*/)?merge-when-green\.sh([[:space:]]|\$)"; then
  refuse "merging is the user's. Give them the exact command to run."
fi

# `cd <dir> && ...` moves where the rest runs.
quoted_dir='("[^"]+"|'"'"'[^'"'"']+'"'"'|[^[:space:];&|]+)'
moved=$(printf '%s' "$command" | grep -Eo "${at_start}cd[[:space:]]+${quoted_dir}" | head -n 1 | sed -E 's/.*cd[[:space:]]+//; s/^["'"'"']//; s/["'"'"']$//')
case "$moved" in
  '') base=${cwd:-.} ;;
  /*) base=$moved ;;
  *) base="${cwd:-.}/$moved" ;;
esac

# Every .claude/user-only from these folders up to the root, each read once.
lists=()
seen=' '
add_lists() {
  local dir=$1
  while [ -n "$dir" ]; do
    case "$seen" in *" $dir "*) ;; *)
      seen="$seen$dir "
      [ -f "$dir/.claude/user-only" ] && lists+=("$dir/.claude/user-only")
    esac
    [ "$dir" = / ] && break
    dir=$(dirname "$dir")
  done
}
# A repository's lists: its own folder and, for a linked worktree, its main checkout's, since a
# list kept out of git isn't in the worktree.
add_repo_lists() {
  local top common
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)
  [ -n "$top" ] || return 0
  add_lists "$top"
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  [ -n "$common" ] && add_lists "$(dirname "$common")"
}
[ -n "$CLAUDE_PROJECT_DIR" ] && add_lists "$CLAUDE_PROJECT_DIR"
add_repo_lists "$base"
# And every repository the command names with `git -C <dir>`, wherever it runs from.
named_dirs=$(printf '%s' "$command" | grep -Eo "git([[:space:]]+-c[[:space:]]+[^[:space:];&|]+)*[[:space:]]+-C[[:space:]]+${quoted_dir}" | sed -E 's/.*-C[[:space:]]+//; s/^["'"'"']//; s/["'"'"']$//')
while IFS= read -r named; do
  [ -n "$named" ] || continue
  case "$named" in /*) ;; *) named="$base/$named" ;; esac
  add_repo_lists "$named"
done <<EOF
$named_dirs
EOF
# A `.claude/user-only.repo` list holds only for its own repository: a workspace that is itself a
# repo can guard its own main without guarding every project folder inside it. It's read for the
# repository the command acts on (the one `git -C` names, else the one it runs in) and that
# repository's main checkout, never for folders above them.
add_repo_only() {
  local top common
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)
  [ -n "$top" ] || return 0
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  for dir in "$top" "$(dirname "${common:-$top/.git}")"; do
    case "$seen" in *" repo:$dir "*) continue ;; esac
    seen="${seen}repo:$dir "
    [ -f "$dir/.claude/user-only.repo" ] && lists+=("$dir/.claude/user-only.repo")
  done
}
if [ -n "$named_dirs" ]; then
  while IFS= read -r named; do
    [ -n "$named" ] || continue
    case "$named" in /*) ;; *) named="$base/$named" ;; esac
    add_repo_only "$named"
  done <<EOF
$named_dirs
EOF
else
  add_repo_only "$base"
fi
for list in "${lists[@]}"; do
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    what=${line%%: *}
    pattern=${line#*: }
    if printf '%s' "$command" | grep -Eq "${at_start}(${pattern})"; then
      refuse "$what is the user's. Give them the exact command to run."
    fi
  done <"$list"
done

# A branch change in a repository's main checkout pulls the ground from under any other session
# working there. A linked worktree belongs to one session, so it may do as it likes.
options="([[:space:]]+-C[[:space:]]+${quoted_dir}|[[:space:]]+-c[[:space:]]+[^[:space:];&|]+)*"
switching="([^[:space:];&|]*/)?git${options}[[:space:]]+(switch|checkout)([[:space:]]|\$)"
if printf '%s' "$command" | grep -Eq "${at_start}${switching}|${at_start}${gh}[[:space:]]+pr[[:space:]]+checkout([[:space:]]|\$)"; then
  part=$(printf '%s' "$command" | grep -Eo "${switching}[^;&|]*" | head -n 1)
  # Restoring files leaves the branch alone: `git checkout -- file`, `git checkout .`.
  restores=0
  if printf '%s' "$part" | grep -Eq 'checkout[^;&|]*[[:space:]]--([[:space:]]|$)' ||
     printf '%s' "$part" | grep -Eq 'checkout([[:space:]]+-[^[:space:]]+)*[[:space:]]+\.(/[^[:space:]]*)?([[:space:]]|$)'; then
    restores=1
  fi
  if [ "$restores" -eq 0 ]; then
    dir=$(printf '%s' "$part" | grep -Eo "[-]C[[:space:]]+${quoted_dir}" | tail -n 1 | sed -E 's/^-C[[:space:]]+//; s/^["'"'"']//; s/["'"'"']$//')
    case "$dir" in
      /*) ;;
      '') dir=$base ;;
      *) dir="$base/$dir" ;;
    esac
    git_dir=$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null)
    common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    if [ -n "$git_dir" ] && [ "$git_dir" = "$common" ]; then
      repo=$(git -C "$dir" rev-parse --show-toplevel)
      refuse "another session may be working in this checkout, so branches don't change here. Use your own worktree: git -C $repo worktree add -b <branch> $(dirname "$repo")/.worktrees/<name> origin/main"
    fi
  fi
fi
exit 0
