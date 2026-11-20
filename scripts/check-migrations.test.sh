#!/usr/bin/env bash
# Checks that check-migrations.mjs fails a change that edits, removes or renames a migration and
# passes one that only adds, on throwaway repositories. Run from anywhere; exits non-zero if any
# case is wrong.

script="$(cd "$(dirname "$0")" && pwd)/check-migrations.mjs"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0
wrong() { echo "WRONG: $1"; failed=1; }

# repo <case>: a repository whose main holds two migrations, with a branch "work" off it.
repo() {
  r="$tmp/$1"
  git init -q -b main "$r"
  mkdir -p "$r/db/migrations"
  printf 'CREATE TABLE a (id INTEGER);\n' >"$r/db/migrations/0001_a.sql"
  printf 'CREATE TABLE b (id INTEGER);\n' >"$r/db/migrations/0002_b.sql"
  g add -A
  g commit -q -m base
  g switch -q -c work
}
g() { git -C "$r" -c user.name=t -c user.email=t@example.com "$@"; }
check() { (cd "$r" && node "$script" db/migrations "$1") >"$tmp/out" 2>&1; }
passes() { check "${2:-main}" || { cat "$tmp/out"; wrong "$1 failed"; }; }
fails() {
  check main && { cat "$tmp/out"; wrong "$1 passed"; }
  grep -qF -- "$2" "$tmp/out" || { cat "$tmp/out"; wrong "$1 didn't name $2"; }
}

repo added
printf 'CREATE TABLE c (id INTEGER);\n' >"$r/db/migrations/0003_c.sql"
g add -A
g commit -q -m add
passes "a new migration"

repo edited
printf 'CREATE TABLE a (id INTEGER, name TEXT);\n' >"$r/db/migrations/0001_a.sql"
g commit -q -am edit
fails "an edited migration" "changed: db/migrations/0001_a.sql"

repo removed
g rm -q db/migrations/0002_b.sql
g commit -q -m remove
fails "a removed migration" "removed: db/migrations/0002_b.sql"

repo renamed
g mv db/migrations/0002_b.sql db/migrations/0002_bee.sql
g commit -q -m rename
fails "a renamed migration" "removed: db/migrations/0002_b.sql"

repo elsewhere
printf 'changed\n' >"$r/README.md"
g add -A
g commit -q -m readme
passes "a change outside the folder"

# main gained a migration after the branch left it: never read as one the branch removed.
repo main-moved-on
printf 'x\n' >"$r/work.txt"
g add -A
g commit -q -m work
g switch -q main
printf 'CREATE TABLE d (id INTEGER);\n' >"$r/db/migrations/0003_d.sql"
g add -A
g commit -q -m main-adds
g switch -q work
passes "main gaining a migration since the branch left it"

repo first-push
printf 'CREATE TABLE a (id INTEGER, x TEXT);\n' >"$r/db/migrations/0001_a.sql"
g commit -q -am edit
passes "an all-zero base checks nothing" 0000000000000000000000000000000000000000
grep -qF "nothing checked" "$tmp/out" || { cat "$tmp/out"; wrong "first-push didn't say it checked nothing"; }

repo unknown-base
check deadbeef && wrong "an unknown base passed"
grep -qF "can't compare" "$tmp/out" || { cat "$tmp/out"; wrong "unknown-base didn't say why"; }

[ "$failed" -eq 0 ] && echo "check-migrations: all cases right"
exit "$failed"
