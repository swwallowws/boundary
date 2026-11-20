#!/usr/bin/env bash
# Checks what public-posts.sh turns away and what it lets through. A stand-in gh says which
# repositories are public, so nothing touches the network: o/open is public, o/closed private and
# o/unsure can't be read. Run from anywhere; exits non-zero if any case is wrong.

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

# repo <folder> <origin url>: a repository with one commit, on branch work.
repo() {
  git init -q -b work "$tmp/$1"
  git -C "$tmp/$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
  [ -z "$2" ] || git -C "$tmp/$1" remote add origin "$2"
}
repo open https://github.com/o/open.git
repo closed git@github.com:o/closed.git
repo unsure ssh://git@github.com/o/unsure
repo local "$tmp/elsewhere.git"
repo none ""
# A public repository with a second remote, private.
git -C "$tmp/open" remote add mirror git@github.com:o/closed.git

# check <blocked|allowed> <cwd> <command>
check() {
  jq -n --arg cwd "$2" --arg command "$3" '{tool_name: "Bash", cwd: $cwd, tool_input: {command: $command}}' >"$tmp/input"
  "$hook" "$tmp/input" >"$tmp/output" 2>&1
  code=$?
  if { [ "$1" = blocked ] && [ "$code" -ne 2 ]; } || { [ "$1" = allowed ] && [ "$code" -ne 0 ]; }; then
    echo "WRONG: expected $1, exit $code, in $2: $3"
    cat "$tmp/output"
    failed=1
  fi
}

# public <cwd> <command>: blocked because o/open is public, never for another reason (a hook that
# couldn't tell would block these too).
public() {
  check blocked "$1" "$2"
  grep -qF "o/open is public, so anyone can read" "$tmp/output" || { echo "WRONG: not refused as public, in $1: $2"; cat "$tmp/output"; failed=1; }
}

# Issues, pull requests and releases on a public repository.
public "$tmp" 'gh issue create -R o/open --title x --body-file b.md'
public "$tmp" 'gh issue create --repo o/open --title x'
public "$tmp" 'gh issue create --repo=o/open --title x'
public "$tmp" 'gh issue create -R github.com/o/open --title x'
public "$tmp/open" 'gh issue comment 5 --body "x"'
public "$tmp/open" 'gh pr create --title x --body-file b.md'
public "$tmp/open" 'gh pr review 3 --approve --body ok'
public "$tmp/open" 'gh pr edit 3 --body x'
public "$tmp/open" 'gh issue close 4 --comment "done"'
public "$tmp/open" 'gh issue close 4 -c done'
public "$tmp/open" 'gh release create v1 --notes x'
public "$tmp" 'cd open && gh pr create --title x'
public "$tmp" 'git status && gh issue create -R o/open --title x'
public "$tmp" '/opt/homebrew/bin/gh issue create -R o/open --title x'
public "$tmp" 'bash -c "gh issue create -R o/open --title x"'
# The same on a private repository, and what only reads.
check allowed "$tmp" 'gh issue create -R o/closed --title x --body-file b.md'
check allowed "$tmp/closed" 'gh pr create --title x --body-file b.md'
check allowed "$tmp/open" 'gh issue list'
check allowed "$tmp/open" 'gh pr view 3'
check allowed "$tmp/open" 'gh issue close 4'
check allowed "$tmp/open" 'gh pr checks 3'
# Can't tell: refused.
check blocked "$tmp" 'gh issue create -R o/unsure --title x'
check blocked "$tmp/none" 'gh issue create --title x'

# gh api: writes to a public repository's issues, pull requests, releases and comments.
public "$tmp" 'gh api -X POST repos/o/open/issues -f title=x'
public "$tmp" 'gh api repos/o/open/issues/1/comments -f body=x'
public "$tmp" 'gh api --method PATCH /repos/o/open/pulls/2 -f body=x'
public "$tmp" 'gh api repos/o/open/releases --input r.json'
public "$tmp/open" 'gh api graphql -f query="mutation { addComment(input: {}) { clientMutationId } }"'
check allowed "$tmp" 'gh api repos/o/open/issues'
check allowed "$tmp" 'gh api repos/o/open/issues -X GET -f state=all'
check allowed "$tmp" 'gh api -X POST repos/o/closed/issues -f title=x'
check allowed "$tmp/open" 'gh api graphql -f query="query { viewer { login } }"'

# Public gists and repositories.
check blocked "$tmp" 'gh gist create --public notes.md'
check blocked "$tmp" 'gh gist create -p notes.md'
check allowed "$tmp" 'gh gist create notes.md'
check blocked "$tmp" 'gh repo create o/new --public'
check blocked "$tmp" 'gh repo edit o/closed --visibility public'
check allowed "$tmp" 'gh repo create o/new --private'

# Pushes to a public GitHub remote.
public "$tmp/open" 'git push'
public "$tmp/open" 'git push -u origin work'
public "$tmp/open" 'git push origin work:main'
public "$tmp" "git -C $tmp/open push origin work"
public "$tmp" 'cd open && git push'
check allowed "$tmp/open" 'git push mirror work'
check allowed "$tmp/closed" 'git push -u origin work'
check allowed "$tmp/local" 'git push origin work'
check blocked "$tmp/unsure" 'git push'
check allowed "$tmp/none" 'git push'

# Words that only mention these.
check allowed "$tmp/open" 'git commit -m "gh issue create needs the user"'
check allowed "$tmp/open" 'grep -n "git push" README.md'
check allowed "$tmp/open" 'git status'

# Without jq the hook refuses instead of reading nothing and letting the call through.
mkdir -p "$tmp/nojq"
printf '{"tool_name":"Bash","tool_input":{"command":"git status"}}' >"$tmp/plain.json"
PATH="$tmp/nojq" "$BASH" "$hook" "$tmp/plain.json" >"$tmp/output" 2>&1
[ $? -eq 2 ] || { echo "WRONG: without jq the hook let a call through"; failed=1; }

if [ "$failed" -eq 0 ]; then
  echo "public-posts: all cases right"
fi
exit "$failed"
