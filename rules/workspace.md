# Working rules

These hold in every project of a workspace that uses boundary. A workspace's own `CLAUDE.md`
imports this file with `@<boundary>/rules/workspace.md` and adds what is personal to it: where
the notes live, names, writing style.

## Checking

- When a predicted failure is cheap to check, check it now instead of handing it back as "if this
  breaks, let me know". Either it's worth verifying now or it's not worth raising.
- Verify everything a script can check before asking the user to try something. Then ask for at
  most one short check with exact paths.
- A test written for a fix must fail without it. Run it once with the fix taken out and say that
  it failed. A test that passes either way guards nothing.
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
- The user runs merges and deploys. Give the exact commands. The `user-only` hook holds this. To
  land a pull request, the command is `<boundary>/scripts/merge-when-green.sh <number> <owner/repo>`:
  it waits for green CI and deletes the branch on origin.
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

## Finishing

- Work isn't done while it leaves things behind. Once it has landed, run
  `<boundary>/scripts/leftovers.sh <checkout>...` on every repository it touched. Remove the
  worktrees and local branches it lists, stop the servers and background tasks you started and
  delete your scratch scripts. A worktree it says holds ignored files gets a look first, since
  removing it deletes them. Deleting a branch on origin is a push, so give the user those
  commands. Say it's done when the script prints "nothing left" for each repository.

## Issues and audits

- Work is tracked in the repository's GitHub issues: one issue per piece of work, opened when it
  becomes work (ideas stay in the user's notes until then). A pull request says `Closes #<n>` for
  each issue it finishes.
- Each project gets an audit about monthly, or sooner after many merges:
  `<boundary>/scripts/audit-due.sh <owner/repo>` says when. Fresh agents read its parts with
  `<boundary>/templates/audit.md`. Each finding is checked against the code and the user chooses
  what to keep. The audit gets a record issue labelled `audit`, and each kept finding its own.

## Public repositories

- Everything in a public repository can be read by anyone: its issues, pull requests, comments,
  releases and every pushed commit's message and code. Keep personal details out of them. A
  security finding goes to the user only, never into an issue.
- Issues, pull requests and pushes for work agreed with the user go out as on any repository.
  The `public-posts` hook reads them first and turns them away when they hold a private word:
  the home folder's path or a line of a `.claude/private-words` list. Releases, public gists and
  making a repository public stay the user's. It refuses when it can't tell whether a
  repository is public.

## CI

- A repository with database migrations runs
  `node <boundary>/scripts/check-migrations.mjs <folder> <base>` in CI: an applied migration may
  only be added to. `<base>` is `HEAD^1` on a pull request (GitHub's merge commit) and
  `github.event.before` on a push, with `fetch-depth: 0` on the checkout.
- A repository with JavaScript modules that run in a browser runs
  `node <boundary>/scripts/check-modules.mjs <folder>...` in CI, so a page no test imports still
  has to parse. Give it folders of modules only: it reads every `.js` file as a module.

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
