# <project>

<One or two lines: what it is and where it runs. The README explains; this file maps.>

## Working here

1. Do what was asked, the simplest way that meets it. Side work is a proposal that says what it costs.
2. If the work grows well past what you expected, stop and say so.
3. Orient with `git log -n 20` and `git log -- <path>` before changing something that has history.
4. Run the checks below for every path you changed. Report the numbers.
5. A commit's subject names what changed and the trap if there was one. Its body says why, what ran
   and what wasn't tested.
6. When something breaks and nobody saw it, add a rule here in the same commit as the fix, with a check.
7. The user deploys, releases and merges. <Name this project's deploy and release commands.>

## Map

<Where the important code is, one line each, 20 to 40 lines. Include every docs/<topic>/ folder.>

- `src/...`: ...

## Rules

<Things a change can break without a visible error. Each gives its reason and a check: a command,
`manual: <what a person looks at>` or `none` if no script can find it yet. The most useful rules
cross files: "each new table needs a line in the backup manifest so backups include it".>

**<Rule, in a few words.>** <Why.> Check: `<command>`.

## Checks

| Changed | Run |
|---|---|
| `<path>/**` | `<command>` |
