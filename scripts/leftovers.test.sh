#!/usr/bin/env bash
# Checks leftovers.sh on throwaway repositories with a local origin, so nothing touches GitHub:
# a clean checkout has nothing left; landed worktrees and branches, local and on origin, are
# listed with commands that remove them; work in progress and branches origin already deleted
# are not. Then it runs the printed commands and expects nothing left.

script="$(cd "$(dirname "$0")" && pwd)/leftovers.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0
wrong() { echo "WRONG: $1"; failed=1; }

# A clean git: no user config, hooks or signing from the machine running the test.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
q() { git -c init.defaultBranch=main "$@" -q; }

q init "$tmp/seed"
git -C "$tmp/seed" commit -q --allow-empty -m first
q clone --bare "$tmp/seed" "$tmp/origin.git"
q clone "$tmp/origin.git" "$tmp/a"
a="$tmp/a"

"$script" "$a" >"$tmp/out" 2>&1 || { cat "$tmp/out"; wrong "a clean checkout reported leftovers"; }
grep -q "nothing left" "$tmp/out" || { cat "$tmp/out"; wrong "a clean checkout didn't say nothing is left"; }

# feat: landed with a merge commit, still on origin, checked out in a worktree.
git -C "$a" switch -q -c feat
git -C "$a" commit -q --allow-empty -m feat
git -C "$a" push -q origin feat
git -C "$a" switch -q main
git -C "$a" merge -q --no-ff -m "land feat" feat
git -C "$a" push -q origin main
git -C "$a" worktree add -q "$tmp/wt feat" feat
# wip: a worktree with a commit that hasn't landed.
git -C "$a" worktree add -q -b wip "$tmp/wt-wip" main
git -C "$tmp/wt-wip" commit -q --allow-empty -m wip
# dirty: nothing committed yet, but a file in the making.
git -C "$a" worktree add -q -b dirty "$tmp/wt-dirty" main
echo draft >"$tmp/wt-dirty/draft.txt"
# gone: landed and pushed, then deleted on origin by someone else.
git -C "$a" push -q origin main:refs/heads/gone
git --git-dir="$tmp/origin.git" branch -q -D gone

# A second, clean repository checked after this one still says nothing is left in it.
q clone --bare "$tmp/seed" "$tmp/origin-b.git"
q clone "$tmp/origin-b.git" "$tmp/b"
"$script" "$a" "$tmp/b" >"$tmp/out" 2>&1
tail -n 1 "$tmp/out" | grep -q "nothing left" || { cat "$tmp/out"; wrong "a clean repository after one with leftovers didn't say nothing is left"; }
[ "$(grep -c "nothing left" "$tmp/out")" -eq 1 ] || { cat "$tmp/out"; wrong "a repository with leftovers also said nothing is left"; }
# Both with leftovers: neither says nothing is left.
git -C "$tmp/b" branch -q old main
"$script" "$a" "$tmp/b" >"$tmp/out" 2>&1
grep -q "nothing left" "$tmp/out" && { cat "$tmp/out"; wrong "a second repository with leftovers said nothing is left"; }
git -C "$tmp/b" branch -q -D old

"$script" "$a" >"$tmp/out" 2>&1 && { cat "$tmp/out"; wrong "leftovers returned success"; }
grep -q "worktree .*wt feat" "$tmp/out" || { cat "$tmp/out"; wrong "a landed worktree wasn't listed"; }
grep -q "branch feat" "$tmp/out" || { cat "$tmp/out"; wrong "a landed local branch wasn't listed"; }
grep -q "on origin: feat" "$tmp/out" || { cat "$tmp/out"; wrong "a landed branch still on origin wasn't listed"; }
grep -q "in progress: .*wt-wip" "$tmp/out" || { cat "$tmp/out"; wrong "an unlanded worktree wasn't shown as in progress"; }
grep -q "in progress: .*wt-dirty" "$tmp/out" || { cat "$tmp/out"; wrong "a worktree with uncommitted changes wasn't shown as in progress"; }
grep -q "branch wip" "$tmp/out" && { cat "$tmp/out"; wrong "an unlanded branch was listed as left over"; }
grep -q "gone" "$tmp/out" && { cat "$tmp/out"; wrong "a branch origin deleted was still listed"; }
grep -q "branch main\|on origin: main\|on origin: HEAD" "$tmp/out" && { cat "$tmp/out"; wrong "the default branch was listed"; }

# The printed commands remove everything listed, in the order printed.
grep '^    \$ ' "$tmp/out" | sed 's/^    \$ //' >"$tmp/cmds"
while IFS= read -r cmd; do
  eval "$cmd" >/dev/null 2>&1 || wrong "a printed command failed: $cmd"
done <"$tmp/cmds"
"$script" "$a" >"$tmp/out" 2>&1 || { cat "$tmp/out"; wrong "leftovers remained after running its commands"; }
grep -q "in progress: .*wt-wip" "$tmp/out" || { cat "$tmp/out"; wrong "the cleanup touched work in progress"; }

# Pointed at a worktree, it reports for the whole repository once.
"$script" "$tmp/wt-wip" >"$tmp/out" 2>&1 || { cat "$tmp/out"; wrong "pointing at a worktree reported leftovers"; }
[ "$(grep -c '^== ' "$tmp/out")" -eq 1 ] || { cat "$tmp/out"; wrong "pointing at a worktree didn't report its repository once"; }

# fresh <name>: a repository with its own origin and one commit, at $tmp/<name>.
fresh() {
  q clone --bare "$tmp/seed" "$tmp/$1-origin.git"
  q clone "$tmp/$1-origin.git" "$tmp/$1"
}
# land <repo> <branch>: a commit on <branch>, pushed, landed on main with a merge commit.
land() {
  git -C "$1" switch -q -c "$2"
  git -C "$1" commit -q --allow-empty -m "$2"
  git -C "$1" push -q origin "$2"
  git -C "$1" switch -q main
  git -C "$1" merge -q --no-ff -m "land $2" "$2"
  git -C "$1" push -q origin main
}

# A branch landed on origin that has a new local commit in a worktree stays, there and on origin.
fresh c
land "$tmp/c" again
git -C "$tmp/c" worktree add -q "$tmp/c-again" again
git -C "$tmp/c-again" commit -q --allow-empty -m "follow-up"
"$script" "$tmp/c" >"$tmp/out" 2>&1
grep -q "on origin: again" "$tmp/out" && { cat "$tmp/out"; wrong "a branch with unlanded local work was listed for deletion on origin"; }
# The same for the branch the main checkout is on.
git -C "$tmp/c" switch -q -c cur
git -C "$tmp/c" commit -q --allow-empty -m cur
git -C "$tmp/c" push -q origin cur
git -C "$tmp/c" switch -q main
git -C "$tmp/c" merge -q --no-ff -m "land cur" cur
git -C "$tmp/c" push -q origin main
git -C "$tmp/c" switch -q cur
"$script" "$tmp/c" >"$tmp/out" 2>&1
grep -q "cur" "$tmp/out" && { cat "$tmp/out"; wrong "the branch the main checkout is on was listed"; }

# A landed worktree holding ignored files is listed with them named, so nobody removes them blind.
fresh d
land "$tmp/d" keys
git -C "$tmp/d" worktree add -q "$tmp/d-keys" keys
echo .env >>"$tmp/d/.git/info/exclude"
echo SECRET=1 >"$tmp/d-keys/.env"
"$script" "$tmp/d" >"$tmp/out" 2>&1
grep -q "d-keys.*ignored.*\.env" "$tmp/out" || { cat "$tmp/out"; wrong "a worktree with ignored files didn't name them"; }

# A locked worktree is in progress, and so is its branch.
fresh e
land "$tmp/e" held
git -C "$tmp/e" worktree add -q "$tmp/e-held" held
git -C "$tmp/e" worktree lock "$tmp/e-held"
"$script" "$tmp/e" >"$tmp/out" 2>&1
grep -q "in progress: .*e-held.*locked" "$tmp/out" || { cat "$tmp/out"; wrong "a locked worktree wasn't shown as in progress"; }
grep -q "branch held" "$tmp/out" && { cat "$tmp/out"; wrong "a locked worktree's branch was listed"; }

# A tag named like a branch doesn't turn the branch's name into heads/<name>.
fresh f
land "$tmp/f" same
git -C "$tmp/f" tag same main
"$script" "$tmp/f" >"$tmp/out" 2>&1
grep -q "heads/\|remotes/" "$tmp/out" && { cat "$tmp/out"; wrong "an ambiguous name came out as heads/ or remotes/"; }
grep -q "branch same: landed" "$tmp/out" || { cat "$tmp/out"; wrong "a branch named like a tag wasn't listed by its name"; }

# A path with spaces is quoted, never backslashed (a backslash before a space prompts).
grep -q 'wt\\ ' "$tmp/cmds" && { cat "$tmp/cmds"; wrong "a path with spaces was backslashed"; }
grep -q "'[^']*wt feat'" "$tmp/cmds" || { cat "$tmp/cmds"; wrong "a path with spaces wasn't single-quoted"; }

# A submodule is checked as itself, not as the superproject.
fresh sub
land "$tmp/sub" subwork
fresh super
git -C "$tmp/super" -c protocol.file.allow=always submodule add -q "$tmp/sub-origin.git" inner 2>/dev/null
git -C "$tmp/super/inner" branch -q subwork origin/subwork
"$script" "$tmp/super/inner" >"$tmp/out" 2>&1
grep -q "^== .*/super/inner$" "$tmp/out" || { cat "$tmp/out"; wrong "a submodule wasn't reported as itself"; }
grep -q "branch subwork: landed" "$tmp/out" || { cat "$tmp/out"; wrong "a submodule's landed branch wasn't listed"; }

# A bare repository is reported as itself, not its parent folder.
q clone --bare "$tmp/seed" "$tmp/plain.git"
"$script" "$tmp/plain.git" >"$tmp/out" 2>&1
grep -q "^== .*/plain.git$" "$tmp/out" || { cat "$tmp/out"; wrong "a bare repository wasn't reported as itself"; }

"$script" >/dev/null 2>&1
[ $? -eq 2 ] || wrong "no checkout given didn't exit 2"
"$script" "$tmp/not-a-repo" >/dev/null 2>&1
[ $? -eq 2 ] || wrong "a folder that isn't a checkout didn't exit 2"

[ "$failed" -eq 0 ] && echo "leftovers: all cases right"
exit "$failed"
