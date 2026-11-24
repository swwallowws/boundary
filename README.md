# boundary

Rules that, when followed, allow freedom.

boundary is a small kit for working with coding agents. It puts the rules that matter where a
machine holds them: hooks at the boundary between the agent and its harness, a short `AGENTS.md`
per repo and one file of working rules for a whole workspace. With those limits in place, an
agent can run on its own without stopping on prompts or stepping on what is yours.

There is nothing to install. Clone it once and point your projects at it.

## What's in it

| Part | What it does |
|---|---|
| `rules/workspace.md` | Working rules for every project: checking, scope, sessions, commits, finishing, specs, where a rule lives, guards and shared docs. Imported by a workspace's `CLAUDE.md`. |
| `rules/permissions.md` | How to run commands so none of them stops on a permission prompt. |
| `templates/AGENTS.md` | A repo's map, the rules a change can break with no visible error and the checks to run per path. |
| `hooks/no-prompts.sh` | Turns away commands that would stop on a prompt (heredocs, `$(...)`, env-var prefixes, commands joined by `&&` or `;`...) before the prompt reaches you. |
| `hooks/user-only.sh` | Turns away what only you do (merging, plus the deploys and releases a project lists) and branch changes in a checkout another session may share. |
| `hooks/public-posts.sh` | Reads what would go out on a public GitHub repository (issues, pull requests, comments, the commits a push adds) whole and turns it away when it holds a private word (your home folder's path or a line of `.claude/private-words`) or comes in a shape it can't read whole. Releases, public gists and making a repository public stay yours. Refuses when it can't tell whether a repository is public. |
| `hooks/private-paths.sh` | Turns away the usual ways an agent reaches data a project keeps from it, including searches that reach it without naming it. |
| `templates/design.md` | A design doc for a step that's hard to reverse or spans sessions: today, design, requirements that each name their check, passes, status. |
| `scripts/spec-checks.sh` | Lists a design doc's requirements that name no check. Fails if there are any. |
| `scripts/check-layout.mjs` | Uses a page in headless Chrome (every slider, every button) and fails when changing text or a control moves or resizes anything else. |
| `scripts/wait-ci.mjs` | Waits for a commit's CI, on main or a pull request, before anyone says it works. |
| `scripts/merge-when-green.sh` | Merges a pull request once its CI is green, keeping a branch another pull request builds on. Yours to run: the hook turns it away from agents. |
| `scripts/check-workflows.mjs` | Fails when a GitHub Actions job that may run on a self-hosted runner is given a secret, since a runner kept between jobs lets one job's leftovers read the next one's. Any runner that isn't a GitHub-hosted label counts as self-hosted. Run it in each repository's CI. Reads YAML with a vendored parser (`scripts/vendor/`). |
| `scripts/leftovers.sh` | Lists what landed work left behind (worktrees, local branches, branches on origin) with the command that removes each. Fails while anything is left. |
| `scripts/check-migrations.mjs` | Fails when a change edits, removes or renames a database migration that already exists, since a live database has run it. Run it in CI. |
| `scripts/check-modules.mjs` | Fails when a JavaScript module doesn't parse, including pages no test imports. Run it in CI. |
| `templates/audit.md`, `scripts/audit-due.sh` | The brief fresh agents audit a project with, and the script that says when the next audit is due (monthly, or after 15 merged pull requests). |
| `init.sh` | Sets a project up: an `AGENTS.md` from the template and the hooks in `.claude/settings.json`. Never overwrites. |

Every hook has its test cases next to it. `./test.sh` runs them all. CI runs them on Linux and
macOS.

## Setup

Needs `bash`, `git` and `jq`. Without `jq` the hooks refuse every call, since they can't read
them. `hooks/public-posts.sh`, `scripts/wait-ci.mjs` and `scripts/audit-due.sh` also need a
signed-in `gh` (without it, posts and pushes to GitHub are refused), and the scripts `node`;
`scripts/link-status.sh` needs `curl`.

Clone boundary to a place agents treat as yours and run the hooks from there. That clone changes
only when you pull it, so an agent's edit can't change a guard without your review:

```sh
git clone https://github.com/swwallowws/boundary.git ~/.claude/boundary-live
~/.claude/boundary-live/init.sh path/to/project
```

Then fill in the project's `AGENTS.md` and, if it needs them, list its deploys and releases in
`.claude/user-only` and its private data in `.claude/private-paths`. The formats are at the top
of each hook. To change boundary itself, work in a second clone and open a pull request.

Once you merge one, `git -C ~/.claude/boundary-live pull` makes it live. Two lists keep both steps
yours. boundary's own
`.claude/user-only` turns away pushes to its main (and pushes that name no branch). A line in
your workspace's `.claude/user-only` turns away updates to the pinned copy:

```
updating the live guards: ([^[:space:];&|]*/)?git([[:space:]]+-c[[:space:]]+[^[:space:];&|]+)*[[:space:]]+-C[[:space:]]+[^[:space:];&|]*boundary-live[^[:space:];&|]*[[:space:]]+(pull|merge|reset|checkout|switch|rebase|cherry-pick|am|apply|restore|stash|clean|rm|mv|commit)([[:space:]]|$)
updating the live guards: cd[[:space:]]+[^;&|]*boundary-live[^;&|]*[;&|]+[[:space:]]*git([[:space:]]+-c[[:space:]]+[^[:space:];&|]+)*[[:space:]]+(pull|merge|reset|checkout|switch|rebase|cherry-pick|am|apply|restore|stash|clean|rm|mv|commit)([[:space:]]|$)
```

A workspace that is itself a repository can guard its own main the same way with
`.claude/user-only.repo`. A list there holds only for that repository, never for the project
repositories inside it.

An edit made with a file tool doesn't pass through these hooks. `git -C <pinned copy> status`
shows it, so check that from time to time.

For a workspace (a folder of projects), its `CLAUDE.md` imports the working rules and keeps what
is personal:

```markdown
boundary is at ~/.claude/boundary-live.
@~/.claude/boundary-live/rules/workspace.md

## Writing
- ...your own style rules...
```

## Where a rule lives

A rule is only as strong as the place it lives. When something has been said twice or broke without
anyone seeing it, it moves to the strongest home that fits:

1. **A hook or a test**, when a machine can tell right from wrong.
2. **The repo's `AGENTS.md`**, with its reason and a check, when it is about one repo.
3. **The workspace's `CLAUDE.md`**, as one line, when it is about how to work everywhere.
4. **Your notes**, when it is status or a personal fact.

Agent memory is a staging area. It loads only in sessions started from the same folder and keeps
no history, so a rule left there misses the sessions it applies to.

## Guards follow a project's shape

A guard costs time on every call, so it is earned by what a mistake would cost. Private data,
releases and deploys get guards from the start. Work in progress stays free until it holds
something worth guarding.

## What it caught

Each piece is here because something went wrong without it, in one person's projects, October
and November 2026, with Claude Code and Opus 5.5:

- **Two sessions shared one checkout.** One moved the branch mid-task and the other's fixes
  landed in its work. Nothing was lost. `user-only.sh` now sends branch changes in a main checkout
  to a worktree.
- **The guards' first review.** A fresh agent, given the code and the requirements, found 15
  commands that got past the first version of the hooks (a quoted folder name, `git status &&`
  before a private script, an absolute path to `gh`...) and two that were wrongly blocked. Each
  is a test case now.
- **A rule in memory missed its session.** "Ask before spawning agents" sat in one folder's
  memory, so a session started in a project folder never loaded it and spawned agents. That is
  why memory is only a staging area here.
- **A guard caught its own author.** The private-data hook blocked the agent's own recursive
  search the moment it was written. Its test cases found a bug in the hook.
- **A rule that could never pass.** A repo's instructions listed a lint command that failed on
  vendored code at every commit. Running it showed that. A check is trusted once it has run.
- **A map that stopped following the app.** Writing a repo's first `AGENTS.md` found the file
  that tells its built-in assistant how the app is laid out had not changed in six days of new features.
- **A push to a public repo.** Asked to push two branches, the agent pushed one to a repository
  that turned out to be a public site, without checking. Nothing deployed and the branch was
  deleted. A repository's `.claude/user-only` can now make pushing the user's. Its lists
  follow `git -C` and worktrees.
- **Guards anyone could edit.** The live hooks ran from the same clone agents work in. Running
  them from a pinned copy came from a second agent's review of the setup.
- **Guards that would never start.** Every hook began with `#!/bin/bash`, which NixOS doesn't
  have. Moving the workspace to a NixOS machine would have switched every guard off, since Claude
  Code lets a command through when its hook can't run. They start through `env` now. The
  tests check every script's first line.
- **The second review.** Before going public, another fresh agent found two holes. Without `jq`
  every hook read nothing and let everything through. `git push origin main:main` or `HEAD`
  reached a main the docs called the user's. The hooks now refuse when they can't read a call.
  boundary's list matches a push by where it lands. Both are test cases now. It also caught this
  README claiming more than the tests held, in several places.
- **A CI check that could never find a pull request's run.** `wait-ci.mjs` listed only main's
  runs, so asking about a pull request's commit always said "no run found".
- **A green run that belonged to main.** Asked about `--sha HEAD` from a branch, `wait-ci.mjs`
  passed `HEAD` to GitHub, which reads it as its default branch. It reported main's green run as
  the branch's. A name is now resolved in the checkout it was typed in, and a test with a
  stand-in `gh` holds it.
- **A merge that closed the next pull request.** Two pull requests were stacked, the second
  based on the first's branch. Merging the first with `--delete-branch` deleted that base, and
  GitHub closed the second instead of moving it to main. `merge-when-green.sh` keeps a branch
  another pull request builds on. It exists because private repositories can't require checks
  without a paid plan, so nothing stopped a merge on red CI either.
- **Branches nobody deleted.** One round of work landed its pull requests across seven
  repositories with plain `gh pr merge`, and every branch stayed behind, on GitHub and locally.
  A cleanup by hand afterwards removed 15. A first run of `leftovers.sh` then found 10 more
  landed branches that the hand cleanup had missed, several from that same session. Finishing
  is a rule now. The script is its check, and `merge-when-green.sh` is the land command, since
  it deletes the branch itself.
- **A button that changed its mind halfway.** In two projects' studies, a play button renamed
  itself ("Go" to "Come back") as a slider passed its middle, and its new width shoved the slider
  sideways. The user read it as the page breaking. `check-layout.mjs` now drives every control
  and names anything that moves.
- **A deploy secret on a shared runner.** When CI moved onto a self-hosted runner, a deploy job
  briefly went with it, token and all. The runner stays up between jobs,
  so a process a test job left behind could have read that token. The deploy went back to a
  hosted runner, and the rule lived only in a comment until `check-workflows.mjs` made it a
  failing check in each repository's CI. Run on the earlier workflow, it names the job and the
  secret. Its first version read YAML as lines and looked for the word "self-hosted". A fresh
  agent asked to get a secret past it found 20 ways, from a custom runner label to YAML anchors,
  and 3 ordinary workflows it failed wrongly. It now parses the YAML and treats every runner
  that isn't a GitHub-hosted label as self-hosted. A second, independent attack on that version
  found 4 more (a `}}` inside a quoted string, a secret in a mapping key, a matrix `include`
  written as an expression, and label patterns looser than GitHub's own list) and 2 wrong
  failures. Every one is a test case.
- **An audit that found what reviews of each change didn't.** Fresh agents reading a whole
  project side by side found dozens of things that reviews of single pull requests had let
  through, some of them real bugs. `templates/audit.md` is their brief, and `audit-due.sh` says
  when the next audit is due.
- **A migration rule held only by a note.** A repository's rules said never to edit an applied
  migration, since the live server won't start; the only check was a `git diff` to remember.
  `check-migrations.mjs` is that check in CI.
- **A syntax check that could never fail.** A CI check that every page parses used
  `node --check`, which passes a broken file with an `import` or `export` when no package says
  `"type": "module"`. A fresh review showed it with a one-line broken file. `check-modules.mjs`
  reads each file as a module and its test holds that file.
- **A rule that was safe only in the repository it was checked in.** A rule to track work in
  GitHub issues was checked against one private repository and then written for every project,
  public ones included. A second agent caught it. `public-posts.sh` now asks GitHub before
  anything is posted or pushed, and on a public repository reads it whole for private words
  first. An attack on its first version found a dozen honest ways past it, from a body on its
  second line to gh's own aliases; each is a test case, and shapes it can't read are refused.
- **A test that passed without its fix.** A new test reached its result through a path where
  older code gave the same answer, so it passed with the fix removed. A fresh review caught it.
  The rule now: run a fix's test once with the fix taken out.

These are anecdotes from one author's work. Nothing here is a controlled measurement.

## What it can't do

- The hooks read command text. A reworded command, `eval` or a script can do what a hook
  turns away. They catch honest mistakes. Anything that truly mustn't happen needs enforcement
  the agent can't touch: encryption, file permissions, a token that can't merge.
- A guard is only as safe as the folder it runs from. If an agent can edit the hooks that run,
  it can change what they allow. Run them from a pinned copy (see Setup) and check it from time
  to time.
- `.claude/user-only` lists are read from the folder the session started in, the repository a
  command runs in, any repository it names with `git -C`, a worktree's main checkout and every
  folder above these. `.claude/private-paths` lists are read from the session's folder and the
  repository the session runs in, with the folders above them. So a Read of one project's files
  from a session started in another isn't covered.
- `public-posts.sh` knows GitHub only. A remote on another host isn't checked, and a post made
  another way (a script, the GitHub website, `curl` to the API) isn't seen. It finds the words
  you list, as written: a name spelled another way or split by an escape (`Jane\ Doe`) gets
  through, and it can't tell a security finding or a detail that reveals too much from any other
  sentence. It reads only commits the checkout knows the remote lacks, so fetch before pushing.
  A repository named only by `-R`, with no checkout here, brings no list of its own. A commit
  message quoting `; gh release create` is refused, on the safe side.
- Pushes are matched by their text too. A protected main on GitHub holds against every spelling
  of a push; a list holds against the spellings its pattern knows.
- The rules files are still instructions. Only the hooks and tests are enforced.

## Credits

- **[dotplan](https://github.com/jamesondh/dotplan)** by Jameson Hodge: the shape of
  `templates/AGENTS.md` (map, rules with reasons and checks, a checks table), its "Working here"
  rules, adding a rule from each unseen failure and commit messages that carry the reason. dotplan
  is the measured one; read it first.
- **Lamis Mukta, "Learning while you sleep"** (AI Native DevCon, June 2026): do anything at the
  boundary between agent and harness deterministically. Start with simple markdown files.
  The name comes from there.
- **Claude Code's documentation** on permissions, permission modes, subagents and settings, which
  `rules/permissions.md` is built from.

Written with Claude Code.
