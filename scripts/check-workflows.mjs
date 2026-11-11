#!/usr/bin/env node
// Fails when a GitHub Actions job that may run on a self-hosted runner is given a secret. A
// self-hosted runner that keeps running between jobs lets a process one job leaves behind read
// a later job's secrets, so jobs with secrets belong on GitHub's hosted runners.
//
//   node scripts/check-workflows.mjs [repo]      (default: the current folder)
//
// Exits 1 and names each job (file, job, where it may run, the secrets it gets), 0 when none.
//
// It errs toward failing:
// - A job counts as hosted only when every runner it could get is one GitHub-hosted label on its
//   own (an exact list, below), with a matrix's values, including its include entries,
//   resolved. Anything else may be self-hosted: a custom label, a label list, a runner group,
//   any other expression, an include that is or holds one.
// - A secret is any mention of the secrets context after a ${{ in any key or value, or in any
//   if:, in any case, except GITHUB_TOKEN, which every job gets anyway. A reusable
//   workflow call that passes secrets (secrets: inherit or a mapping) fails unless it calls a
//   workflow in this repository whose jobs are all hosted.
// - A file that isn't valid YAML, or has no jobs, fails.
// The YAML is read by a real parser (vendored js-yaml), so anchors, aliases, quoting and flow
// style resolve as GitHub reads them.
//
// Out of its reach: a hosted job handing a secret on through outputs, artifacts or a cache; and
// a self-hosted runner given a hosted label (GitHub's docs don't say where such a job would go),
// so never give a self-hosted runner one.

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { load } from "./vendor/js-yaml.mjs";

const repo = process.argv[2] ?? ".";
const dir = join(repo, ".github", "workflows");
if (!existsSync(dir)) {
  console.log("check-workflows: no workflows");
  process.exit(0);
}

// GitHub-hosted standard runner labels, exactly as docs.github.com lists them (Actions,
// GitHub-hosted runners, read 2026-11-11). Labels are case-insensitive. Anything else counts as
// maybe self-hosted, larger runners included, since their owners name them. Update this list
// when GitHub adds an image; until then a job on a new label fails here, which is the safe way.
const HOSTED = new Set([
  "ubuntu-slim", "ubuntu-latest", "ubuntu-26.04", "ubuntu-24.04", "ubuntu-22.04",
  "ubuntu-26.04-arm", "ubuntu-24.04-arm", "ubuntu-22.04-arm",
  "windows-latest", "windows-2025", "windows-2025-vs2026", "windows-2022",
  "windows-11-arm", "windows-11-vs2026-arm",
  "macos-latest", "macos-26", "macos-15", "macos-26-intel", "macos-15-intel", "xcode-27",
]);
const isHostedLabel = (label) => typeof label === "string" && HOSTED.has(label.trim().toLowerCase());
// One label on its own, as a string or a one-element list, is the only shape that's hosted.
const isHostedRunsOn = (value) =>
  isHostedLabel(value) || (Array.isArray(value) && value.length === 1 && isHostedLabel(value[0]));

// Every runs-on value the job could end up with, or null when that can't be known.
function possibleRunsOn(job) {
  const runsOn = job["runs-on"];
  if (runsOn === undefined) return null;
  const expr = typeof runsOn === "string" && runsOn.match(/^\s*\$\{\{\s*matrix\.([A-Za-z_][\w-]*)\s*\}\}\s*$/);
  if (!expr) return /\$\{\{/.test(JSON.stringify(runsOn)) ? null : [runsOn];
  const matrix = job.strategy?.matrix;
  if (!matrix || typeof matrix !== "object" || Array.isArray(matrix)) return null;
  const key = expr[1];
  const values = [];
  if (key in matrix) {
    if (!Array.isArray(matrix[key])) return null;
    values.push(...matrix[key]);
  }
  // An include that's an expression, or holds one, can add any runner: it can't be placed.
  if (matrix.include !== undefined) {
    if (!Array.isArray(matrix.include)) return null;
    for (const entry of matrix.include) {
      if (!entry || typeof entry !== "object" || Array.isArray(entry)) return null;
      if (key in entry) values.push(entry[key]);
    }
  }
  if (!values.length || values.some((v) => /\$\{\{/.test(JSON.stringify(v)))) return null;
  return values;
}
const isHosted = (job) => {
  const values = possibleRunsOn(job);
  return values !== null && values.every(isHostedRunsOn);
};
const describe = (job) => (job["runs-on"] === undefined ? "no runs-on" : `runs-on: ${JSON.stringify(job["runs-on"])}`);

// The expression text in a value, keys included (GitHub evaluates expressions in some keys): for
// each string, everything after its first ${{ (a }} inside a quoted string doesn't end an
// expression for GitHub, so this doesn't try to find where one ends), and each if: whole.
function expressions(value, out = [], key = "") {
  const scan = (s, isIf) => {
    if (isIf) out.push(s);
    const at = s.indexOf("${{");
    if (at >= 0) out.push(s.slice(at + 3));
  };
  if (typeof value === "string") scan(value, key === "if");
  else if (Array.isArray(value)) value.forEach((v) => expressions(v, out));
  else if (value && typeof value === "object") {
    for (const [k, v] of Object.entries(value)) {
      scan(k, false);
      expressions(v, out, k);
    }
  }
  return out;
}
const GITHUB_TOKEN = /\bsecrets\s*(\.\s*github_token\b|\[\s*['"]github_token['"]\s*\])/gi;
const secretsIn = (value) =>
  [...new Set(expressions(value).map((e) => e.replace(GITHUB_TOKEN, "").replace(/\}\}\s*$/, "").trim()).filter((e) => /\bsecrets\b/i.test(e)))];

const files = readdirSync(dir).filter((f) => /\.ya?ml$/i.test(f)).sort();
const parsed = new Map();
const problems = [];
for (const file of files) {
  const where = join(".github", "workflows", file);
  try {
    parsed.set(file, load(readFileSync(join(dir, file), "utf8")));
  } catch (e) {
    problems.push(`${where}: can't read it as YAML (${e.reason ?? e.message})`);
  }
}

// A workflow in this repository whose jobs are all hosted, for reusable calls that pass secrets.
function callsOnlyHosted(uses) {
  const local = typeof uses === "string" && uses.match(/^\.\/\.github\/workflows\/([^@/]+\.ya?ml)$/i);
  const callee = local && parsed.get(local[1]);
  const jobs = callee?.jobs;
  if (!jobs || typeof jobs !== "object") return false;
  return Object.values(jobs).every((job) => job && typeof job === "object" && job.uses === undefined && isHosted(job));
}

for (const [file, doc] of parsed) {
  const where = join(".github", "workflows", file);
  const jobs = doc && typeof doc === "object" ? doc.jobs : undefined;
  if (!jobs || typeof jobs !== "object" || Array.isArray(jobs) || !Object.keys(jobs).length) {
    problems.push(`${where}: has no jobs it can read`);
    continue;
  }
  const everyJob = secretsIn(doc.env ?? {});
  for (const [name, job] of Object.entries(jobs)) {
    if (!job || typeof job !== "object") {
      problems.push(`${where}: job ${name} isn't a mapping`);
      continue;
    }
    if (job.uses !== undefined) {
      // A caller's workflow-level env doesn't reach the called workflow (GitHub docs, reusing
      // workflows), so only what the call itself passes counts.
      const passes = job.secrets === "inherit" || secretsIn(job.secrets ?? {}).length || secretsIn(job.with ?? {}).length;
      if (passes && !callsOnlyHosted(job.uses)) {
        problems.push(`${where}: job ${name} passes secrets to ${job.uses}, which may run on a self-hosted runner`);
      }
      continue;
    }
    if (isHosted(job)) continue;
    const given = [...new Set([...everyJob, ...secretsIn(job)])];
    if (given.length) {
      problems.push(`${where}: job ${name} may run on a self-hosted runner (${describe(job)}) and is given: ${given.join(" | ")}`);
    }
  }
}

for (const p of problems) console.log(p);
if (problems.length) process.exit(1);
console.log(`check-workflows: no job that may run on a self-hosted runner is given a secret (${files.length} workflow${files.length === 1 ? "" : "s"})`);
