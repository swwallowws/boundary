#!/usr/bin/env bash
# Checks that check-workflows.mjs fails every way a self-hosted job can be given a secret and
# passes the ways it can't. Run from anywhere; exits non-zero if any case is wrong.

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/check-workflows.mjs"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0
wrong() { echo "WRONG: $1"; failed=1; }

# workflow <case> <file>: the workflow on stdin becomes $tmp/<case>/.github/workflows/<file>.
workflow() {
  mkdir -p "$tmp/$1/.github/workflows"
  cat >"$tmp/$1/.github/workflows/$2"
}
passes() {
  node "$script" "$tmp/$1" >"$tmp/out" 2>&1 || { cat "$tmp/out"; wrong "$2 failed"; }
}
fails() {
  node "$script" "$tmp/$1" >"$tmp/out" 2>&1 && wrong "$2 passed"
  grep -q -- "$3" "$tmp/out" || { cat "$tmp/out"; wrong "$2 didn't say: $3"; }
}

# Tests on the desktop with no secret, the deploy with its secret on GitHub's runner.
workflow clean ci.yml <<'EOF'
name: CI
on: [push]
permissions:
  contents: read
jobs:
  test:
    runs-on: [self-hosted, desktop]
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      # secrets.SITE_TOKEN is for the deploy only, never here
      - run: npm test
        env:
          GH: ${{ secrets.GITHUB_TOKEN }}
  deploy:
    needs: test
    runs-on: ubuntu-latest
    env:
      TOKEN: ${{ secrets.SITE_TOKEN }}
    steps:
      - run: ./deploy.sh
EOF
passes clean "a desktop job without secrets beside a hosted deploy with one"

workflow job-env ci.yml <<'EOF'
jobs:
  deploy:
    runs-on: [self-hosted, desktop]
    env:
      FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
    steps:
      - run: flyctl deploy
EOF
fails job-env "a self-hosted job's env with a secret" "ci.yml:2: job deploy runs on a self-hosted runner and is given secrets.FLY_API_TOKEN"

workflow step-with ci.yml <<'EOF'
jobs:
  site:
    runs-on: self-hosted
    steps:
      - uses: some/action@0123456789012345678901234567890123456789
        with:
          token: ${{ secrets.SITE_DEPLOY_TOKEN }}
EOF
fails step-with "a step's with: on a self-hosted job" "is given secrets.SITE_DEPLOY_TOKEN"

workflow top-env ci.yml <<'EOF'
env:
  KEY: ${{ secrets.API_KEY }}
jobs:
  test:
    runs-on: [self-hosted, desktop]
    steps:
      - run: cargo test
EOF
fails top-env "a workflow-level env with a secret and a self-hosted job" "job test runs on a self-hosted runner and is given secrets.API_KEY"

workflow all-secrets ci.yml <<'EOF'
jobs:
  test:
    runs-on: [self-hosted, desktop]
    steps:
      - run: echo '${{ toJSON(secrets) }}' > all.json
      - run: echo "${{ secrets['ODD-NAME'] }}"
EOF
fails all-secrets "toJSON(secrets) and secrets[...] in a self-hosted job" "secrets), secrets\['ODD-NAME'\]"

workflow matrix ci.yml <<'EOF'
jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, self-hosted]
    runs-on: ${{ matrix.os }}
    steps:
      - run: ./test.sh
        env:
          T: ${{ secrets.T }}
EOF
fails matrix "a matrix that includes self-hosted, with a secret" "job test runs on a self-hosted runner and is given secrets.T"

workflow unplaceable ci.yml <<'EOF'
jobs:
  test:
    runs-on: ${{ vars.RUNNER }}
    steps:
      - run: ./test.sh
EOF
fails unplaceable "a runs-on that can't be placed" "job test runs on \${{ vars.RUNNER }}, which can't be placed"

workflow hosted-matrix ci.yml <<'EOF'
jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    env:
      T: ${{ secrets.T }}
    steps:
      - run: ./test.sh
EOF
passes hosted-matrix "a hosted matrix with a secret"

workflow two-files a.yml <<'EOF'
jobs:
  fine:
    runs-on: [self-hosted, desktop]
    steps:
      - run: true
EOF
workflow two-files b.yaml <<'EOF'
jobs:
  leaky:
    runs-on: [self-hosted, desktop]
    steps:
      - run: true
        env:
          X: ${{ secrets.X }}
EOF
fails two-files "a second workflow file, .yaml" "b.yaml:2: job leaky"
grep -q "job fine" "$tmp/out" && { cat "$tmp/out"; wrong "a clean job in another file was named"; }

mkdir -p "$tmp/none"
passes none "a repository with no workflows"
node "$script" "$here/.." >"$tmp/out" 2>&1 || { cat "$tmp/out"; wrong "boundary's own workflows failed"; }

[ "$failed" -eq 0 ] && echo "check-workflows: all cases right"
exit "$failed"
