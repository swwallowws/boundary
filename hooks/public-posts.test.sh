#!/usr/bin/env bash
# Checks what public-posts.sh turns away and what it lets through. A stand-in gh says which
# repositories are public, so nothing touches the network: o/open is public, o/closed private and
# o/unsure can't be read. The private words are a stand-in home folder and a workspace list. Run
# from anywhere; exits non-zero if any case is wrong.

hook="$(cd "$(dirname "$0")" && pwd)/public-posts.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Only the call the hook makes: gh repo view <owner/repo> --json visibility.
[ "$1 $2" = "repo view" ] || { echo "unexpected gh call: $*" >&2; exit 1; }
case "$3" in
  o/open) echo '{"visibility":"PUBLIC"}' ;;
  o/closed) echo '{"visibility":"PRIVATE"}' ;;
  *) echo "HTTP 404" >&2; exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"

# The workspace's private words, and a home folder whose path is one too.
ws="$tmp/ws"
mkdir -p "$ws/.claude"
printf '# names, emails, places\nJane Doe\njane@example.com\n\n' >"$ws/.claude/private-words"
export CLAUDE_PROJECT_DIR="$ws" HOME=/home/tester

# repo <folder> <origin url>: a repository in the workspace with one commit, on branch work, that
# its origin already has.
g() { git -C "$ws/$r" -c user.name=t -c user.email=t@t "$@"; }
repo() {
  r=$1
  git init -q -b work "$ws/$r"
  g commit -q --allow-empty -m first
  [ -z "$2" ] || { g remote add origin "$2"; g update-ref refs/remotes/origin/work HEAD; }
}
repo open https://github.com/o/open.git
repo closed git@github.com:o/closed.git
repo unsure ssh://git@github.com/o/unsure
repo local "$tmp/elsewhere.git"
repo none ""
# A list of the public repository's own.
mkdir -p "$ws/open/.claude"
printf 'codename falcon\n' >"$ws/open/.claude/private-words"

# check <blocked|allowed> <cwd> <command> [text the refusal must hold]
check() {
  jq -n --arg cwd "$2" --arg command "$3" '{tool_name: "Bash", cwd: $cwd, tool_input: {command: $command}}' >"$tmp/input"
  "$hook" "$tmp/input" >"$tmp/output" 2>&1
  code=$?
  if { [ "$1" = blocked ] && [ "$code" -ne 2 ]; } || { [ "$1" = allowed ] && [ "$code" -ne 0 ]; }; then
    echo "WRONG: expected $1, exit $code, in $2: $3"
    cat "$tmp/output"
    failed=1
  elif [ -n "$4" ] && ! grep -qF -- "$4" "$tmp/output"; then
    echo "WRONG: blocked for another reason than \"$4\", in $2: $3"
    cat "$tmp/output"
    failed=1
  fi
}
private='a private word'

# Issues and pull requests on a public repository: out when their text holds no private word.
check allowed "$ws" 'gh issue create -R o/open --title "Fences in sections" --body "A ## line in a code block split the path."'
check allowed "$ws/open" 'gh pr create --title x --body "Closes #3"'
check blocked "$ws" 'gh issue create -R o/open --title x --body "Jane Doe found it"' "holds \"Jane Doe\""
check blocked "$ws" 'gh issue create -R o/open --title x --body "JANE DOE found it"' "$private"
check blocked "$ws/open" 'gh pr create --title x --body "see /home/tester/notes.md"' "holds \"/home/tester\""
check blocked "$ws/open" 'gh issue comment 5 --body "ask jane@example.com"' "$private"
check blocked "$ws/open" 'gh issue close 4 --comment "Jane Doe says done"' "$private"
check blocked "$ws/open" 'gh pr review 3 --approve --body "codename falcon looks good"' "holds \"codename falcon\""
check blocked "$ws" 'cd open && gh pr edit 3 --body "for Jane Doe"' "$private"
check blocked "$ws" 'git status && gh issue create -R o/open --title "Jane Doe"' "$private"
check blocked "$ws" "bash -c 'gh issue create -R o/open --title x --body \"Jane Doe\"'" "$private"
# A body file is read too.
printf 'Steps:\n1. Ask jane@example.com.\n' >"$ws/body.md"
printf 'Steps:\n1. Open the page.\n' >"$ws/clean.md"
check blocked "$ws" 'gh issue create -R o/open --title x --body-file body.md' "holds \"jane@example.com\""
check blocked "$ws" "gh issue create -R o/open --title x --body-file $ws/body.md" "$private"
check allowed "$ws" 'gh issue create -R o/open --title x --body-file clean.md'
# A list's comment lines are no words.
check allowed "$ws" 'gh issue create -R o/open --title x --body "names, emails, places"'
# A private repository, and what only reads.
check allowed "$ws" 'gh issue create -R o/closed --title x --body "Jane Doe found it"'
check allowed "$ws/open" 'gh issue list --search "Jane Doe"'
check allowed "$ws/open" 'gh issue close 4'
# Can't tell: refused, as that.
check blocked "$ws" 'gh issue create -R o/unsure --title x' "couldn't tell whether o/unsure is public"
check blocked "$ws/none" 'gh issue create --title x' "couldn't tell which GitHub repository"

# gh api writes.
check allowed "$ws" 'gh api -X POST repos/o/open/issues -f title=x -f body=y'
check blocked "$ws" 'gh api repos/o/open/issues/1/comments -f body="Jane Doe"' "$private"
check blocked "$ws" 'gh api --method PATCH /repos/o/open/pulls/2 --input body.md' "$private"
check blocked "$ws/open" 'gh api graphql -f query="mutation { addComment(input: {body: \"Jane Doe\"}) { clientMutationId } }"' "$private"
check allowed "$ws" 'gh api repos/o/open/issues'
check allowed "$ws" 'gh api -X POST repos/o/closed/issues -f body="Jane Doe"'

# Always the user's: releases on a public repository, public gists and repositories.
check blocked "$ws/open" 'gh release create v1 --notes x' "A release there is the user's"
check blocked "$ws" 'gh release edit v1 -R o/open --notes x' "A release there is the user's"
check blocked "$ws" 'gh api -X POST repos/o/open/releases -f tag_name=v1' "A release there is the user's"
check allowed "$ws/closed" 'gh release create v1 --notes x'
check blocked "$ws" 'gh gist create --public notes.md' "public gist"
check blocked "$ws" 'gh gist create -p notes.md' "public gist"
check allowed "$ws" 'gh gist create notes.md'
check blocked "$ws" 'gh repo create o/new --public' "public repository"
check blocked "$ws" 'gh repo edit o/closed --visibility public' "public repository"
check allowed "$ws" 'gh repo create o/new --private'

# Pushes to a public repository: out when the commits it adds hold no private word.
r=open
printf 'hello\n' >"$ws/open/a.txt"
g add a.txt
g commit -q -m "Fences in sections"
check allowed "$ws/open" 'git push'
check allowed "$ws/open" 'git push -u origin work'
g commit -q --allow-empty -m "Thanks to Jane Doe"
check blocked "$ws/open" 'git push origin work' "holds \"Jane Doe\""
check blocked "$ws" "git -C $ws/open push" "$private"
check blocked "$ws" 'cd open && git push' "$private"
# Once the remote has them, they aren't read again.
g update-ref refs/remotes/origin/work HEAD
check allowed "$ws/open" 'git push'
# A change, as well as a message.
printf 'contact: jane@example.com\n' >"$ws/open/b.txt"
g add b.txt
g commit -q -m "Add contact"
check blocked "$ws/open" 'git push' "holds \"jane@example.com\""
g update-ref refs/remotes/origin/work HEAD
# Another branch, named in the refspec.
g branch -q side
g switch -q side
g commit -q --allow-empty -m "codename falcon"
g switch -q work
check allowed "$ws/open" 'git push origin work'
check blocked "$ws/open" 'git push origin side:side' "holds \"codename falcon\""
# A private repository, another host, and a remote that can't be read.
r=closed
g commit -q --allow-empty -m "Jane Doe"
check allowed "$ws/closed" 'git push'
r=local
g commit -q --allow-empty -m "Jane Doe"
check allowed "$ws/local" 'git push origin work'
check blocked "$ws/unsure" 'git push' "couldn't tell whether o/unsure is public"
check allowed "$ws/none" 'git push'

# Words that only mention these.
check allowed "$ws/open" 'git commit -m "gh issue create needs no Jane Doe"'
check allowed "$ws/open" 'grep -n "git push" README.md'

# Without jq the hook refuses instead of reading nothing and letting the call through.
mkdir -p "$tmp/nojq"
printf '{"tool_name":"Bash","tool_input":{"command":"git status"}}' >"$tmp/plain.json"
PATH="$tmp/nojq" "$BASH" "$hook" "$tmp/plain.json" >"$tmp/output" 2>&1
[ $? -eq 2 ] || { echo "WRONG: without jq the hook let a call through"; failed=1; }

if [ "$failed" -eq 0 ]; then
  echo "public-posts: all cases right"
fi
exit "$failed"
