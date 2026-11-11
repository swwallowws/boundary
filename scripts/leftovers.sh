#!/usr/bin/env bash
# Lists what finished work left behind in each repository, with the command that removes it.
# Exits 1 when something is left, 0 when nothing is, 2 on a bad argument.
#   scripts/leftovers.sh <checkout>...
#
# After `git fetch --prune`, a leftover is anything whose commits are all in origin's default
# branch:
# - a worktree other than the main checkout, with nothing uncommitted and not locked. One that
#   holds ignored files (a .env, recordings, node_modules) has them named: `worktree remove`
#   deletes them, so look first.
# - a local branch
# - a branch still on origin. Deleting it is a push, so it's the user's.
# Work in progress is shown and never counted: a worktree with uncommitted changes, unlanded
# commits or a lock, its branch, the branch the main checkout is on and a local branch with
# commits origin hasn't landed (its copy on origin stays too).
# A branch landed by squash or rebase has different commits on main, so it shows as not landed:
# this kit lands with merge commits (merge-when-green.sh, which deletes the branch on origin
# too). Look before deleting a long-lived branch that main happens to contain.
# Commands quote with single quotes: a backslash before a space stops on a permission prompt.

if [ $# -eq 0 ]; then
  echo "usage: leftovers.sh <checkout>..." >&2
  exit 2
fi

left=0
seen="|"

# quote <word>: the word as a shell argument, in single quotes when it needs any.
quote() {
  case "$1" in
    *[!A-Za-z0-9_./:@%+=-]*) printf "'%s'" "${1//\'/\'\\\'\'}" ;;
    *) printf %s "$1" ;;
  esac
}

# say <what> <command>: one leftover and how to remove it.
say() {
  echo "  $1"
  echo "    \$ $2"
  found=1
  left=1
}

# landed <ref>: every commit of <ref> is in the default branch on origin.
landed() { git -C "$main" merge-base --is-ancestor "$1" "$base" 2>/dev/null; }

for dir in "$@"; do
  # The repository's own first worktree record is its main checkout: right for linked worktrees
  # and bare repositories. A submodule's first record is its git folder under the superproject's
  # .git/modules, so a submodule is named by its own top level.
  main=$(git -C "$dir" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
  if [ -z "$main" ]; then
    echo "$dir: not a git checkout" >&2
    exit 2
  fi
  if [ -n "$(git -C "$dir" rev-parse --show-superproject-working-tree 2>/dev/null)" ]; then
    main=$(git -C "$dir" rev-parse --show-toplevel)
  fi
  case "$seen" in *"|$main|"*) continue ;; esac
  seen="$seen$main|"
  qmain=$(quote "$main")
  echo "== $main"

  if ! git -C "$main" fetch -q --prune origin; then
    echo "  can't fetch origin, so nothing was checked"
    left=1
    continue
  fi
  base=$(git -C "$main" symbolic-ref -q --short refs/remotes/origin/HEAD)
  [ -n "$base" ] || base=origin/main
  if ! git -C "$main" rev-parse -q --verify "$base" >/dev/null; then
    echo "  origin has no $base to compare with, so nothing was checked"
    left=1
    continue
  fi
  found=0
  current=$(git -C "$main" symbolic-ref -q --short HEAD)
  # Branches that belong to work in progress, as |name|name|.
  busy="|$current|"

  # Worktrees. The first record of `worktree list --porcelain` is the main checkout; each record
  # ends with a blank line.
  n=0
  path=""
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) path=${line#worktree }; head=""; branch=""; locked=""; gone="" ;;
      "HEAD "*) head=${line#HEAD } ;;
      "branch refs/heads/"*) branch=${line#branch refs/heads/} ;;
      locked*) locked=1 ;;
      prunable*) gone=1 ;;
      "")
        [ -n "$path" ] || continue
        n=$((n + 1))
        if [ "$n" -gt 1 ]; then
          on=""
          [ -n "$branch" ] && on=" on $branch"
          if [ -n "$locked" ]; then
            echo "  in progress: worktree $path$on (locked)"
            busy="$busy$branch|"
          elif [ -n "$gone" ]; then
            say "worktree $path$on: its folder is gone" "git -C $qmain worktree prune"
          elif [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
            echo "  in progress: worktree $path$on (uncommitted changes)"
            busy="$busy$branch|"
          elif [ -n "$head" ] && landed "$head"; then
            ignored=$(git -C "$path" status --porcelain --ignored 2>/dev/null | sed -n 's/^!! //p' | head -n 5 | tr '\n' ' ')
            if [ -n "$ignored" ]; then
              say "worktree $path$on: landed, but it holds ignored files (${ignored% }): look before removing" "git -C $qmain worktree remove $(quote "$path")"
            else
              say "worktree $path$on: landed" "git -C $qmain worktree remove $(quote "$path")"
            fi
          else
            echo "  in progress: worktree $path$on (not landed)"
            busy="$busy$branch|"
          fi
        fi
        path=""
        ;;
    esac
  done < <(git -C "$main" worktree list --porcelain; echo)

  # Local branches. A landed one is a leftover unless work in progress holds it.
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    [ "$b" = "${base#origin/}" ] && continue
    case "$busy" in *"|$b|"*) continue ;; esac
    if landed "refs/heads/$b"; then
      say "branch $b: landed" "git -C $qmain branch -D $(quote "$b")"
    else
      busy="$busy$b|"
    fi
  done < <(git -C "$main" for-each-ref --format='%(refname:lstrip=2)' refs/heads/)

  # Branches on origin, after --prune dropped the ones origin no longer has. One whose local
  # branch is still in progress stays.
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    [ "$b" = HEAD ] || [ "origin/$b" = "$base" ] && continue
    case "$busy" in *"|$b|"*) continue ;; esac
    say "on origin: $b: landed (deleting it is a push)" "git -C $qmain push origin --delete $(quote "$b")"
  done < <(git -C "$main" for-each-ref --merged "$base" --format='%(refname:lstrip=3)' refs/remotes/origin/)

  [ "$found" -eq 0 ] && echo "  nothing left"
done
exit "$left"
