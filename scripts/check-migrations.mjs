// Fails when a change edits, removes or renames a migration that already exists. A live
// database has run every migration in the folder, and a migration tool such as sqlx refuses to
// start once one it applied has changed or gone, so a migration may only be added.
//
// Run in CI from the repository's root:
//   node <boundary>/scripts/check-migrations.mjs <folder> <base>
// <base> is the commit the change starts from: on a pull request the main it merges into
// (`HEAD^1` on GitHub's merge commit), on a push the commit main was on before
// (`github.event.before`). The diff runs from where the change left <base> (three dots), so a
// migration <base> gained since is never read as one this change removed. An empty or all-zero
// <base> (a branch's first push) checks nothing. Needs the history back to <base>
// (`fetch-depth: 0`).

import { execFileSync } from "node:child_process";

const [folder, base] = process.argv.slice(2);
if (!folder) {
  console.error("usage: node check-migrations.mjs <folder> <base>");
  process.exit(2);
}
if (!base || /^0+$/.test(base)) {
  console.log(`migrations: no base commit, nothing checked in ${folder}`);
  process.exit(0);
}

let diff;
try {
  diff = execFileSync("git", ["diff", "--name-status", "--no-renames", `${base}...HEAD`, "--", folder], { encoding: "utf8" });
} catch (e) {
  console.error(`migrations: can't compare with ${base}: ${e.stderr?.toString().trim() || e.message}`);
  process.exit(1);
}
const touched = diff
  .split("\n")
  .filter(Boolean)
  .map((line) => line.split("\t"))
  .filter(([status]) => status !== "A")
  .map(([status, path]) => `${status === "D" ? "removed" : "changed"}: ${path}`);
if (touched.length) {
  console.error(`migrations: an applied migration may only be added to, never ${touched.length === 1 ? "this" : "these"}:`);
  for (const t of touched) console.error(`  ${t}`);
  console.error("Add a new numbered migration instead.");
  process.exit(1);
}
console.log(`migrations: only added in ${folder}`);
