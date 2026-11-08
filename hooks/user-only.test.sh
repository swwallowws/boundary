#!/usr/bin/env bash
# Checks what user-only.sh turns away and what it lets through, against a throwaway workspace,
# repository and worktree. Run from anywhere; exits non-zero if any case is wrong.

hook="$(cd "$(dirname "$0")" && pwd)/user-only.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ws="$tmp/ws"
main="$ws/main"
wt="$ws/wt"
git init -q -b main "$main"
git -C "$main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
git -C "$main" worktree add -q -b other "$wt"
mkdir -p "$main/sub" "$main/.claude" "$ws/.claude" "$tmp/elsewhere"
failed=0

# The workspace lists deploys for every project in it; the repository lists its own releases.
cat >"$ws/.claude/user-only" <<'EOF'
# what: extended regex
deploying: nixos-rebuild([[:space:]]|$)
deploying: nix[[:space:]]+run[[:space:]][^;&|]*#deploy
deploying: fly[[:space:]]+deploy|vercel[[:space:]]+--prod
EOF
printf '%s\n' 'releasing: ([^[:space:];&|]*/)?(ship|store)-release\.sh([[:space:]]|$)' >"$main/.claude/user-only"
export CLAUDE_PROJECT_DIR="$main"

# check <blocked|allowed> <cwd> <command>
check() {
  jq -n --arg cwd "$2" --arg command "$3" '{tool_name: "Bash", cwd: $cwd, tool_input: {command: $command}}' >"$tmp/input"
  "$hook" "$tmp/input" >"$tmp/output" 2>&1
  code=$?
  if { [ "$1" = blocked ] && [ "$code" -ne 2 ]; } || { [ "$1" = allowed ] && [ "$code" -ne 0 ]; }; then
    echo "WRONG: expected $1, exit $code, in $2: $3"
    failed=1
  fi
}

# Merging, always.
check blocked "$tmp" 'gh pr merge 71 --squash'
check blocked "$tmp" 'gh pr merge 71 --repo a/b --squash'
check blocked "$tmp" 'git status && gh pr merge 1'
check blocked "$tmp" '/opt/homebrew/bin/gh pr merge 1 --squash'
check blocked "$tmp" 'gh api -X PUT repos/a/b/pulls/1/merge'
check blocked "$tmp" 'gh api graphql -f query="mutation { mergePullRequest(input: {}) { clientMutationId } }"'

# Listed in the workspace, above the project.
check blocked "$main" 'nix run .#deploy'
check blocked "$main" 'nix run /x/app#deploy -- build'
check blocked "$main" 'nixos-rebuild switch --flake .#host'
check blocked "$main" 'sudo nixos-rebuild switch'
check blocked "$main" 'fly deploy'
check blocked "$main" 'vercel --prod'

# Listed in the repository the command runs in.
check blocked "$main" './ship-release.sh'
check blocked "$main/sub" '/x/app/store-release.sh 1.0.0'

# Run through a shell or a wrapper, they're still the user's.
check blocked "$main" 'bash ship-release.sh'
check blocked "$main" 'bash -x ./ship-release.sh'
check blocked "$main" 'sh -c "./ship-release.sh 1.0"'
check blocked "$main" "zsh -c 'nixos-rebuild switch'"
check blocked "$main" 'env FOO=1 ./ship-release.sh'
check blocked "$main" 'FOO=1 BAR=2 ./ship-release.sh'
check blocked "$main" 'nohup ./ship-release.sh'
check blocked "$tmp" 'bash -c "gh pr merge 1"'
check blocked "$main" 'sudo bash nixos-rebuild switch'
check allowed "$main" 'bash scripts/test.sh'
check allowed "$main" 'bash -c "git status"'
check allowed "$main" 'cat ship-release.sh'

# A repository whose list makes pushing the user's (a public one), with a worktree. The list is
# kept out of git, so the worktree has no copy and the main checkout's list has to count.
pub="$tmp/pub"
git init -q -b main "$pub"
git -C "$pub" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
git -C "$pub" worktree add -q -b side "$tmp/pubwt"
mkdir -p "$pub/.claude"
printf '%s\n' 'pushing to a public repo: ([^[:space:];&|]*/)?git([[:space:]]+-[Cc][[:space:]]+[^[:space:];&|]+)*[[:space:]]+push([[:space:]]|$)' >"$pub/.claude/user-only"
check blocked "$pub" 'git push'
check blocked "$pub" 'git push origin --delete side'
check blocked "$tmp/pubwt" 'git push -u origin side'
check blocked "$tmp/elsewhere" "git -C $pub push origin main"
check blocked "$tmp/elsewhere" "git -C $tmp/pubwt push"
check blocked "$tmp/elsewhere" "git -c core.pager=cat -C \"$pub\" push"
check allowed "$main" 'git push'
check allowed "$tmp/elsewhere" "git -C $main push"
check allowed "$pub" 'git status'
check allowed "$pub" 'git commit -m "push later"'

# boundary's own list: its main changes only through a pull request the user merges.
own="$tmp/own"
git init -q -b main "$own"
git -C "$own" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
mkdir -p "$own/.claude"
cp "$(dirname "$hook")/../.claude/user-only" "$own/.claude/user-only"
check blocked "$own" 'git push origin main'
check blocked "$own" 'git push -u origin main'
check blocked "$own" 'git push --force origin +main'
check blocked "$own" 'git push origin HEAD:main'
check blocked "$own" 'git push origin main:main'
check blocked "$own" 'git push origin HEAD'
check blocked "$own" 'git push origin HEAD:refs/heads/main'
check blocked "$own" 'git push origin +HEAD:main'
check blocked "$own" 'git push origin some-branch:main'
check allowed "$own" 'git push origin HEAD:some-branch'
check blocked "$own" 'git push'
check blocked "$own" 'git push origin'
check blocked "$own" 'git push -u origin'
check blocked "$tmp/elsewhere" "git -C $own push origin main"
check allowed "$own" 'git push -u origin protect-main'
check allowed "$own" 'git push origin main-fix'
check allowed "$own" 'git push --delete origin old-branch'
check allowed "$tmp/elsewhere" "git -C $own push -u origin some-branch"

# A workspace that is itself a repository guards its own main with .claude/user-only.repo, which
# must not reach the project repositories inside it.
wsr="$tmp/wsrepo"
git init -q -b main "$wsr"
git -C "$wsr" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
git -C "$wsr" worktree add -q -b side "$tmp/wsrepo-wt"
git init -q -b main "$wsr/proj"
mkdir -p "$wsr/.claude"
cp "$(dirname "$hook")/../.claude/user-only" "$wsr/.claude/user-only.repo"
check blocked "$wsr" 'git push origin main'
check blocked "$wsr" 'git push'
check blocked "$tmp/elsewhere" "git -C $wsr push origin main"
check blocked "$tmp/wsrepo-wt" 'git push origin main'
check allowed "$wsr/proj" 'git push origin main'
check allowed "$wsr/proj" 'git push'
check allowed "$wsr" "git -C proj push origin main"
check allowed "$wsr" 'git push -u origin side'

# Outside the workspace and the repository, only merging and branch changes are guarded.
unset CLAUDE_PROJECT_DIR
check allowed "$tmp/elsewhere" './ship-release.sh'
check allowed "$tmp/elsewhere" 'nixos-rebuild switch'
check blocked "$tmp/elsewhere" 'gh pr merge 1'
export CLAUDE_PROJECT_DIR="$main"

# Branch changes in a main checkout.
check blocked "$main" 'git switch other'
check blocked "$main" 'git checkout other'
check blocked "$main" 'git checkout -b fresh'
check blocked "$main" 'git switch -c fresh'
check blocked "$tmp" "git -C $main switch other"
check blocked "$tmp" "git -C \"$main\" checkout other"
check blocked "$ws" 'git -C main switch other'
check blocked "$main/sub" 'git switch other'
check blocked "$main" 'gh pr checkout 71'
check blocked "$main" 'git -c core.pager=cat checkout other'
check blocked "$tmp" "cd $main && git switch other"
check blocked "$tmp" "cd \"$main\" && git checkout other"

# A linked worktree belongs to its session.
check allowed "$wt" 'git switch main2'
check allowed "$wt" 'git checkout -b fresh'
check allowed "$tmp" "git -C $wt switch main2"
check allowed "$tmp" "git -C $wt checkout -b fresh"
check allowed "$tmp" "cd $wt && git switch main2"

# Ordinary work stays open.
check allowed "$main" 'git status'
check allowed "$main" 'git checkout -- file.txt'
check allowed "$main" 'git checkout HEAD -- file.txt'
check allowed "$main" 'git checkout .'
check allowed "$main" 'git checkout ./src/file.txt'
check allowed "$main" 'git restore file.txt'
check allowed "$main" "git -C $main worktree add -b fresh $tmp/new origin/main"
check allowed "$main" 'git branch --list'
check allowed "$main" 'gh pr view 71'
check allowed "$main" 'gh pr create --title x'
check allowed "$main" 'gh api repos/a/b/pulls/1'
check allowed "$main" 'nix build .#server'
check allowed "$tmp" 'git switch other'

# Words that only mention these.
check allowed "$main" 'git commit -m "gh pr merge is the user'"'"'s"'
check allowed "$main" 'git commit -m "never git switch here"'
check allowed "$main" 'git commit -m "docs: run vercel --prod after review"'
check allowed "$main" 'grep -n nixos-rebuild flake.nix'
check allowed "$main" 'ls ship-release.sh'

# Without jq the hook refuses instead of reading nothing and letting the call through.
mkdir -p "$tmp/nojq"
printf '{"tool_name":"Bash","tool_input":{"command":"git status"}}' >"$tmp/plain.json"
PATH="$tmp/nojq" "$BASH" "$hook" "$tmp/plain.json" >"$tmp/output" 2>&1
[ $? -eq 2 ] || { echo "WRONG: without jq the hook let a call through"; failed=1; }

if [ "$failed" -eq 0 ]; then
  echo "user-only: all cases right"
fi
exit "$failed"
