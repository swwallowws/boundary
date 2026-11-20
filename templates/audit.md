# Audit brief

What fresh agents are given for a project's audit. `scripts/audit-due.sh <owner/repo>` says when
one is due. Copy this, fill in the parts in angle brackets, and give each agent one part of the
project. Don't give an agent your own view of the code: it reads with fresh eyes or not at all.

---

You are auditing one part of <project>: <part, such as "the server in server/", "the phone app in
ios/", "the desk in desk/">. The repository is at <path>. Read its `AGENTS.md` first: the rules
there, and the checks it lists, are what the code is meant to hold.

Read the code of your part, and enough of the others to see where they meet it. Follow
`<boundary>/rules/permissions.md` for every command. <Anything the project keeps from agents,
such as private data or a live server: what not to read or reach.>

Look for, in this order:

1. **Bugs**: concrete input or state that gives a wrong result, loses data, crashes or leaks
   something private. Name the file and line, the steps that show it and how sure you are
   (checked against the code, or likely from reading).
2. **Places where two clients behave differently** (a phone and a desk, a server and a client)
   for what should be one behaviour. Say which way each goes.
3. **Rules that no longer hold**: an `AGENTS.md` rule whose check no longer catches what it
   guards, a check that can't fail, a doc or comment that says something the code doesn't do.
4. **Structure that costs**: code written several times that should be one, files too large to
   change safely, work that grows with history (a query that reads everything, a list that never
   shrinks). Say what it would cost to fix: small, medium or large.
5. **Dead code**: routes, pages, functions or styles nothing reaches.

Report numbered findings, most serious first within each group, one or two lines each, with the
file and line. Under 1,500 words. Report only what you found in the code; leave out style
preferences and anything you can't point to.

---

## After the agents report

- Check each finding against the code before it goes anywhere. Say which were confirmed and
  which are the reviewers' reading.
- Give the user the list, numbered, with a recommendation: which to fix, in what groups, and
  which way to go where two clients differ.
- File what the user wants kept as issues labelled `audit`, one per finding, so the next
  `audit-due.sh` counts from them.
