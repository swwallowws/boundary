// Wait for every workflow run on a commit to finish, then print one line per run and exit
// non-zero if any failed or none ran. For "push, then make sure CI is green" before saying
// anything works.
//   node scripts/wait-ci.mjs owner/repo ...                  newest commit on each repo's main
//   node scripts/wait-ci.mjs --sha <commit> owner/repo       that commit, on any branch or PR
// <commit> is a hash, or a name (HEAD, a branch) that this checkout resolves.
import { execFileSync } from "node:child_process";

const args = process.argv.slice(2);
const shaAt = args.indexOf("--sha");
const given = shaAt >= 0 ? args.splice(shaAt, 2)[1] : null;
const repos = args;
const usage = "usage: node scripts/wait-ci.mjs [--sha <commit>] <owner/repo>...";
if (shaAt >= 0 && (!given || given.includes("/"))) { console.error(`--sha needs a commit. ${usage}`); process.exit(2); }
if (!repos.length) { console.error(usage); process.exit(2); }

// A name is resolved here, in the checkout it was typed in. GitHub reads HEAD as its default
// branch's head, so asking it about HEAD from a branch reported main's green run as the branch's.
// A short hash this checkout doesn't have goes to GitHub as it is; any other name is refused.
function localCommit(name) {
  try {
    return execFileSync("git", ["rev-parse", "--verify", "--quiet", `${name}^{commit}`], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return null;
  }
}
const sha = given ? (localCommit(given) ?? (/^[0-9a-f]{7,40}$/i.test(given) ? given : null)) : null;
if (given && !sha) {
  console.error(`--sha ${given}: no such commit in this checkout. A name like HEAD or a branch is resolved here, so run this from the checkout that has it, or give a hash.`);
  process.exit(2);
}

const gh = (...a) => JSON.parse(execFileSync("gh", a, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }));
// The pauses between looks, scaled down by the tests (scripts/wait-ci.test.sh).
const scale = Number(process.env.WAIT_CI_PAUSE_SCALE ?? 1);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms * scale));
const fields = "databaseId,headSha,status,conclusion,workflowName,displayTitle,url,event";

// Every run for the commit; waits for them to appear after a push. `gh run list --commit` only
// matches a full SHA, so a short one is resolved first. A commit's runs can come from a push and
// from a pull request, on any branch, so only --sha's absence limits the search to main.
async function runsFor(repo) {
  let full = null;
  if (sha) {
    try {
      full = gh("api", `repos/${repo}/commits/${sha}`).sha;
    } catch {
      return [{ repo, missing: true, why: `GitHub has no commit ${sha} in ${repo} (not pushed yet, or another repo's)` }];
    }
  }
  const list = () => {
    const runs = full
      ? gh("run", "list", "--repo", repo, "--commit", full, "--limit", "20", "--json", fields)
      : gh("run", "list", "--repo", repo, "--branch", "main", "--limit", "20", "--json", fields);
    const head = full ?? runs[0]?.headSha;
    return runs.filter((r) => r.headSha === head);
  };
  for (let i = 0; i < 20; i++) {
    if (list().length) {
      // Workflows on one commit register a few seconds apart, so look once more before settling.
      await sleep(15000);
      return list().map((r) => ({ repo, ...r }));
    }
    await sleep(5000);
  }
  return [{ repo, missing: true }];
}

let failed = 0;
const all = [];
for (const repo of repos) all.push(...(await runsFor(repo)));
while (all.some((r) => !r.missing && r.status !== "completed")) {
  await sleep(20000);
  for (const run of all) {
    if (run.missing || run.status === "completed") continue;
    try {
      Object.assign(run, gh("run", "view", String(run.databaseId), "--repo", run.repo, "--json", "status,conclusion"));
    } catch { /* a network blip: ask again next round */ }
  }
}
for (const run of all) {
  if (run.missing) { console.log(`?    ${run.repo}: ${run.why ?? `no run found${sha ? ` for ${sha}` : ""}`}`); failed++; continue; }
  // A workflow its own conditions skipped didn't fail. It didn't pass either, so it says so.
  const skipped = run.conclusion === "skipped" || run.conclusion === "neutral";
  const ok = run.conclusion === "success";
  if (!ok && !skipped) failed++;
  const mark = ok ? "ok  " : skipped ? "skip" : "FAIL";
  console.log(`${mark} ${run.repo}: ${run.workflowName} (${run.event}) "${run.displayTitle}" ${run.conclusion}${ok ? "" : `  ${run.url}`}`);
}
process.exitCode = failed ? 1 : 0;
