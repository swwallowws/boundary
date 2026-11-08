# Working rules

These hold in every project of a workspace that uses boundary. A workspace's own `CLAUDE.md`
imports this file with `@<boundary>/rules/workspace.md` and adds what is personal to it: where
the notes live, names, writing style.

## Checking

- When a predicted failure is cheap to check, check it now instead of handing it back as "if this
  breaks, let me know". Either it's worth verifying now or it's not worth raising.
- Verify everything a script can check before asking the user to try something. Then ask for at
  most one short check with exact paths.
- Never say something works until the CI for that push has passed:
  `node <boundary>/scripts/wait-ci.mjs --sha <commit> <owner/repo>`. If a repo has no CI or CI
  didn't run on that change, say so.
- A page holds still while it's used. Text that changes (a label, a count, a status line) and
  controls that move never resize or shift anything else: give them fixed room. A control's
  label says what it will do and changes only when that does, never midway through a slider.
  Before showing a page or a mockup, run `node <boundary>/scripts/check-layout.mjs <page>`; mark
  anything meant to move with `data-moves`. It presses every button, so run it on mockups and
  test data only: it holds back requests that write, but mark any button with a real effect
  `data-no-press` too.

## Scope

- Do the obvious next steps of a request without a "go ahead?" round. Ask only for real decisions:
  deleting or overwriting the user's files, pushing, driving their apps or a genuine choice
  between outcomes.
- When the user agrees to a subset of what you proposed, do only that subset.
- When the user points to an image or message they already sent, treat it as the spec.
- The user runs merges and deploys. Give the exact commands. The `user-only` hook holds this.
- Never modify a production database on your own initiative. Only when asked, in that moment.

## Sessions and agents

- Prefer small reusable scripts over long inline one-liners for anything non-trivial.
- Build in the main session, with short updates as you go. A fresh agent reviews between tasks
  or after them: give it the code and the requirement, without your conclusion. Ask before
  delegating anything else.
- One session per checkout. Work on a branch in your own worktree. The `user-only` hook turns
  away branch changes in a main checkout.
- Follow `<boundary>/rules/permissions.md` for every command and point every subagent at it, so
  work runs without permission prompts. The `no-prompts` hook turns away the common misses.

## Commits

- The subject names what changed and the trap if there was one, in the words a later search
  would use.
- The body says why: what was wrong, what changed and what you ruled out.
- End the body with what ran, with numbers ("Ran: cargo test, 212 pass"). Then name what wasn't
  tested.

## Specs

- A design doc's requirements each end with their check: a command, a test's name, `manual: …` or
  `none` with the reason. `<boundary>/templates/design.md` is the shape.
- `<boundary>/scripts/spec-checks.sh <doc>` lists requirements without one. A spec isn't done
  until it passes. A `manual` or `none` check says why no command can do it.

## Where a rule lives

A rule is only as strong as the place it lives. When something has been said twice or broke without
anyone seeing it, move it to the strongest home that fits, in this order:

1. **A hook or a test**, when a machine can tell right from wrong.
2. **The repo's `AGENTS.md`**, with its reason and a check, when it is about one repo. Put it
   there in the same commit as the fix.
3. **The workspace's `CLAUDE.md`**, as one line, when it is about how to work everywhere.
4. **The user's notes**, when it is status or a personal fact, never a rule.

Memory is a staging area. A memory that is still true after a session gets promoted to one of
these homes and deleted. Memory loads only in sessions started from the same folder and has no
history, so a rule left there misses the sessions it applies to.

## Guards follow a project's shape

A guard costs time on every call, so it is earned by what a mistake would cost. Private data,
releases and deploys get guards from the start. Work in progress stays free until it holds
something worth guarding.

## Shared docs and to-dos

- When a shared doc is named for the work, keep it current. End any reply that changed something
  it tracks with one line naming the doc and whether it was updated.
- Write the user's to-dos as short numbered one-liners in order. The order carries the
  dependencies.
