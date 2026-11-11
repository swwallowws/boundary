#!/usr/bin/env bash
# Checks that check-workflows.mjs fails every way a job that may run on a self-hosted runner can
# be given a secret, and passes the ways it can't. The bypass cases came from a fresh agent asked
# to get a secret past the first, line-based version: all of them passed it. Run from anywhere;
# exits non-zero if any case is wrong.

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/check-workflows.mjs"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0
wrong() { echo "WRONG: $1"; failed=1; }

# workflow <case> [file]: the workflow on stdin becomes $tmp/<case>/.github/workflows/<file>.
workflow() {
  mkdir -p "$tmp/$1/.github/workflows"
  cat >"$tmp/$1/.github/workflows/${2:-ci.yml}"
}
passes() {
  node "$script" "$tmp/$1" >"$tmp/out" 2>&1 || { cat "$tmp/out"; wrong "$1 failed: $2"; }
}
# fails <case> <what> [text the report must contain, default "job deploy"]
fails() {
  node "$script" "$tmp/$1" >"$tmp/out" 2>&1 && wrong "$1 passed: $2"
  grep -qF -- "${3:-job deploy}" "$tmp/out" || { cat "$tmp/out"; wrong "$1 didn't say ${3:-job deploy}: $2"; }
}

# --- Passes ---

workflow clean <<'EOF'
name: CI
on: [push]
jobs:
  test:
    runs-on: [self-hosted, desktop]
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      # secrets.SITE_TOKEN is for the deploy only, never here
      - run: test ! -e secrets.json && npm test
        env:
          GH: ${{ secrets.GITHUB_TOKEN }}
          GH2: ${{ secrets['github_token'] }}
  deploy:
    needs: test
    if: github.repository_owner != 'self-hosted-mirror'
    runs-on: ubuntu-latest
    env:
      TOKEN: ${{ secrets.SITE_TOKEN }}
    steps:
      - run: ./deploy.sh
EOF
passes clean "desktop tests without secrets (a file named secrets.json, GITHUB_TOKEN spelled two ways), a hosted deploy with one"

workflow hosted-matrix <<'EOF'
jobs:
  deploy:
    strategy:
      matrix:
        os: [ubuntu-24.04, macos-15, windows-2025]
        include:
          - os: ubuntu-24.04-arm
    runs-on: ${{ matrix.os }}
    env:
      T: ${{ secrets.T }}
    steps:
      - run: ./test.sh
EOF
passes hosted-matrix "a matrix of hosted labels, include too, with a secret"

workflow local-call-hosted <<'EOF'
jobs:
  deploy:
    uses: ./.github/workflows/deploy.yml
    secrets: inherit
EOF
workflow local-call-hosted deploy.yml <<'EOF'
on: workflow_call
jobs:
  push:
    runs-on: ubuntu-latest
    steps:
      - run: ./push.sh
        env:
          T: ${{ secrets.T }}
EOF
passes local-call-hosted "secrets: inherit to a local workflow whose jobs are all hosted"

mkdir -p "$tmp/none"
passes none "a repository with no workflows"
node "$script" "$here/.." >"$tmp/out" 2>&1 || { cat "$tmp/out"; wrong "boundary's own workflows failed"; }

# --- Fails: where the job runs ---

workflow job-env <<'EOF'
jobs:
  deploy:
    runs-on: [self-hosted, desktop]
    env:
      FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
    steps:
      - run: flyctl deploy
EOF
fails job-env "a self-hosted job's env with a secret" "job deploy may run on a self-hosted runner"

workflow custom-label <<'EOF'
jobs:
  deploy:
    runs-on: [linux, desktop]
    env:
      T: ${{ secrets.T }}
    steps:
      - run: ./deploy.sh
EOF
fails custom-label "a custom label list without the word self-hosted"

workflow lookalike <<'EOF'
jobs:
  deploy:
    runs-on: ubuntu-desktop
    env:
      T: ${{ secrets.T }}
    steps:
      - run: ./deploy.sh
EOF
fails lookalike "a custom label shaped like a hosted one"

workflow group <<'EOF'
jobs:
  deploy:
    runs-on:
      group: desktops
    env:
      T: ${{ secrets.T }}
    steps:
      - run: ./deploy.sh
EOF
fails group "a runner group"

workflow case <<'EOF'
jobs:
  deploy:
    runs-on: [Self-Hosted, desktop]
    env:
      T: ${{ secrets.T }}
    steps:
      - run: ./deploy.sh
EOF
fails case "Self-Hosted in another case"

workflow matrix-include <<'EOF'
jobs:
  deploy:
    strategy:
      matrix:
        os: [ubuntu-latest]
        include:
          - os: desktop
    runs-on: ${{ matrix.os }}
    env:
      T: ${{ secrets.T }}
    steps:
      - run: ./deploy.sh
EOF
fails matrix-include "a matrix whose include adds a custom label"

workflow expr-line <<'EOF'
jobs:
  deploy:
    runs-on:
      - ${{ vars.RUNNER }}
    env:
      T: ${{ secrets.T }}
    steps:
      - run: ./deploy.sh
EOF
fails expr-line "an expression on its own line under runs-on"

workflow expr-hosted-word <<'EOF'
jobs:
  deploy:
    runs-on: ${{ vars.RUNNER }}
    steps:
      - run: echo "the image used to be ubuntu-22.04"
        env:
          T: ${{ secrets.T }}
EOF
fails expr-hosted-word "an expression runner with a hosted name elsewhere in the job"

workflow deep-indent <<'EOF'
jobs:
    deploy:
        runs-on: ${{ vars.RUNNER }}
        env:
            T: ${{ secrets.T }}
        steps:
            - run: ./deploy.sh
EOF
fails deep-indent "jobs indented four spaces, keys eight"

# --- Fails: reusable workflows ---

workflow remote-inherit <<'EOF'
jobs:
  deploy:
    uses: some-org/infra/.github/workflows/deploy.yml@0123456789012345678901234567890123456789
    secrets: inherit
EOF
fails remote-inherit "secrets: inherit to a workflow in another repository"

workflow remote-mapping <<'EOF'
jobs:
  deploy:
    uses: some-org/infra/.github/workflows/deploy.yml@0123456789012345678901234567890123456789
    secrets:
      T: ${{ secrets.T }}
EOF
fails remote-mapping "a secrets mapping to a workflow in another repository"

workflow local-call-input <<'EOF'
jobs:
  deploy:
    uses: ./.github/workflows/deploy.yml
    with:
      runner: self-hosted
    secrets: inherit
EOF
workflow local-call-input deploy.yml <<'EOF'
on:
  workflow_call:
    inputs:
      runner:
        type: string
jobs:
  push:
    if: inputs.runner != 'macos-latest'
    runs-on: ${{ inputs.runner }}
    steps:
      - run: ./push.sh
        env:
          T: ${{ secrets.T }}
EOF
fails local-call-input "secrets: inherit to a local workflow whose runner is an input"
grep -qF "job push may run on a self-hosted runner" "$tmp/out" || { cat "$tmp/out"; wrong "the called workflow's own job wasn't named"; }

# --- Fails: how the secret is named ---

workflow step-with <<'EOF'
jobs:
  deploy:
    runs-on: self-hosted
    steps:
      - uses: some/action@0123456789012345678901234567890123456789
        with:
          token: ${{ secrets.SITE_DEPLOY_TOKEN }}
EOF
fails step-with "a step's with: on a self-hosted job" "secrets.SITE_DEPLOY_TOKEN"

workflow top-env <<'EOF'
env:
  KEY: ${{ secrets.API_KEY }}
jobs:
  deploy:
    runs-on: [self-hosted, desktop]
    steps:
      - run: cargo test
EOF
fails top-env "a workflow-level env with a secret" "secrets.API_KEY"

workflow hash-in-string <<'EOF'
jobs:
  deploy:
    runs-on: self-hosted
    env:
      T: "x #${{ secrets.T }}"
    steps:
      - run: ./deploy.sh
EOF
fails hash-in-string "a # before the secret inside a quoted string" "secrets.T"

workflow star <<'EOF'
jobs:
  deploy:
    runs-on: self-hosted
    env:
      T: ${{ join(secrets.*, ' ') }}
    steps:
      - run: ./deploy.sh
EOF
fails star "join(secrets.*)" "secrets.*"

workflow all-secrets <<'EOF'
jobs:
  deploy:
    runs-on: [self-hosted, desktop]
    steps:
      - run: echo '${{ toJSON(secrets) }}' > all.json
      - run: echo "${{ secrets['ODD-NAME'] }}"
EOF
fails all-secrets "toJSON(secrets) and secrets[...]" "secrets['ODD-NAME']"

workflow context-case <<'EOF'
jobs:
  deploy:
    runs-on: self-hosted
    env:
      T: ${{ Secrets.T }}
    steps:
      - run: ./deploy.sh
EOF
fails context-case "Secrets.T in another case" "Secrets.T"

workflow token-lookalike <<'EOF'
jobs:
  deploy:
    runs-on: self-hosted
    env:
      T: ${{ secrets.GITHUB_TOKEN_ADMIN }}
    steps:
      - run: ./deploy.sh
EOF
fails token-lookalike "a secret named like GITHUB_TOKEN" "GITHUB_TOKEN_ADMIN"

workflow anchors <<'EOF'
jobs:
  build:
    runs-on: ubuntu-latest
    env: &e
      T: ${{ secrets.T }}
    steps:
      - run: ./build.sh
  deploy:
    runs-on: self-hosted
    env: *e
    steps:
      - run: ./deploy.sh
EOF
fails anchors "an alias carrying a secret into a self-hosted job" "secrets.T"
grep -qF "job build" "$tmp/out" && { cat "$tmp/out"; wrong "anchors: the hosted job was named"; }

workflow merge-key <<'EOF'
x-shared: &shared
  env:
    T: ${{ secrets.T }}
jobs:
  deploy:
    <<: *shared
    runs-on: self-hosted
    steps:
      - run: ./deploy.sh
EOF
fails merge-key "a merge key carrying a secret" "secrets.T"

# --- Fails: layouts a line reader misses ---

workflow quoted-job <<'EOF'
jobs:
  "deploy":
    runs-on: self-hosted
    env: {T: "${{ secrets.T }}"}
    steps: [{run: ./deploy.sh}]
EOF
fails quoted-job "a quoted job name"

workflow anchored-job <<'EOF'
jobs:
  deploy: &d
    runs-on: self-hosted
    env:
      T: ${{ secrets.T }}
    steps:
      - run: ./deploy.sh
EOF
fails anchored-job "an anchor on the job name"

workflow flow <<'EOF'
jobs: {deploy: {runs-on: self-hosted, env: {T: "${{ secrets.T }}"}, steps: [{run: ./deploy.sh}]}}
EOF
fails flow "jobs in flow style"

workflow quoted-jobs <<'EOF'
"jobs":
  deploy:
    runs-on: self-hosted
    env:
      T: ${{ secrets.T }}
    steps:
      - run: ./deploy.sh
EOF
fails quoted-jobs "a quoted jobs key"

workflow space-colon <<'EOF'
jobs :
  deploy :
    runs-on : self-hosted
    env :
      T : ${{ secrets.T }}
    steps :
      - run : ./deploy.sh
EOF
fails space-colon "a space before every colon"

workflow crlf <<'EOF'
jobs:
  deploy:
    runs-on: self-hosted
    env:
      T: ${{ secrets.T }}
    steps:
      - run: ./deploy.sh
EOF
awk '{ printf "%s\r\n", $0 }' "$tmp/crlf/.github/workflows/ci.yml" >"$tmp/crlf.yml"
mv "$tmp/crlf.yml" "$tmp/crlf/.github/workflows/ci.yml"
grep -q $'\r' "$tmp/crlf/.github/workflows/ci.yml" || wrong "crlf: the fixture has no CR"
fails crlf "CRLF line endings"

workflow two-files a.yml <<'EOF'
jobs:
  fine:
    runs-on: [self-hosted, desktop]
    steps:
      - run: true
EOF
workflow two-files b.yaml <<'EOF'
jobs:
  deploy:
    runs-on: [self-hosted, desktop]
    steps:
      - run: true
        env:
          X: ${{ secrets.X }}
EOF
fails two-files "a second workflow file, .yaml" "b.yaml: job deploy"
grep -qF "job fine" "$tmp/out" && { cat "$tmp/out"; wrong "two-files: a clean job in another file was named"; }

# --- Fails: what can't be read ---

workflow broken <<'EOF'
jobs:
  deploy:
    runs-on: self-hosted
      env: [
EOF
fails broken "invalid YAML" "can't read it as YAML"

workflow no-jobs <<'EOF'
name: nothing here
on: [push]
EOF
fails no-jobs "a workflow with no jobs" "has no jobs"

[ "$failed" -eq 0 ] && echo "check-workflows: all cases right"
exit "$failed"
