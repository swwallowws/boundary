#!/usr/bin/env bash
# PreToolUse hook for Bash. Reads what would go out on a public GitHub repository, where anyone
# can read it, and turns it away when it holds a private word. Exit 2 blocks the command and
# hands the message on stderr back to the agent. A JSON file as the first argument stands in for
# stdin when testing; public-posts.test.sh holds the cases.
#
# On a public repository:
# - Issues and pull requests (made, edited, commented on, reviewed, closed with a comment) and
#   writes to them through `gh api` go out when their text holds no private word: the command's
#   own text and any file it hands over (--body-file, -F, --input).
# - A push goes out when the commits it adds (their messages and their changes) hold none.
# - Releases, a public gist and a repository made or turned public are always the user's.
# On a private repository nothing is checked. When the hook can't tell whether a repository is
# public, it refuses.
#
# Private words are the home folder's path and every line of a `.claude/private-words` list,
# matched ignoring case, read from the folder the session started in ($CLAUDE_PROJECT_DIR) and
# the repository the command runs in, with the folders above them. One word or phrase per line;
# blank lines and lines starting with # are skipped:
#
#   # names, emails, places, private project terms
#   Jane Doe
#   jane@example.com
#
# The repository is the one `-R`/`--repo` names, the one a `gh api` path names, else the one the
# command runs in (its origin, or for a push the remote it names). Whether it is public comes
# from `gh repo view`. Remotes outside GitHub aren't checked.

# Without jq the call can't be read. An empty read would let everything through.
command -v jq >/dev/null 2>&1 || { echo "Blocked: jq isn't installed, so this guard can't read the call. Install jq." >&2; exit 2; }
input=$(jq -c '.' "${1:-/dev/stdin}")
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')

refuse() {
  echo "Blocked: $1" >&2
  exit 2
}

# As in user-only.sh: a command counts at the start of a line of work, after sudo, a wrapper or a
# shell that runs it.
assign='[[:alpha:]_][[:alnum:]_]*=[^[:space:];&|]*[[:space:]]+'
at_start="(^|[;&|])[[:space:]]*(sudo[[:space:]]+)?(${assign})*((env|command|exec|nohup|time)[[:space:]]+(${assign})*)*((ba|z|da|k)?sh[[:space:]]+(-[[:alpha:]]+[[:space:]]+)*[\"']?)?"
gh='([^[:space:];&|]*/)?gh'
quoted_dir='("[^"]+"|'"'"'[^'"'"']+'"'"'|[^[:space:];&|]+)'
unquote() { sed -E 's/^["'"'"']//; s/["'"'"']$//'; }

# `cd <dir> && ...` moves where the rest runs.
moved=$(printf '%s' "$command" | grep -Eo "${at_start}cd[[:space:]]+${quoted_dir}" | head -n 1 | sed -E 's/.*cd[[:space:]]+//' | unquote)
case "$moved" in
  '') base=${cwd:-.} ;;
  /*) base=$moved ;;
  *) base="${cwd:-.}/$moved" ;;
esac

# The private words: the home folder's path and the lines of every .claude/private-words list
# from the session's folder and the command's repository up to the root.
words=$(mktemp)
trap 'rm -f "$words"' EXIT
case "$HOME" in ''|/) ;; *) printf '%s\n' "$HOME" >>"$words" ;; esac
seen=' '
add_words() {
  local dir=$1
  while [ -n "$dir" ]; do
    case "$seen" in *" $dir "*) ;; *)
      seen="$seen$dir "
      [ -f "$dir/.claude/private-words" ] && grep -Ev '^[[:space:]]*(#|$)' "$dir/.claude/private-words" >>"$words"
    esac
    [ "$dir" = / ] && break
    dir=$(dirname "$dir")
  done
}
[ -n "$CLAUDE_PROJECT_DIR" ] && add_words "$CLAUDE_PROJECT_DIR"
top=$(git -C "$base" rev-parse --show-toplevel 2>/dev/null)
[ -n "$top" ] && add_words "$top"

# The first private word in the text on stdin, or nothing.
private_in() { grep -Fio -f "$words" | head -n 1; }

# owner/repo from a GitHub remote URL (https, ssh or git@), or nothing for any other host.
github_repo() {
  printf '%s' "$1" | sed -nE 's#^(https?://|ssh://)?([^@/]+@)?github\.com[:/]([^/]+)/([^/]+)$#\3/\4#p' | sed -E 's/\.git$//'
}

# Whether <owner/repo> is public: refuses when that can't be told. $2 says what would go out.
is_public() {
  local repo=$1 what=$2 seen
  [ -n "$repo" ] || refuse "couldn't tell which GitHub repository $what would go to, so whether anyone can read it. Name it with -R <owner/repo>."
  seen=$(gh repo view "$repo" --json visibility 2>/dev/null | jq -r '.visibility // empty' 2>/dev/null)
  case "$seen" in
    PUBLIC) return 0 ;;
    PRIVATE|INTERNAL) return 1 ;;
    *) refuse "couldn't tell whether $repo is public (gh repo view gave nothing), so $what can't go out from here. Give the user the command." ;;
  esac
}

# Refuses when <text> holds a private word, on public <repo>. The text comes as an argument, never
# down a pipe: a refusal inside a pipe would end only the pipe's own subshell.
clean() {
  local repo=$1 what=$2 found
  found=$(printf '%s\n' "$3" | private_in)
  [ -z "$found" ] || refuse "$repo is public, so anyone can read $what, and it holds \"$found\", a private word (your home folder or a .claude/private-words list). Leave it out and try again."
}

here_repo() { github_repo "$(git -C "$1" remote get-url origin 2>/dev/null)"; }

# A repository a gh command names with -R/--repo, without a host in front.
named_repo() {
  printf '%s' "$1" | grep -Eo -- "(-R|--repo)([[:space:]]+|=)${quoted_dir}" | head -n 1 | sed -E 's/^(-R|--repo)([[:space:]]+|=)//' | unquote | sed -E 's#^(https?://)?github\.com/##; s#\.git$##'
}

# The text a gh command sends: its own words and the files it hands over.
sent() {
  local part=$1 file
  printf '%s\n' "$part"
  printf '%s' "$part" | grep -Eo -- "(--body-file|--input|-F|--field)([[:space:]]+|=)${quoted_dir}" | sed -E 's/^(--body-file|--input|-F|--field)([[:space:]]+|=)//' | unquote |
    while IFS= read -r file; do
      file=${file#*=@}
      file=${file#@}
      case "$file" in -) continue ;; /*) ;; *) file="$base/$file" ;; esac
      [ -f "$file" ] && cat "$file"
    done
}

# Each part of the command that starts at a line of work, up to the next ; & or |.
parts() { printf '%s' "$command" | grep -Eo "${at_start}$1[^;&|]*"; }

# Always the user's on a public repository: releases. And anywhere: a public gist or repository.
while IFS= read -r part; do
  [ -n "$part" ] || continue
  repo=$(named_repo "$part")
  [ -n "$repo" ] || repo=$(here_repo "$base")
  is_public "$repo" "a release" && refuse "$repo is public. A release there is the user's: give them the command."
done <<EOF
$(parts "${gh}[[:space:]]+release[[:space:]]+(create|edit|upload)([[:space:]]|\$)")
EOF
[ -n "$(parts "${gh}[[:space:]]+gist[[:space:]]+create([[:space:]]|\$)" | grep -E -- "[[:space:]](--public|-p)([[:space:]]|\$)")" ] &&
  refuse "a public gist can be read by anyone. That is the user's: give them the command."
[ -n "$(parts "${gh}[[:space:]]+repo[[:space:]]+(create|edit)([[:space:]]|\$)" | grep -E -- "(--public([[:space:]]|\$)|--visibility([[:space:]]+|=)[\"']?public)")" ] &&
  refuse "a public repository can be read by anyone. Making one, or turning one public, is the user's. Give them the command."

# Issues and pull requests: made, edited, commented on, reviewed, closed with a comment.
while IFS= read -r part; do
  [ -n "$part" ] || continue
  repo=$(named_repo "$part")
  [ -n "$repo" ] || repo=$(here_repo "$base")
  is_public "$repo" "an issue or a pull request there" && clean "$repo" "this issue or pull request" "$(sent "$part")"
done <<EOF
$(parts "${gh}[[:space:]]+(issue|pr)[[:space:]]+(create|comment|edit|review)([[:space:]]|\$)"; parts "${gh}[[:space:]]+(issue|pr)[[:space:]]+(close|reopen)[[:space:]][^;&|]*(-c|--comment)([[:space:]=]|\$)")
EOF

# Writes through gh api to issues, pull requests and comments, and GraphQL mutations.
while IFS= read -r part; do
  [ -n "$part" ] || continue
  writes=0
  printf '%s' "$part" | grep -Eqi -- "(-X|--method)([[:space:]]+|=)[\"']?(POST|PATCH|PUT)" && writes=1
  # gh api sends POST once a field or input is given, unless told otherwise.
  if printf '%s' "$part" | grep -Eq -- "[[:space:]](-f|-F|--field|--raw-field|--input)([[:space:]=]|\$)" &&
     ! printf '%s' "$part" | grep -Eqi -- "(-X|--method)([[:space:]]+|=)[\"']?GET"; then
    writes=1
  fi
  [ "$writes" -eq 1 ] || continue
  if printf '%s' "$part" | grep -Eq '[[:space:]]graphql([[:space:]]|$)'; then
    if printf '%s' "$part" | grep -Eqi 'mutation'; then
      repo=$(here_repo "$base")
      is_public "$repo" "this GraphQL write" && clean "$repo" "this GraphQL write" "$(sent "$part")"
    fi
    continue
  fi
  repo=$(printf '%s' "$part" | grep -Eo '/?repos/[^/[:space:]"'"'"']+/[^/[:space:]"'"'"']+/(issues|pulls|releases|comments)' | head -n 1 | sed -E 's#^/?repos/##; s#/(issues|pulls|releases|comments)$##')
  [ -n "$repo" ] || continue
  if is_public "$repo" "this write to its issues, pull requests, releases or comments"; then
    printf '%s' "$part" | grep -Eq '/releases' && refuse "$repo is public. A release there is the user's: give them the command."
    clean "$repo" "this write" "$(sent "$part")"
  fi
done <<EOF
$(parts "${gh}[[:space:]]+api([[:space:]]|\$)")
EOF

# Pushes to a public GitHub remote publish the commits they add: their messages and changes.
options="([[:space:]]+-C[[:space:]]+${quoted_dir}|[[:space:]]+-c[[:space:]]+[^[:space:];&|]+)*"
while IFS= read -r part; do
  [ -n "$part" ] || continue
  dir=$(printf '%s' "$part" | grep -Eo -- "-C[[:space:]]+${quoted_dir}" | tail -n 1 | sed -E 's/^-C[[:space:]]+//' | unquote)
  case "$dir" in
    '') dir=$base ;;
    /*) ;;
    *) dir="$base/$dir" ;;
  esac
  # The remote: the first word after push that names one, else the branch's own, else origin.
  # What is pushed: the refspecs after it (their source side), else the checked-out commit.
  remote=""
  refs=""
  for word in $(printf '%s' "$part" | sed -E 's/.*[[:space:]]push([[:space:]]|$)//'); do
    case "$word" in -*) continue ;; esac
    if [ -z "$remote" ] && [ -z "$refs" ] && git -C "$dir" remote 2>/dev/null | grep -qx -- "$word"; then
      remote=$word
    else
      src=${word%%:*}
      src=${src#+}
      [ -n "$src" ] && refs="$refs $src"
    fi
  done
  if [ -z "$remote" ]; then
    branch=$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null)
    [ -n "$branch" ] && remote=$(git -C "$dir" config "branch.$branch.remote" 2>/dev/null)
  fi
  remote=${remote:-origin}
  repo=$(github_repo "$(git -C "$dir" remote get-url "$remote" 2>/dev/null)")
  [ -n "$repo" ] || continue
  is_public "$repo" "the commits this push publishes" || continue
  # The commits the remote doesn't have yet, as far as this checkout knows: messages and changes.
  # Not the author line: the user's own git name and email are on every commit they push.
  # shellcheck disable=SC2086
  clean "$repo" "the commits this push publishes (their messages and changes)" "$(git -C "$dir" log --format='%B' -p ${refs:-HEAD} --not --remotes="$remote" 2>/dev/null)"
done <<EOF
$(parts "([^[:space:];&|]*/)?git${options}[[:space:]]+push([[:space:]]|\$)")
EOF
exit 0
