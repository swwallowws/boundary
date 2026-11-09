# Guards

The hooks that keep merges, deploys, releases, private data and branch changes the user's, and
the setup that keeps the hooks themselves out of an agent's reach.

## Status

| Pass | State |
|---|---|
| 1. The three hooks with test cases | done (#1 to #3) |
| 2. Lists that follow `git -C`, worktrees and a repo's own main | done (#1, #2, #4) |
| 3. Hooks that start on any machine | done (#3) |
| 4. Lint for the hooks | done (#5) |

## Today

Three PreToolUse hooks (`hooks/no-prompts.sh`, `hooks/user-only.sh`, `hooks/private-paths.sh`)
read the command or the path a tool names and exit 2 to block. What only the user runs and what
stays private are listed per project in `.claude/user-only`, `.claude/user-only.repo` and
`.claude/private-paths`. A workspace runs the hooks from a pinned clone that changes only when the
user pulls it.

## Design

- **Text, honestly.** The hooks read command text, so they catch honest mistakes. A script,
  `eval` or a spelling a pattern doesn't know gets through. Anything that truly mustn't happen
  needs enforcement the agent can't touch (encryption, permissions, a protected branch, a token
  that can't merge). That limit has no check by design: the README says so.
- **Refuse blind.** A hook that can't read its call (no `jq`) refuses it. Reading nothing would
  match nothing and let everything through.
- **Lists follow the work.** A list reaches every command it should: from the session's folder,
  the command's repository, any repository `git -C` names, a worktree's main checkout and every
  folder above these. A `.repo` list is the exception: it holds only for its own repository.
- **A guard that can't start is no guard.** Claude Code lets a command through when its hook
  fails to run, so the hooks start through `env` and run from paths that exist on every machine.
- **Guarded guards.** The pinned clone changes only by the user's pull. Pushes that could land on
  boundary's main are the user's, in every spelling the list knows.

## Requirements

- R1. Merging a pull request is always the user's, plain, as `gh api` calls or through `scripts/merge-when-green.sh`. Check: `hooks/user-only.test.sh` ("Merging, always")
- R2. A listed command is the user's however it starts: plain or after `sudo`, `env`, an assignment or `nohup`. The same holds when `bash`, `sh -c` or `zsh -c` runs it. Check: `hooks/user-only.test.sh` ("Run through a shell or a wrapper")
- R3. Lists apply from the workspace above a project and from the repository a command runs in. Outside both they don't. Check: `hooks/user-only.test.sh` ("Listed in the workspace", "Listed in the repository the command runs in", "Outside the workspace")
- R4. A repository's list follows `git -C` and its worktrees. Check: `hooks/user-only.test.sh` ("A repository whose list makes pushing the user's")
- R5. A `.repo` list holds for its own repository only, never for projects inside it. Check: `hooks/user-only.test.sh` ("A workspace that is itself a repository")
- R6. Branches change only in a worktree, never in a main checkout another session may share. Check: `hooks/user-only.test.sh` ("Branch changes in a main checkout")
- R7. Pushes that could land on boundary's main are the user's: any refspec ending in `main` or `HEAD`. So is a push that names no branch. A named branch stays open. Check: `hooks/user-only.test.sh` ("boundary's own list")
- R8. The common shapes that stop on a permission prompt are turned away first: inline python, backticks and command substitution, process substitution, heredocs, env-var prefixes anywhere in the command and `/dev/null`. Pipes, `;` and loops aren't caught. Check: `hooks/no-prompts.test.sh`
- R9. Private paths are refused when named and when a search could reach them without naming them. Check: `hooks/private-paths.test.sh`
- R10. Every script starts through `env`, so the hooks start on NixOS. Check: `./test.sh` (first-line check)
- R11. The hooks pass shellcheck at warning level. Check: CI's shellcheck job
- R12. `init.sh` never overwrites a project's files. Check: `init.test.sh`
- R13. A workspace runs the hooks from a pinned copy only the user updates. Check: manual: the workspace's own probes of its wiring, since the pinned copy lives outside this repo
- R14. A hook that can't read its call refuses it. Check: the "Without jq" case in each hook's test file
- R15. `merge-when-green.sh` merges only once every run on the pull request's head is green, with a merge commit, and keeps a branch another open pull request is based on. A repository with no workflows merges with a note that nothing checked it. Check: `scripts/merge-when-green.test.sh`

## Passes

1. The three hooks with test cases: R1, R6, R8, R9, R12
2. Lists that follow the work: R3, R4, R5, R7
3. Hooks that start on any machine: R2, R10, R14
4. Lint for the hooks: R11
