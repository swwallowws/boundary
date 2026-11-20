#!/usr/bin/env bash
# PreToolUse hook for Bash. Turns away what would publish on a public GitHub repository, since
# anyone can read it: issues, pull requests and releases (made, edited, commented on, reviewed),
# writes to those through `gh api`, a public gist, a repository made or turned public, and pushes
# to a public GitHub remote. Those are the user's: write the text to a file, show it to them with
# personal details and security findings left out, and give them the command. Exit 2 blocks the
# command and hands the message on stderr back to the agent. A JSON file as the first argument
# stands in for stdin when testing; public-posts.test.sh holds the cases.
#
# The repository is the one `-R`/`--repo` names, the one a `gh api` path names, else the one the
# command runs in (its origin, or for a push the remote it names). Whether it is public comes
# from `gh repo view`. When that can't be read, the post is refused. Remotes outside GitHub
# aren't checked.

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

# owner/repo from a GitHub remote URL (https, ssh or git@), or nothing for any other host.
github_repo() {
  printf '%s' "$1" | sed -nE 's#^(https?://|ssh://)?([^@/]+@)?github\.com[:/]([^/]+)/([^/]+)$#\3/\4#p' | sed -E 's/\.git$//'
}

# Refuses when <owner/repo> is public, or when that can't be told. $2 says what would be posted.
check() {
  local repo=$1 what=$2 seen
  [ -n "$repo" ] || refuse "couldn't tell which GitHub repository $what would go to, so whether anyone can read it. Name it with -R <owner/repo>."
  seen=$(gh repo view "$repo" --json visibility 2>/dev/null | jq -r '.visibility // empty' 2>/dev/null)
  case "$seen" in
    PUBLIC) refuse "$repo is public, so anyone can read $what. That is the user's: write the text to a file with personal details and security findings left out, show it to them and give them the command to run." ;;
    PRIVATE|INTERNAL) ;;
    *) refuse "couldn't tell whether $repo is public (gh repo view gave nothing), so posting $what is the user's." ;;
  esac
}

# The repository a command runs in: its origin on GitHub.
here_repo() {
  github_repo "$(git -C "$1" remote get-url origin 2>/dev/null)"
}

# A repository a gh command names with -R/--repo, without a host in front.
named_repo() {
  printf '%s' "$1" | grep -Eo -- "(-R|--repo)([[:space:]]+|=)${quoted_dir}" | head -n 1 | sed -E 's/^(-R|--repo)([[:space:]]+|=)//' | unquote | sed -E 's#^(https?://)?github\.com/##; s#\.git$##'
}

# Each part of the command that starts at a line of work, up to the next ; & or |.
parts() { printf '%s' "$command" | grep -Eo "${at_start}$1[^;&|]*"; }

# Issues, pull requests and releases: made, edited, commented on, reviewed.
while IFS= read -r part; do
  [ -n "$part" ] || continue
  repo=$(named_repo "$part")
  [ -n "$repo" ] || repo=$(here_repo "$base")
  check "$repo" "an issue, a pull request or a release there"
done <<EOF
$(parts "${gh}[[:space:]]+((issue|pr)[[:space:]]+(create|comment|edit|review|close|reopen)|release[[:space:]]+(create|edit))([[:space:]]|\$)" | grep -Ev "[[:space:]](close|reopen)([[:space:]]|\$)" ; parts "${gh}[[:space:]]+(issue|pr)[[:space:]]+(close|reopen)[[:space:]][^;&|]*(-c|--comment)([[:space:]=]|\$)")
EOF

# Writes through gh api to issues, pull requests, releases and comments, and GraphQL mutations.
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
    printf '%s' "$part" | grep -Eqi 'mutation' && check "$(here_repo "$base")" "this GraphQL write"
    continue
  fi
  repo=$(printf '%s' "$part" | grep -Eo '/?repos/[^/[:space:]"'"'"']+/[^/[:space:]"'"'"']+/(issues|pulls|releases|comments)' | head -n 1 | sed -E 's#^/?repos/##; s#/(issues|pulls|releases|comments)$##')
  [ -n "$repo" ] && check "$repo" "this write to its issues, pull requests, releases or comments"
done <<EOF
$(parts "${gh}[[:space:]]+api([[:space:]]|\$)")
EOF

# A public gist, and a repository made or turned public.
[ -n "$(parts "${gh}[[:space:]]+gist[[:space:]]+create([[:space:]]|\$)" | grep -E -- "[[:space:]](--public|-p)([[:space:]]|\$)")" ] &&
  refuse "a public gist can be read by anyone. That is the user's: write it to a file, show it to them and give them the command."
[ -n "$(parts "${gh}[[:space:]]+repo[[:space:]]+(create|edit)([[:space:]]|\$)" | grep -E -- "(--public([[:space:]]|\$)|--visibility([[:space:]]+|=)[\"']?public)")" ] &&
  refuse "a public repository can be read by anyone. Making one, or turning one public, is the user's. Give them the command."

# Pushes to a public GitHub remote publish the commits, their messages and their code.
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
  remote=""
  for word in $(printf '%s' "$part" | sed -E 's/.*[[:space:]]push([[:space:]]|$)//'); do
    case "$word" in -*) continue ;; esac
    git -C "$dir" remote 2>/dev/null | grep -qx -- "$word" && remote=$word
    break
  done
  if [ -z "$remote" ]; then
    branch=$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null)
    [ -n "$branch" ] && remote=$(git -C "$dir" config "branch.$branch.remote" 2>/dev/null)
  fi
  url=$(git -C "$dir" remote get-url "${remote:-origin}" 2>/dev/null)
  repo=$(github_repo "$url")
  [ -n "$repo" ] && check "$repo" "the commits this push publishes (their messages and code)"
done <<EOF
$(parts "([^[:space:];&|]*/)?git${options}[[:space:]]+push([[:space:]]|\$)")
EOF
exit 0
