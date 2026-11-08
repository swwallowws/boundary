# <Topic>

<Written only for a step that is hard to reverse (a schema, a protocol, auth, money) or that spans
sessions. Everything else goes straight to code and a commit that says why. Lives in
docs/<topic>/ and stays current while the work runs.>

## Status

| Pass | State |
|---|---|
| 1. <name> | open |

## Today

<How it works now, with file references and a measured baseline if the work changes a number.>

## Design

<The target and the reasoning: what was chosen, what was ruled out and why.>

## Requirements

<One line each, ending with its check: a command, a test's name, `manual: <what a person looks
at>` or `none` with the reason no check is possible yet. `scripts/spec-checks.sh` fails on a
requirement with no check.>

- R1. <What must hold.> Check: `<command or test name>`
- R2. <What must hold.> Check: manual: <what to look at>

## Passes

<The steps, each naming the requirements it meets. Use the project's checks before writing new ones.>

1. <name>: R1, R2
