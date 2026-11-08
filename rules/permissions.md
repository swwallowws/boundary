# Working without permission prompts

Rules for an agent and its subagents in any project that uses boundary, so work runs without
stopping on permission prompts. A background subagent cannot answer its own prompt: it goes to
the user while the agent waits for an answer. The only real fix is that every action already
matches an allow rule or needs none.

Sources: code.claude.com/docs/en/permissions.md, permission-modes.md, sub-agents.md,
settings-reference.md.

## Rules

1. **Stay inside the working directories.** With `permissions.blockReadsOutsideWorkingDirectories`
   on, reading, running or naming any path outside them prompts (for example /tmp or ~/.claude).
   Put scratch files inside the project, in a gitignored folder. If a tool from outside is needed,
   copy it into the project once. `/dev/null` is outside them too, so write throwaway output to
   a file in the project's scratch folder. Symlinks count by their target: a virtualenv's `bin/python`
   points outside the project, so never list or read inside `.venv`; only run its commands. Keep
   one venv per project at `.venv` and allowlist it.
2. **Use the file tools** (Read, Edit, Write, Grep) instead of cat, head, tail, sed, awk or
   echo-redirects. They are pre-approved inside the working directories.
3. **One plain command per Bash call.** Compound commands are split at `&&`, `||`, `;`, `|`, `&`
   and newlines. Every part must match an allow rule on its own, so a compound usually prompts.
   - Never prefix with `cd dir &&`. Use project-relative paths or `git -C <path>`.
   - Never use an env-var prefix (`FOO=1 cmd`). Use a command-line flag instead.
   - Redirect targets (`> file`) are checked separately; write files with the Write tool.
   - Quote a path with spaces. A backslash before a space triggers a prompt.
4. **Commands must be parseable.** Otherwise the checker asks the user. Never use heredocs (`<<EOF`),
   `$(...)` or backticks, process substitution, `for`/`while` loops, backslash line
   continuations or quotes nested in quotes. Anything longer than one line goes in a script
   file, run by its path. No `python -c`.
   - `gh api repos/...` prompts too: the checker reads the endpoint as a path it cannot verify.
     For GitHub metadata use `gh repo view`, `gh run list` or a script that calls `gh api`.
5. **Commit messages:** one `git commit` call with one `-m "..."` flag per paragraph.
6. **Never edit permission settings, `.claude/` settings files, git hooks or CLAUDE.md on your
   own.** Those changes come from the user. Never push or use `--no-verify` without being asked.
7. **If a needed command does not fit these rules, stop and ask** (a subagent reports
   NEEDS_CONTEXT naming the exact command). Do not look for a way around a prompt or a block.

## Setting it up per project

- Add the project's routine commands as allow rules in `<project>/.claude/settings.json`, in the
  exact form they will be run, for example `"Bash(.venv/bin/pytest:*)"`, `"Bash(git commit:*)"`.
- `/add-dir` only lasts for the session. For a directory that should always count as a working
  directory, add it to `additionalDirectories` in a settings file.
- `/fewer-permission-prompts` scans past sessions and proposes an allowlist.
- Subagents run in the main session's mode and follow its allow and deny rules.
