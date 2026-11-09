# boundary

A kit of rules, hooks and templates for working with coding agents. The README says what it is
for; this file is for working on it.

## Working here

1. Do what was asked, the simplest way that meets it. Side work is a proposal that says what it costs.
2. If the work grows well past what you expected, stop and say so.
3. Run `./test.sh` before every commit and report its lines.
4. A commit's subject names what changed and the trap if there was one. Its body says why, what ran
   and what wasn't tested.
5. When something breaks and nobody saw it, add a test case or a rule here in the same commit as
   the fix.
6. The user pushes, merges and decides when this goes public.

## Map

- `rules/workspace.md`: working rules a workspace's `CLAUDE.md` imports
- `rules/permissions.md`: commands that run without permission prompts
- `templates/AGENTS.md`: what `init.sh` copies into a project
- `docs/guards/`: the guards' design, each requirement tied to the test case that holds it
  (`./test.sh` runs spec-checks on every `docs/*/README.md`)
- `templates/design.md`: the design-doc shape; `scripts/spec-checks.sh` (with its test) checks
  every requirement names a check
- `hooks/<name>.sh` and `hooks/<name>.test.sh`: each hook with its cases
- `scripts/`: `wait-ci.mjs` (CI before "done"), `link-status.sh` and `check-layout.mjs` (a page
  holds still while it's used; its test pages are in `scripts/check-layout/`)
- `init.sh`, `init.test.sh`: setting a project up
- `test.sh`: runs every test; CI (`.github/workflows/checks.yml`) runs it on Linux and macOS
- `.claude/user-only`: this repo's own list. Pushes to main are the user's; push a named branch
  and open a pull request

## Rules

**Every hook change comes with cases.** A hook that turns away too little fails silently and one
that turns away too much stops work. Add a blocked and an allowed case for each change.
Check: `./test.sh`.

**Every script starts with `#!/usr/bin/env bash`.** NixOS has no `/bin/bash`. A hook that
can't start lets the command it guards through, with no warning. Check: `./test.sh` checks the
first line of every script.

**Hooks run on macOS's bash 3.2 and BSD tools.** On a Mac, `env bash` finds bash 3.2: no
`mapfile`, associative arrays or `${x,,}`. Its `sed` and `grep` are BSD's. Check: CI's macOS job.

**A hook exits 2 to block and 0 otherwise.** Any other exit code lets the call through with an
error, so a hook that crashes guards nothing. Check: the test cases expect exactly 2 or 0.

**The kit holds no one's paths.** It is meant to go public. Personal paths, names and project
details go in the workspace's own files and the per-project lists. Check: `grep -rn /Users .`
prints only this line's own mention in AGENTS.md.

**The formats live at the top of each hook.** `init.sh` and the README point there, so a change
to a list's format changes that comment in the same commit. Check: manual.

**Credit what came from elsewhere.** Add it to the README's Credits when an idea or a piece of text
comes from someone's work. Check: manual.

**Shellcheck passes at warning level.** CI fails on any warning or error. Info-level notes about
`$(`, backticks or `;&|` in single quotes are the hooks matching those as text, on purpose.
Check: CI's shellcheck job.

## Checks

| Changed | Run |
|---|---|
| anything | `./test.sh` |
| `scripts/wait-ci.mjs` | `scripts/wait-ci.test.sh` (in `./test.sh`), then `node scripts/wait-ci.mjs --sha <a PR's commit> <owner/repo>` finds its run on GitHub |
