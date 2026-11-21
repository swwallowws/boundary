#!/usr/bin/env bash
# PreToolUse hook for Bash. Reads what would go out on a public GitHub repository, where anyone
# can read it, and turns it away when it holds a private word or comes in a shape the hook can't
# read whole. Exit 2 blocks the command and hands the message on stderr back to the agent. A JSON
# file as the first argument stands in for stdin when testing; public-posts.test.sh holds the
# cases.
#
# On a public repository:
# - An issue or pull request (made, edited, commented on, reviewed, closed or reopened with a
#   comment) goes out when its text comes from the command and from files (--body-file, -F,
#   --template), never from stdin or a command substitution, and the whole command and those
#   files hold no private word. The whole command is read, every line, so a quoted `;` or a
#   second line can't hide a word.
# - Labels and a repository's description are read the same way.
# - A push goes out when it names one remote and plain branches or commits (or none, for the
#   checked-out one) and the commits the remote doesn't have yet, their messages and changes,
#   hold no private word. --all, --mirror, --tags, tags and patterns are refused: name the branch.
#   A deletion sends nothing.
# - Writes through `gh api` and GraphQL mutations are refused: use `gh issue` or `gh pr`.
# - Releases are the user's. Anywhere: a public gist, and a repository made or turned public.
# On a private repository nothing is checked. When the hook can't tell whether a repository is
# public, or can't read what a push sends, it refuses.
#
# Private words are the home folder's path and every line of a `.claude/private-words` list,
# matched ignoring case, read from the folder the session started in ($CLAUDE_PROJECT_DIR), the
# repository the command runs in and any repository it names with `git -C`, with the folders
# above them. One word or phrase per line; blank lines and lines starting with # are skipped:
#
#   # names, emails, places, private project terms
#   Jane Doe
#   jane@example.com
#
# The repository is, as gh picks it: the one `-R`/`--repo` names, else GH_REPO (in the command
# or the environment), else the one `gh repo set-default` chose, else the origin of the folder
# the command runs in. For a push, the remote it names. Whether it is public comes from
# `gh repo view`. Remotes outside GitHub aren't checked. Words that only mention these (a commit
# message, a grep) count too when they sit at the start of a line of work after `;`: the hook
# errs on the safe side.

# Without jq the call can't be read. An empty read would let everything through.
command -v jq >/dev/null 2>&1 || { echo "Blocked: jq isn't installed, so this guard can't read the call. Install jq." >&2; exit 2; }
input=$(jq -c '.' "${1:-/dev/stdin}")
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')

refuse() {
  echo "Blocked: $1" >&2
  exit 2
}
# Words split from the command (refspecs like refs/heads/*) are never file patterns.
set -f

# As in user-only.sh: a command counts at the start of a line of work, after sudo, a wrapper, an
# assignment or a shell that runs it.
assign='[[:alpha:]_][[:alnum:]_]*=[^[:space:];&|]*[[:space:]]+'
at_start="(^|[;&|])[[:space:]]*(sudo[[:space:]]+)?(${assign})*((env|command|exec|nohup|time)[[:space:]]+(${assign})*)*((ba|z|da|k)?sh[[:space:]]+(-[[:alpha:]]+[[:space:]]+)*[\"']?)?"
gh='([^[:space:];&|]*/)?gh'
quoted_dir='("[^"]+"|'"'"'[^'"'"']+'"'"'|[^[:space:];&|]+)'
unquote() { sed -E 's/^["'"'"']//; s/["'"'"']$//'; }

# Every line of the command at once, so a multi-line command is read whole.
flat=$(printf '%s' "$command" | tr '\n' ' ')

# `cd <dir> && ...` moves where the rest runs.
moved=$(printf '%s' "$flat" | grep -Eo "${at_start}cd[[:space:]]+${quoted_dir}" | head -n 1 | sed -E 's/.*cd[[:space:]]+//' | unquote)
case "$moved" in
  '') base=${cwd:-.} ;;
  /*) base=$moved ;;
  *) base="${cwd:-.}/$moved" ;;
esac
# Repositories the command names with `git -C <dir>`.
named_dirs=$(printf '%s' "$flat" | grep -Eo "git([[:space:]]+-c[[:space:]]+[^[:space:];&|]+)*[[:space:]]+-C[[:space:]]+${quoted_dir}" | sed -E 's/.*-C[[:space:]]+//' | unquote)

# The private words: the home folder's path and the lines of every .claude/private-words list.
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
add_repo_words() {
  local top
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)
  [ -n "$top" ] && add_words "$top"
}
[ -n "$CLAUDE_PROJECT_DIR" ] && add_words "$CLAUDE_PROJECT_DIR"
add_repo_words "$base"
while IFS= read -r named; do
  [ -n "$named" ] || continue
  case "$named" in /*) ;; *) named="$base/$named" ;; esac
  add_repo_words "$named"
done <<EOF
$named_dirs
EOF

# The first private word in <text>, or nothing. Runs of spaces and line ends read as one space, in
# the text and in the words, so a name wrapped onto the next line is still found.
private_in() {
  local spaced
  spaced=$(mktemp)
  awk '{ gsub(/[[:space:]]+/, " "); sub(/^ /, ""); sub(/ $/, ""); if ($0 != "") print }' "$words" >"$spaced"
  printf '%s\n' "$1" | tr -s '[:space:]' ' ' | grep -Fio -f "$spaced" | head -n 1
  rm -f "$spaced"
}

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

# Refuses when <text> holds a private word, on public <repo>.
clean() {
  local repo=$1 what=$2 found
  found=$(private_in "$3")
  [ -z "$found" ] || refuse "$repo is public, so anyone can read $what, and it holds \"$found\", a private word (your home folder or a .claude/private-words list). Leave it out and try again."
}

# The repository a gh command acts on, picked the way gh picks it.
gh_repo() {
  local part=$1 repo env_repo resolved
  repo=$(printf '%s' "$part" | grep -Eo -- "(-R|--repo)([[:space:]]+|=)${quoted_dir}" | head -n 1 | sed -E 's/^(-R|--repo)([[:space:]]+|=)//' | unquote)
  if [ -z "$repo" ]; then
    env_repo=$(printf '%s' "$flat" | grep -Eo "GH_REPO=${quoted_dir}" | tail -n 1 | sed -E 's/^GH_REPO=//' | unquote)
    repo=${env_repo:-$GH_REPO}
  fi
  if [ -z "$repo" ]; then
    resolved=$(git -C "$base" config --get-regexp '^remote\..*\.gh-resolved$' 2>/dev/null | awk '$2 == "base" { sub(/^remote\./, "", $1); sub(/\.gh-resolved$/, "", $1); print $1; exit }')
    repo=$(github_repo "$(git -C "$base" remote get-url "${resolved:-origin}" 2>/dev/null)")
  fi
  printf '%s' "$repo" | sed -E 's#^(https?://)?github\.com/##; s#\.git$##'
}

# The files a gh command hands over as text: --body-file, -F/--body-file, --template.
handed() {
  printf '%s' "$1" | grep -Eo -- "(--body-file|-F|--template|-T)([[:space:]]+|=)${quoted_dir}" | sed -E 's/^(--body-file|-F|--template|-T)([[:space:]]+|=)//' | unquote
}

# Each gh command at the start of a line of work, read up to the next ; & or |.
gh_parts() { printf '%s' "$flat" | grep -Eo "${at_start}${gh}[[:space:]]+$1[^;&|]*"; }

# Anywhere: a public gist, and a repository made or turned public.
[ -n "$(gh_parts "gist[[:space:]]+(create|new)([[:space:]]|\$)" | grep -Ei -- "[[:space:]](--public|-p)([[:space:]=]|\$)")" ] &&
  refuse "a public gist can be read by anyone. That is the user's: give them the command."
[ -n "$(gh_parts "repo[[:space:]]+(create|new|edit)([[:space:]]|\$)" | grep -Ei -- "(--public([[:space:]=]|\$)|--visibility([[:space:]]+|=)[\"']?public)")" ] &&
  refuse "a public repository can be read by anyone. Making one, or turning one public, is the user's. Give them the command."

# gh api writes and GraphQL mutations: refused on a public repository, and wherever the hook
# can't tell where they go.
while IFS= read -r part; do
  [ -n "$part" ] || continue
  writes=0
  printf '%s' "$part" | grep -Eqi -- "(-X|--method)([[:space:]]+|=)[\"']?(POST|PATCH|PUT|DELETE)" && writes=1
  if printf '%s' "$part" | grep -Eq -- "[[:space:]](-f|-F|--field|--raw-field|--input)([[:space:]=]|\$)" &&
     ! printf '%s' "$part" | grep -Eqi -- "(-X|--method)([[:space:]]+|=)[\"']?GET"; then
    writes=1
  fi
  [ "$writes" -eq 1 ] || continue
  # GraphQL always posts: a mutation, or a query from a file the hook doesn't open, is a write.
  if printf '%s' "$part" | grep -Eq '[[:space:]]graphql([[:space:]]|$)'; then
    if printf '%s' "$part" | grep -Eqi 'mutation|=@'; then
      refuse "a GraphQL write can't be read for where it goes or what it says. Use gh issue or gh pr with --body-file."
    fi
    continue
  fi
  path=$(printf '%s' "$part" | grep -Eo '[[:space:]]/?repos/[^[:space:]"'"'"']+' | head -n 1 | sed -E 's#^[[:space:]]*/?repos/##')
  if [ -z "$path" ]; then
    printf '%s' "$part" | grep -Eqi '[[:space:]]/?gists' && printf '%s' "$part" | grep -Eqi 'public' &&
      refuse "a public gist can be read by anyone. That is the user's: give them the command."
    continue
  fi
  owner=${path%%/*}
  rest=${path#*/}
  name=${rest%%/*}
  repo="$owner/$name"
  [ "$repo" = "{owner}/{repo}" ] && repo=$(gh_repo "")
  is_public "$repo" "this gh api write" && refuse "$repo is public. A gh api write there can't be read whole: use gh issue or gh pr with --body-file."
  printf '%s' "$part" | grep -Eqi 'visibility|private' && printf '%s' "$part" | grep -Eqi 'public|false' &&
    refuse "turning a repository public is the user's. Give them the command."
done <<EOF
$(gh_parts "api([[:space:]]|\$)")
EOF

# Releases on a public repository: the user's.
while IFS= read -r part; do
  [ -n "$part" ] || continue
  is_public "$(gh_repo "$part")" "a release" && refuse "$(gh_repo "$part") is public. A release there is the user's: give them the command."
done <<EOF
$(gh_parts "release[[:space:]]+(create|new|edit|upload)([[:space:]]|\$)")
EOF

# Issues, pull requests, labels and a repository's description: their text, read whole.
posts="(issue|pr)[[:space:]]+(create|new|comment|edit|review|close|reopen)([[:space:]]|\$)|label[[:space:]]+(create|edit)([[:space:]]|\$)|repo[[:space:]]+edit([[:space:]]|\$)"
while IFS= read -r part; do
  [ -n "$part" ] || continue
  repo=$(gh_repo "$part")
  # A label or a repository edit names its repository first, as an argument, when it isn't -R.
  if printf '%s' "$part" | grep -Eq "[[:space:]]repo[[:space:]]+edit[[:space:]]+[^-[:space:]]"; then
    repo=$(printf '%s' "$part" | sed -E 's/.*[[:space:]]repo[[:space:]]+edit[[:space:]]+([^[:space:]]+).*/\1/' | unquote)
  fi
  is_public "$repo" "this" || continue
  # Text the hook can't read: stdin, a command substitution.
  if printf '%s' "$flat" | grep -Eq -- '\$\(|`' ||
     printf '%s' "$part" | grep -Eq -- "(--body-file|-F|--input)([[:space:]]+|=)[\"']?-([[:space:]\"']|\$)" ||
     printf '%s' "$flat" | grep -Eq -- "\|[[:space:]]*${gh}[[:space:]]"; then
    refuse "$repo is public, and this text comes from somewhere the hook can't read (stdin or a command). Write it to a file and pass it with --body-file."
  fi
  text=$flat
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    case "$file" in /*) ;; *) file="$base/$file" ;; esac
    [ -f "$file" ] || refuse "$repo is public, and $file, which this command hands over, can't be read."
    text="$text
$(cat "$file")"
  done <<FILES
$(handed "$part")
FILES
  clean "$repo" "this" "$text"
done <<EOF
$(gh_parts "($posts)")
EOF

# Pushes to a public GitHub remote: what they send, read.
options="([[:space:]]+-C[[:space:]]+${quoted_dir}|[[:space:]]+-c[[:space:]]+[^[:space:];&|]+)*"
while IFS= read -r part; do
  [ -n "$part" ] || continue
  dir=$(printf '%s' "$part" | grep -Eo -- "-C[[:space:]]+${quoted_dir}" | tail -n 1 | sed -E 's/^-C[[:space:]]+//' | unquote)
  case "$dir" in
    '') dir=$base ;;
    /*) ;;
    *) dir="$base/$dir" ;;
  esac
  remote=""
  url=""
  refs=""
  all=""
  deleting=0
  skip=0
  # shellcheck disable=SC2013
  for word in $(printf '%s' "$part" | sed -E 's/.*[[:space:]]push([[:space:]]|$)//'); do
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    word=$(printf '%s' "$word" | unquote)
    case "$word" in
      --all|--mirror|--tags|--follow-tags) all=1 ;;
      -d|--delete) deleting=1 ;;
      -o|--push-option|--repo|--receive-pack|--exec) skip=1 ;;
      -*) ;;
      *)
        if [ -z "$remote" ] && [ -z "$url" ] && [ -z "$refs" ]; then
          if git -C "$dir" remote 2>/dev/null | grep -qx -- "$word"; then remote=$word; continue; fi
          case "$word" in *://*|*@*:*|*github.com*) url=$word; continue ;; esac
        fi
        refs="$refs $word"
        ;;
    esac
  done
  if [ -z "$remote" ] && [ -z "$url" ]; then
    branch=$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null)
    [ -n "$branch" ] && remote=$(git -C "$dir" config "branch.$branch.remote" 2>/dev/null)
    remote=${remote:-origin}
  fi
  [ -n "$url" ] || url=$(git -C "$dir" remote get-url "$remote" 2>/dev/null)
  repo=$(github_repo "$url")
  [ -n "$repo" ] || continue
  is_public "$repo" "the commits this push publishes" || continue
  [ "$deleting" -eq 1 ] && continue
  [ -z "$all" ] || refuse "$repo is public, and --all, --mirror and --tags send more than the hook reads. Push one named branch."
  # Each source: a plain branch or commit, never a tag or a pattern. A deletion (`:branch`) sends nothing.
  sources=""
  for ref in $refs; do
    src=${ref%%:*}
    src=${src#+}
    [ -n "$src" ] || continue
    case "$src" in *'*'*|refs/tags/*|tag) refuse "$repo is public, and this push sends tags or a pattern, more than the hook reads. Push one named branch." ;; esac
    git -C "$dir" show-ref -q --verify "refs/tags/$src" && refuse "$repo is public, and $src is a tag. Push one named branch."
    git -C "$dir" rev-parse -q --verify "$src^{commit}" >/dev/null 2>&1 || refuse "$repo is public, and the hook can't read what $src is. Push one named branch."
    sources="$sources $src"
  done
  # The commits the remote doesn't have yet, as far as this checkout knows: messages and changes.
  # Not the author line: the user's own git name and email are on every commit they push.
  # shellcheck disable=SC2086
  if [ -n "$remote" ]; then
    sent=$(git -C "$dir" log --format='%B' -p ${sources:-HEAD} --not --remotes="$remote" 2>/dev/null) || refuse "$repo is public, and the hook couldn't read what this push sends. Push one named branch."
  else
    sent=$(git -C "$dir" log --format='%B' -p ${sources:-HEAD} 2>/dev/null) || refuse "$repo is public, and the hook couldn't read what this push sends. Push one named branch."
  fi
  clean "$repo" "the commits this push publishes (their messages and changes)" "$sent"
done <<EOF
$(printf '%s' "$flat" | grep -Eo "${at_start}([^[:space:];&|]*/)?git${options}[[:space:]]+push([[:space:]]|\$)[^;&|]*")
EOF
exit 0
